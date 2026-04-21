/**
 * @description Abstract base class for integration services
 */
public abstract class AbstractIntegrationService {
    @TestVisible
    private static final String DEFAULT_TIMEOUT = '30000';
    
    @TestVisible protected Integration_Endpoint__mdt endpoint;
    @TestVisible protected Integration_Mapping__mdt mapping;
    protected Map<String, Object> configuration;
    
    /**
     * @description Constructor that initializes the service with endpoint and mapping configurations
     * @param endpointName The developer name of the Integration_Endpoint__mdt record
     * @param mappingName The developer name of the Integration_Mapping__mdt record
     */
    public AbstractIntegrationService(String endpointName, String mappingName) {
        // Changed Logger call to be generic to avoid potential issues with logger processing names in constructor
        Logger.info('Initializing integration service...');
        
        this.loadConfigurations(mappingName);
        this.configuration = new Map<String, Object>();
    }
    
    /**
     * @description Loads endpoint and mapping configurations
     * @param mappingName The developer name of the mapping configuration
     */
    private void loadConfigurations(String mappingName) {
        try {
            this.mapping = IntegrationMappingCache.getMappingByName(mappingName);
            if (this.mapping == null) {
                throw new IntegrationException('Mapping not found: ' + mappingName);
            }
            
            // Set endpoint from relationship
            this.endpoint = mapping.Endpoint__r;
            this.validateConfigurations();
            
        } catch (Exception e) {
            // Modified Logger call
            Logger.error('Failed to load integration configurations: ' + e.getMessage());
            throw new IntegrationException('Failed to load integration configurations: ' + e.getMessage());
        }
    }
    
    /**
     * @description Validates the loaded configurations
     */
    protected void validateConfigurations() {
        List<String> errors = new List<String>();
        
        if (mapping == null) {
            errors.add('Mapping configuration not found');
        } else {
            if (!mapping.Active__c) {
                errors.add('Mapping configuration is inactive');
            }
            
            if (endpoint == null) {
                errors.add('No endpoint configured for mapping');
            } else {
                if (!endpoint.Active__c) {
                    errors.add('Endpoint configuration is inactive');
                }
                if (String.isBlank(endpoint.Named_Credential__c)) {
                    errors.add('Named Credential is required');
                }
            }
        }
        
        if (!errors.isEmpty()) {
            String errorMsg = String.join(errors, ', ');
            throw new IntegrationException(errorMsg);
        }
        Logger.info('Integration configurations validated successfully.');
    }
    
    /**
     * @description Loads and processes the Dataweave mapping
     * @param data The data to transform
     * @return The transformed data
     */
    public List<SObject> processDataweaveMapping(String responseBody) {
        System.debug(LoggingLevel.DEBUG, 'DataWeave map: ' + mapping.Dataweave_Map_Name__c);
        System.debug(LoggingLevel.DEBUG, 'DataWeave payload summary: ' + summarizeTextForLog(responseBody));
        try {
            DataWeave.Script dScript = selectDataWeavePullScript(mapping.Dataweave_Map_Name__c);
            DataWeave.Result dResult = dScript.execute(
                    new Map<String, Object>{ 'payload' => responseBody }
            );
            String transformedJson = dResult.getValueAsString();
            System.debug(LoggingLevel.DEBUG, 'DataWeave transformed summary: ' + summarizeTextForLog(transformedJson));

            List<SObject> recordsList = (List<SObject>) JSON.deserialize(transformedJson, List<SObject>.class);
            Logger.debug('Deserialized ' + (recordsList != null ? recordsList.size() : 0) + ' records');

            return recordsList;
            
        } catch (Exception e) {
            Logger.error('Failed to process Dataweave mapping for: ' + mapping.Dataweave_Map_Name__c + ' - Exception: ' + e.getMessage() + '\nStack trace: ' + e.getStackTraceString());
            Logger.saveLog();
            throw new IntegrationException('Failed to process Dataweave mapping: ' + e.getMessage());
        }
    }

    @TestVisible
    public static String summarizeTextForLog(String value) {
        if (value == null) {
            return 'null';
        }

        return 'len=' + value.length();
    }
    
    /**
     * @description Makes an HTTP callout to the configured endpoint using Named Credentials
     * @param method The HTTP method to use
     * @param urlPath The URL path to append to the Named Credential base URL
     * @return HttpResponse The response from the endpoint
     */
    @TestVisible protected HttpResponse makeCallout(String method, String urlPath) {
        return makeCallout(method, urlPath, null);
    }

    /**
     * @description Makes an HTTP callout with a separate request body (used for GraphQL POST requests)
     * @param method The HTTP method to use
     * @param urlPath The URL path to append to the Named Credential base URL
     * @param requestBody The request body to send (null for GET requests)
     * @return HttpResponse The response from the endpoint
     */
    @TestVisible protected HttpResponse makeCallout(String method, String urlPath, String requestBody) {
        try {
            Http http = new Http();
            HttpRequest request = new HttpRequest();

            // Build the endpoint URL using Named Credentials
            String baseUrl = 'callout:' + endpoint.Named_Credential__c;
            request.setEndpoint(baseUrl + (urlPath != null ? urlPath : ''));
            request.setMethod(method);

            Integer timeout = endpoint.Timeout__c != null ?
                Integer.valueOf(endpoint.Timeout__c) :
                Integer.valueOf(DEFAULT_TIMEOUT);
            request.setTimeout(timeout);

            if (String.isNotBlank(requestBody)) {
                request.setBody(requestBody);
                request.setHeader('Content-Type', 'application/json');
            }
            Logger.debug('Making HTTP callout to ' + baseUrl + urlPath + ' via ' + endpoint.Named_Credential__c);

            HttpResponse response = http.send(request);
            logResponse(response);

            return response;

        } catch (Exception e) {
            Logger.error('HTTP callout failed: ' + e.getMessage());
            throw new IntegrationException('HTTP callout failed: ' + e.getMessage());
        }
    }
    
    /**
     * @description Logs the HTTP response using Nebula Logger
     * @param response The HTTP response to log
     */
    private void logResponse(HttpResponse response) {
        String logMessage = 'HTTP Response: ' + response.getStatusCode() + ' ' + response.getStatus();
        
        if (response.getStatusCode() >= 400) {
            Logger.error(logMessage);
        } else {
            Logger.debug(logMessage);
        }
    }

    public static DataWeave.Script selectDataWeavePullScript(String objectType) {
        String scriptName = 'DataWeaveScriptResource.' + objectType;
        try {
            Logger.debug('Attempting to load DataWeave script: ' + scriptName);
            
            Type scriptType = Type.forName(scriptName);
            if (scriptType != null) {
                Logger.debug('Found DataWeave script for objectType: ' + objectType + ', scriptName: ' + scriptName);
                Logger.saveLog();
                return (DataWeave.Script) scriptType.newInstance();
            } else {
                Logger.error('No Dataweave script found for objectType: ' + objectType + ', scriptName: ' + scriptName);
                Logger.saveLog();
                throw new IllegalArgumentException('No Dataweave script found for: ' + objectType);
            }
        } catch (Exception e) {
            Logger.error('Error loading DataWeave script for objectType: ' + objectType + ', scriptName: ' + scriptName + ' - Exception: ' + e.getMessage() + '\nStack trace: ' + e.getStackTraceString());
            Logger.saveLog();
            throw new IllegalArgumentException('Error instantiating Dataweave script for: ' + objectType);
        }
    }
    
    public class IntegrationException extends Exception {}
}
