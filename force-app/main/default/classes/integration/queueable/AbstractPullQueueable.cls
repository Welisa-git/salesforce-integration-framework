/**
 * @description Abstract base class for pull queueable operations
 * Provides core functionality for pulling and processing external data
 */
public abstract class AbstractPullQueueable extends AbstractIntegrationService implements Queueable, Database.AllowsCallouts {
    
    @TestVisible protected final String operationName;
    @TestVisible protected final DateTime lastRunTime;
    @TestVisible protected PaginationState paginationState;
    protected final String mappingName;
    @TestVisible protected Integer currentSyncOrder;
    private final String LAST_RUN_KEY = 'LastRunTime_';
    
    protected String endpointName;
    
    // Store the sync service instance for reuse within the execute method
    private transient TypedSyncService currentSyncServiceInstance;
    
    /**
     * @description Constructor for AbstractPullQueueable
     * @param endpointName Developer name of the endpoint configuration
     * @param mappingName Developer name of the mapping configuration
     * @param operationName Name of the operation for tracking
     * @param lastRunTime Last successful run time for this operation
     * @param paginationState Current pagination state (null for first page)
     * @param syncOrder The current sync order for the mapping
     */
    public AbstractPullQueueable(String endpointName, String mappingName, String operationName, 
                            DateTime lastRunTime, PaginationState paginationState, Integer syncOrder) {
        super(endpointName, mappingName);
        this.operationName = operationName;
        this.lastRunTime = lastRunTime;
        this.paginationState = paginationState;
        this.endpointName = endpointName;
        this.mappingName = mappingName;
        this.currentSyncOrder = syncOrder;
        // Batch size logging moved to execute method where it's expected to be initialized
    }
    
    /**
     * @description Main execute method for the queueable
     * @param ctx QueueableContext provided by the system
     */
    public void execute(QueueableContext ctx) {
        try {
            // Initialize logger tags if Nebula Logger is enabled
            initializeLoggerTags();
            
            applyTags(Logger.info('Starting integration execution for: ' + operationName + ' (Endpoint: ' + endpointName + ', Mapping: ' + mappingName + ')'));
            // Log batch size here, assuming it's initialized by now (e.g., via mapping or subclass)
            // If batchSize isn't a member, remove this log or adjust how it's determined
            // Logger.info('Batch Size: ' + this.batchSize); 
            
            // Validate essential properties
            if (String.isBlank(endpointName) || String.isBlank(mappingName) || mapping == null) {
                Logger.error('Required parameters or mapping are missing/null. EndpointName: ' + endpointName + ', MappingName: ' + mappingName);
                return;
            }
            
            // Instantiate the TypedSyncService ONCE for this execution
            this.currentSyncServiceInstance = getSyncServiceInstance(mapping.Target_Object__c);
            if (this.currentSyncServiceInstance != null) {
                 Logger.debug('Instantiated sync service for ' + mapping.Target_Object__c + ' for this transaction.');
            }

            IntegrationResult result = pullAndProcessRecords();
            if (result == null) {
                Logger.error('Pull operation returned null result');
                return;
            }
            
            if (!result.isSuccess) {
                Logger.error('Pull operation failed: ' + (result.message != null ? result.message : 'No error message provided'));
                return;
            }

            // After processing records
            if (result != null && result.isSuccess) {
                applyTags(Logger.info('Successfully pulled data from external system for ' + operationName));
            }

            PaginationResult pageResult = handlePaginationResult(result);
            if (pageResult == null) {
                Logger.info('No pagination result or completed pagination for ' + operationName);
                saveLastRunTime(DateTime.now());
                return;
            }

            // Get record count before processing
            Integer recordCount = pageResult.getSObjects() != null ? pageResult.getSObjects().size() : 0;
            Logger.info('Processing ' + recordCount + ' records for ' + operationName);

            // Process records before checking pagination
            processRecords(pageResult);

            // After processing, log next steps
            if (pageResult.getHasMoreData() && pageResult.getNextState() != null) {
                Logger.info('More data available, enqueueing next batch for ' + operationName);
                this.paginationState = pageResult.getNextState();
                System.enqueueJob(this);
            } else {
                Logger.info('Integration completed for ' + operationName + ', no more data available');
                saveLastRunTime(DateTime.now());
            }
        } catch (Exception e) {
            applyTags(Logger.error('Pull operation failed: ' + e.getMessage() +
                        '\nStack trace: ' + e.getStackTraceString()));
            throw e;
        }
    }

    /**
     * @description Orchestrates fetching data, transforming, processing, and upserting.
     *              Subclasses MUST implement this method to define the specific pull logic.
     */
    // Declared abstract to force implementation in subclasses
    protected abstract IntegrationResult pullAndProcessRecords();

    /**
     * @description Process the records from the pagination result
     * @param pageResult The pagination result containing records and metadata
     */
    protected void processRecords(PaginationResult pageResult) {
        // Validate input parameter
        if (pageResult == null) {
            Logger.debug('No pagination result to process');
            return;
        }
        
        List<SObject> transformedSObjects = pageResult.getSObjects();
        if (transformedSObjects == null || transformedSObjects.isEmpty()) {
            Logger.debug('No records to process in pagination result');
            return;
        }
        
        // *** Directly call processSObjects on the stored instance ***
        List<SObject> recordsToUpsert;
        if (this.currentSyncServiceInstance != null) {
            try {
                Logger.debug('Calling overridden processSObjects on sync service instance for ' + transformedSObjects.size() + ' records.');
                recordsToUpsert = this.currentSyncServiceInstance.processSObjects(transformedSObjects);
                Logger.debug('Finished overridden processSObjects call.');
                // Ensure we have a list, even if processing returns null
                if (recordsToUpsert == null) recordsToUpsert = new List<SObject>(); 
            } catch (Exception e) {
                 Logger.error('Error during overridden processSObjects for ' + mapping.Target_Object__c + ': ' + 
                            e.getMessage() + '\n' + e.getStackTraceString());
                 // Decide how to handle error - skip upsert for this batch?
                 recordsToUpsert = new List<SObject>(); 
            }
        } else {
            // If no specific service instance, use the transformed records directly
            recordsToUpsert = transformedSObjects;
        }
        
        // If processing resulted in an empty list, skip upsert
        if (recordsToUpsert.isEmpty()) {
            Logger.debug('No records remaining after calling processSObjects. Skipping upsert.');
            return;
        }

        // Validate endpoint configuration (can stay here or move)
        if (endpoint == null) {
            Logger.error('Endpoint configuration is null');
            return;
        }
        
        String externalIdField = !String.isBlank(mapping.External_Id_Field_Overide__c)
            ? mapping.External_Id_Field_Overide__c
            : endpoint.External_ID_Field__c;
        if (String.isBlank(externalIdField)) {
            Logger.error('External ID field not configured for endpoint: ' + endpointName);
            return;
        }

        try {
            // Safe access to first record to get SObject type (use the list going to upsert)
            SObject firstRecord = recordsToUpsert[0]; 
            if (firstRecord == null) {
                Logger.error('First record is null despite list not being empty');
                return;
            }
            
            // Get the SObject field for external ID
            Schema.SObjectType sObjectType = firstRecord.getSObjectType();
            if (sObjectType == null) {
                Logger.error('Could not determine SObject type');
                return;
            }
            
            Schema.DescribeSObjectResult describe = sObjectType.getDescribe();
            Map<String, Schema.SObjectField> fieldMap = describe?.fields?.getMap();
            if (fieldMap == null) {
                Logger.error('Could not retrieve field map for ' + sObjectType);
                return;
            }
            
            Schema.SObjectField externalIdFieldToken = fieldMap.get(externalIdField);
            if (externalIdFieldToken == null) {
                Logger.error('External ID field ' + externalIdField + ' not found on ' + sObjectType);
                return;
            }
            if (!externalIdFieldToken.getDescribe().isExternalId() && !externalIdFieldToken.getDescribe().isIdLookup()) {
                Logger.error('Field ' + externalIdField + ' is not marked as External ID on ' + sObjectType);
                return;
            }

            // Perform the upsert using the PRE-PROCESSED list
            Logger.info('Starting upsert operation for: ' + describe.getName() + ' records: ' + recordsToUpsert.size());
            Database.UpsertResult[] results = Database.upsert(recordsToUpsert, externalIdFieldToken, false);
            if (results != null) {
                // Pass the PRE-PROCESSED list to handleUpsertResults
                handleUpsertResults(results, recordsToUpsert, describe.getName(), pageResult);
            } else {
                Logger.error('Upsert operation returned null results');
            }
        } catch (Exception e) {
            Logger.error('Failed to upsert records: ' + e.getMessage() + '\n' + e.getStackTraceString());
            Logger.saveLog(); // Save logs when exception occurs
            throw e;
        }
    }


    /**
     * @description Handle upsert results and log errors
     * @param results The upsert results
     * @param records The *original* pre-processed records that were upserted
     * @param objectType The type of object being processed
     * @param pageResult The pagination result containing metadata
     */
    @TestVisible
    private void handleUpsertResults(Database.UpsertResult[] results, List<SObject> records, String objectType, PaginationResult pageResult) {
        // Validate input parameters
        if (results == null || records == null || results.size() != records.size()) {
            Logger.error('Invalid upsert results or records. Results size: ' + (results != null ? String.valueOf(results.size()) : 'null') + 
                        ', Records size: ' + (records != null ? String.valueOf(records.size()) : 'null'));
            return;
        }
        
        if (String.isBlank(objectType)) {
            objectType = 'Unknown';
        }
        
        // Safely get external ID field name
        String externalIdField = endpoint?.External_ID_Field__c;
        if (String.isBlank(externalIdField)) {
            externalIdField = 'Id';
        }

        Integer successCount = 0;
        Integer failureCount = 0;
        List<String> failedIds = new List<String>();

        // Prepare lists for post-processing hook
        List<SObject> successfulUpserts = new List<SObject>();
        Map<Id, SObject> originalRecordsMap = new Map<Id, SObject>();

        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                successCount++;
                // Capture successful record and its original state for post-processing
                Id recordId = results[i].getId();
                SObject originalRecord = records[i];

                // Create a representation of the successful record with its ID
                // Note: Cloning might not be strictly necessary if the original list isn't modified elsewhere,
                // but it provides a safer snapshot.
                SObject successfulRecord = originalRecord.clone(false, true, true, false); 
                successfulRecord.Id = recordId; 
                
                successfulUpserts.add(successfulRecord);
                originalRecordsMap.put(recordId, originalRecord);

            } else {
                failureCount++;
                // Safe access to failed record
                SObject failedRecord = records[i];
                String externalId = '';
                
                try {
                    // Safely retrieve external ID value
                    if (failedRecord != null && failedRecord.get(externalIdField) != null) {
                        externalId = String.valueOf(failedRecord.get(externalIdField));
                        failedIds.add(externalId);
                    }
                } catch (Exception e) {
                    externalId = 'Error retrieving external ID: ' + e.getMessage();
                }
                
                // Log each error for the record
                if (results[i].getErrors() != null) {
                    for (Database.Error error : results[i].getErrors()) {
                        String errorMessage = error != null ? error.getMessage() : 'No error message';
                        Boolean isKnownQuoteLineItemError =
                            objectType == 'QuoteLineItem' &&
                            errorMessage?.startsWith('❌ Upsert error on QuoteLineItem: Elfsquad_Id__c=');

                        if (!isKnownQuoteLineItemError) {
                            Logger.error('DML Error for ' + objectType + ' record ' + externalId + ': ' + errorMessage);
                        }
                    }
                }
            }
        }
        
        // Add more detailed failure logging
        if (failureCount > 0) {
            Logger.warn('Failed to upsert ' + failureCount + ' ' + objectType + ' records');
            // Log first few failures with details
            Integer loggedFailures = 0;
            for (Integer i = 0; i < results.size() && loggedFailures < 5; i++) {
                if (!results[i].isSuccess()) {
                    SObject failedRecord = records[i];
                    String externalId = failedRecord.get(externalIdField) != null ? 
                        String.valueOf(failedRecord.get(externalIdField)) : 'Unknown';
                    
                    String errorMsg = '';
                    for (Database.Error error : results[i].getErrors()) {
                        errorMsg += error.getMessage() + '; ';
                    }
                    
                    Logger.warn('Failed record: ' + externalId + ' - Errors: ' + errorMsg);
                    loggedFailures++;
                }
            }
        }
        
        // === START Post-processing Hook ===
        if (!successfulUpserts.isEmpty()) {
            // Use the STORED instance variable, not a new instance
            if (this.currentSyncServiceInstance != null) { 
                try {
                    Logger.debug('Calling postProcessUpsert for ' + objectType + 
                                ' using stored sync service instance with ' + successfulUpserts.size() + ' records.');
                    // Call postProcessUpsert on the STORED instance
                    this.currentSyncServiceInstance.postProcessUpsert(successfulUpserts, originalRecordsMap);
                    Logger.debug('Finished postProcessUpsert for ' + objectType);
                } catch (Exception e) {
                    Logger.error('Error during postProcessUpsert for ' + objectType + ': ' + 
                                e.getMessage() + '\n' + e.getStackTraceString());
                }
            } else {
                 Logger.debug('No typed sync service registered for ' + objectType + '; skipping postProcessUpsert.');
            }
        }
        // === END Post-processing Hook ===

        Logger.info('Integration progress for ' + operationName + ': ' + successCount + ' successful, ' + failureCount + ' failed');
        Logger.saveLog(); // Save logs after processing results
    }

    /**
     * @description Extract pagination result from integration result
     * @param result The integration result containing pagination data
     * @return PaginationResult The extracted pagination result or null
     */
    private PaginationResult handlePaginationResult(IntegrationResult result) {
        // Validate input parameter
        if (result == null || result.additionalDetails == null) {
            return null;
        }
        
        Object pageResultObj = result.additionalDetails.get('paginationResult');
        if (pageResultObj == null) {
            return null;
        }
        
        if (!(pageResultObj instanceof PaginationResult)) {
            Logger.error('Expected PaginationResult but found ' + String.valueOf(pageResultObj));
            return null;
        }
        
        return (PaginationResult)pageResultObj;
    }
    
    /**
     * @description Saves the last successful run time per mapping to Integration_Pagination_State__c
     * @param runTime The time to save
     */
    protected void saveLastRunTime(DateTime runTime) {
        if (runTime == null) {
            runTime = DateTime.now();
        }
        
        if (String.isBlank(mappingName)) {
            Logger.error('Cannot save last run time: mapping name is blank');
            return;
        }
        
        try {
            Integration_Pagination_State__c state = Integration_Pagination_State__c.getInstance(mappingName);
            if (state == null) {
                state = new Integration_Pagination_State__c(Name = mappingName);
            }
            state.Last_Run_Date__c = runTime;
            upsert state Name;
            Logger.debug('Saved last run time for mapping ' + mappingName + ': ' + runTime);
        } catch (Exception e) {
            Logger.error('Failed to save last run time for ' + mappingName + ': ' + e.getMessage());
        }
    }
    
    /**
     * @description Gets the last successful run time for a given mapping or operation name
     * @param operationName The mapping name to look up
     * @return DateTime The last run time or null if never run
     */
    public static DateTime getLastRunTime(String operationName) {
        if (String.isBlank(operationName)) {
            Logger.error('Operation name cannot be null or blank');
            return null;
        }
        
        try {
            Integration_Pagination_State__c state = Integration_Pagination_State__c.getInstance(operationName);
            return state?.Last_Run_Date__c;
        } catch (Exception e) {
            Logger.error('Failed to get last run time for ' + operationName + ': ' + e.getMessage());
            return null;
        }
    }

    // Add new method to get mapping with caching
    protected Integration_Mapping__mdt getCurrentMapping() {
        return IntegrationMappingCache.getMappingByEndpointAndOrder(endpointName, currentSyncOrder);
    }
    
    private static Integration_Mapping__mdt getMappingFromCache(String endpointName, Decimal syncOrder) {
        return IntegrationMappingCache.getMappingByEndpointAndOrder(endpointName, syncOrder);
    }
    
    protected Decimal getMaxSyncOrderForEndpoint() {
        return IntegrationMappingCache.getMaxSyncOrderForEndpoint(endpointName);
    }
    
    protected Integration_Mapping__mdt getNextMapping(Decimal nextSyncOrder) {
        return IntegrationMappingCache.getMappingByEndpointAndOrder(endpointName, nextSyncOrder);
    }

    // Helper method to get Sync Service Instance
    // Note: All lookups and transformations are handled by DataWeave in Mule
    // Apex sync services are kept only for backward compatibility with legacy mappings
    private TypedSyncService getSyncServiceInstance(String targetObject) {
        if (String.isBlank(targetObject)) {
            return null;
        }
        
        // Try to load object-specific service (for backward compatibility only)
        try {
            String className = targetObject + 'SyncService';
            Type serviceType = Type.forName(className);
            if (serviceType != null) {
                Object instance = serviceType.newInstance();
                if (instance instanceof TypedSyncService) {
                    Logger.debug('Using object-specific sync service: ' + className);
                    return (TypedSyncService) instance;
                }
            }
        } catch (Exception e) {
            Logger.debug('No sync service for ' + targetObject + ', all processing handled by DataWeave');
        }
        
        return null;
    }

    /**
     * @description Check if Nebula Logger is enabled for the current endpoint
     * @return Boolean True if Nebula Logger is enabled, false otherwise
     */
    private Boolean isNebulaLoggerEnabled() {
        if (endpoint == null) {
            return false;
        }
        try {
            // Dynamic access to avoid compilation error if field doesn't exist yet
            Object enableNebulaValue = endpoint.get('Enable_Nebula_Logger__c');
            return enableNebulaValue != false;
        } catch (Exception e) {
            // Field doesn't exist or can't be accessed - default to false
            return false;
        }
    }

    /**
     * @description Parsed logger tags from mapping's Logger_Tags__c field, applied to Nebula Logger entries
     */
    @TestVisible
    protected List<String> loggerTags = new List<String>();

    private void initializeLoggerTags() {
        loggerTags = new List<String>();
        if (!isNebulaLoggerEnabled() || mapping == null) {
            return;
        }
        try {
            Object tagsValue = mapping.get('Logger_Tags__c');
            if (tagsValue == null || String.isBlank(String.valueOf(tagsValue))) {
                return;
            }
            for (String tag : String.valueOf(tagsValue).split(',')) {
                String t = tag.trim();
                if (String.isNotBlank(t)) {
                    loggerTags.add(t);
                }
            }
        } catch (Exception e) {
            Logger.error('Failed to initialize logger tags: ' + e.getMessage());
        }
    }

    /**
     * @description Applies loggerTags to a Nebula Logger entry builder
     * @param entry The LogEntryEventBuilder returned by Logger.info/warn/error/debug
     */
    @TestVisible
    protected void applyTags(LogEntryEventBuilder entry) {
        if (entry != null && !loggerTags.isEmpty()) {
            for (String tag : loggerTags) {
                entry.addTag(tag);
            }
        }
    }
}
