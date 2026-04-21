/**
 * @description Abstract base class for pagination strategies
 * Provides extension points for custom pagination implementations
 */
public abstract class PaginationStrategy {
    
    protected Integration_Endpoint__mdt endpoint;
    protected Integration_Mapping__mdt mapping;
    protected DateTime lastRunTime;
    
    /**
     * @description Initialize the strategy with configuration
     * @param endpoint The endpoint configuration
     * @param mapping The mapping configuration
     * @param lastRunTime The last run time for incremental sync
     */
    public virtual void initialize(Integration_Endpoint__mdt endpoint, Integration_Mapping__mdt mapping, DateTime lastRunTime) {
        // Validate input parameters
        if (endpoint == null) {
            throw new IllegalArgumentException('Endpoint configuration cannot be null');
        }
        
        if (mapping == null) {
            throw new IllegalArgumentException('Mapping configuration cannot be null');
        }
        
        this.endpoint = endpoint;
        this.mapping = mapping;
        this.lastRunTime = lastRunTime; // can be null for full sync
        
        String targetObject = mapping.Target_Object__c != null ? mapping.Target_Object__c : 'Not specified';
        String syncOrder = mapping.Sync_Order__c != null ? String.valueOf(mapping.Sync_Order__c) : 'Not specified';
        
        Logger.debug('Initialized strategy with endpoint: ' + endpoint.DeveloperName + 
                    ', mapping: ' + mapping.DeveloperName +
                    ', target object: ' + targetObject +
                    ', sync order: ' + syncOrder);
    }
    
    /**
     * @description Core method to process API response and handle pagination
     * @param response The HTTP response from the API call
     * @param state Current pagination state
     * @return PaginationResult containing processed records and next state
     */
    public abstract PaginationResult processResponse(HttpResponse response, PaginationState state);

    /**
     * @description Processes the list of SObjects after initial deserialization.
     *              NOTE: This method is now DELEGATED. The actual call to
     *              TypedSyncService.processSObjects happens in AbstractPullQueueable
     *              using a persistent instance.
     * @param sObjects List of deserialized SObjects
     * @return List<SObject> The original list (or empty list if input is null).
     */
    public virtual List<SObject> processSObjects(List<SObject> sObjects) {
        // This method is now primarily a pass-through. The TypedSyncService logic
        // is handled directly by the Queueable to maintain instance state.
        Logger.debug('PaginationStrategy.processSObjects: Returning input list. Object-specific processing delegated to Queueable.');
        return sObjects != null ? sObjects : new List<SObject>();
    }
    
    /**
     * @description Get the appropriate sync service instance for the target object.
     *              NOTE: This is now primarily used by the Queueable at the start
     *              of its execution, not repeatedly by the strategy.
     * @param targetObject The target object name from the mapping
     * @return TypedSyncService The sync service instance or null if not found
     */
    public static TypedSyncService getSyncServiceInstance(String targetObject) {
        if (String.isBlank(targetObject)) {
            return null;
        }

        for (String className : getSyncServiceClassCandidates(targetObject)) {
            try {
                Type serviceType = Type.forName(className);
                if (serviceType != null) {
                    Object instance = serviceType.newInstance();
                    if (instance instanceof TypedSyncService) {
                        return (TypedSyncService)instance;
                    }
                }
            } catch (Exception e) {
                Logger.debug('No sync service found for ' + targetObject + ' using ' + className + ': ' + e.getMessage());
            }
        }
        return null;
    }

    @TestVisible
    private static List<String> getSyncServiceClassCandidates(String targetObject) {
        List<String> candidates = new List<String>{ targetObject + 'SyncService' };
        String normalizedTargetObject = targetObject;
        if (normalizedTargetObject.endsWith('__c')) {
            normalizedTargetObject = normalizedTargetObject.removeEnd('__c');
        } else if (normalizedTargetObject.endsWith('__mdt')) {
            normalizedTargetObject = normalizedTargetObject.removeEnd('__mdt');
        }

        String normalizedCandidate = normalizedTargetObject + 'SyncService';
        if (!candidates.contains(normalizedCandidate)) {
            candidates.add(normalizedCandidate);
        }
        return candidates;
    }

    /**
     * @description Get pagination-specific headers to add to the request
     * Can be overridden to provide custom headers
     * @return Map of header names to values
     */
    protected virtual Map<String, String> getPaginationHeaders() {
        return new Map<String, String>();
    }
    
    /**
     * @description Construct the full endpoint URL from base components
     * @param baseUrl The base URL from endpoint
     * @param basePath The base API path
     * @param resourcePath The resource-specific path
     * @return The constructed URL
     */
    protected String constructFullUrl(String basePath, String resourcePath) {
        // Initialize to empty string to avoid prepending "null"
        String fullUrl = '';
        
        // Start with trimmed base URL
        if (String.isNotBlank(basePath)) {
            basePath = basePath.trim();
            // Ensure base path starts with / and doesn't end with /
            basePath = basePath.startsWith('/') ? basePath : '/' + basePath;
            basePath = basePath.endsWith('/') ? basePath.removeEnd('/') : basePath;
            fullUrl += basePath;
        }
        
        // Add resource path if present
        if (String.isNotBlank(resourcePath)) {
            resourcePath = resourcePath.trim();
            // Ensure resource path starts with / and doesn't end with /
            resourcePath = resourcePath.startsWith('/') ? resourcePath : '/' + resourcePath;
            resourcePath = resourcePath.endsWith('/') ? resourcePath.removeEnd('/') : resourcePath;
            fullUrl += resourcePath;
        }
        
        return fullUrl;
    }
    
    /**
     * @description Modify the endpoint URL for pagination
     * Can be overridden to add custom query parameters
     * @param baseUrl The base endpoint URL
     * @param state Current pagination state
     * @return Modified URL with pagination parameters
     */
    public virtual String modifyEndpointUrl(String baseUrl, PaginationState state) {
        // Validate input parameters
        if (String.isBlank(baseUrl)) {
            Logger.error('Base URL is null or empty');
            return '';
        }
        
        // Safely access endpoint and mapping properties
        String basePath = endpoint?.Base_Path__c;
        String resourcePath = mapping?.Resource_Path__c;
        
        // Construct full URL from components
        String fullUrl = constructFullUrl(basePath, resourcePath);
        return String.isNotBlank(fullUrl) ? fullUrl : baseUrl;
    }
    
    /**
     * @description Extract records from the response
     * Can be overridden to handle custom response formats
     * @param responseBody The response body as a string
     * @return List of records as objects
     */
    protected virtual List<Object> extractRecords(String responseBody) {
        // Validate input parameters
        if (String.isBlank(responseBody)) {
            Logger.warn('Response body is empty or null');
            return new List<Object>();
        }
        
        try {
            Object parsed = JSON.deserializeUntyped(responseBody);
            
            if (parsed instanceof List<Object>) {
                return (List<Object>)parsed;
            } else if (parsed instanceof Map<String, Object>) {
                Map<String, Object> responseMap = (Map<String, Object>)parsed;
                
                // Look for common array field names
                for (String key : new List<String>{'records', 'items', 'data', 'results'}) {
                    if (responseMap.containsKey(key) && responseMap.get(key) instanceof List<Object>) {
                        return (List<Object>)responseMap.get(key);
                    }
                }
                
                // If no standard array fields found, log warning
                Logger.warn('No standard record array found in response. Available fields: ' + 
                          String.join(new List<String>(responseMap.keySet()), ', '));
            } else {
                Logger.warn('Unexpected response format: ' + (parsed != null ? String.valueOf(parsed) : 'null'));
            }
        } catch (JSONException e) {
            Logger.error('Failed to parse response JSON: ' + e.getMessage());
        } catch (Exception e) {
            Logger.error('Error extracting records: ' + e.getMessage());
        }
        
        return new List<Object>();
    }
    
    /**
     * @description Check if more records are available
     * Can be overridden to handle custom pagination indicators
     * @param response The HTTP response
     * @param currentRecords The records from this response
     * @return Boolean indicating if more records exist
     */
    protected virtual Boolean hasMoreRecords(HttpResponse response, List<Object> currentRecords) {
        // Validate input parameters
        if (response == null || currentRecords == null) {
            return false;
        }
        
        // Default implementation checks if we got a full page of records
        Integer pageSize = currentRecords.size();
        Integer configuredPageSize = getPaginationPageSize();
        
        return pageSize > 0 && pageSize >= configuredPageSize;
    }
    
    /**
     * @description Get the page size for pagination
     * Can be overridden to provide custom page size logic
     * @return Integer indicating how many records per page
     */
    @TestVisible
    protected virtual Integer getPaginationPageSize() {
        // Prioritize mapping page size, then endpoint, then default
        Integer mappingPageSize = mapping?.Page_Size__c != null ?
            Integer.valueOf(mapping.Page_Size__c) : null;

        if (mappingPageSize != null && mappingPageSize > 0) {
            return mappingPageSize;
        }

        // Default to 100 if neither is set or valid
        return 100;
    }
    
    /**
     * @description Create next pagination state
     * Can be overridden to handle custom state management
     * @param response The HTTP response
     * @param currentState Current pagination state
     * @return Next pagination state
     */
    protected virtual PaginationState createNextState(HttpResponse response, PaginationState currentState) {
        // Validate response
        if (response == null) {
            Logger.warn('Cannot create next pagination state: HTTP response is null');
            return null;
        }
        
        // Get page size safely
        Integer pageSize = getPaginationPageSize();
        
        // Create initial state if none exists
        if (currentState == null) {
            return new PaginationState(0, pageSize);
        }
        
        // Safely calculate next offset
        Integer currentOffset = currentState.getOffset() != null ? currentState.getOffset() : 0;
        return new PaginationState(currentOffset + pageSize, pageSize);
    }
    
    /**
     * @description Handle any errors in the response
     * Can be overridden to provide custom error handling
     * @param response The HTTP response
     * @return String error message or null if no error
     */
    protected virtual String handleErrors(HttpResponse response) {
        // Validate input parameter
        if (response == null) {
            return 'No HTTP response available';
        }
        
        Integer statusCode = response.getStatusCode();
        
        // Check for HTTP error status codes
        if (statusCode >= 400) {
            String errorMessage = 'HTTP Error ' + statusCode + ': ' + response.getStatus();
            
            // Try to extract more detailed error information from response body
            try {
                String body = response.getBody();
                if (String.isNotBlank(body)) {
                    // Attempt to parse as JSON
                    Object parsed = JSON.deserializeUntyped(body);
                    if (parsed instanceof Map<String, Object>) {
                        Map<String, Object> errorMap = (Map<String, Object>)parsed;
                        
                        // Look for common error fields
                        for (String key : new List<String>{'error', 'message', 'errorMessage', 'description'}) {
                            if (errorMap.containsKey(key)) {
                                errorMessage += ' - ' + String.valueOf(errorMap.get(key));
                                break;
                            }
                        }
                    }
                }
            } catch (Exception e) {
                // If error parsing fails, just log the message
                Logger.debug('Could not parse error details: ' + e.getMessage());
            }
            
            return errorMessage;
        }
        
        return null;
    }

    /**
     * @description HTTP method to use for the callout. Override in GraphQL strategies to return 'POST'.
     * @return String HTTP method (default: 'GET')
     */
    public virtual String getHttpMethod() {
        return 'GET';
    }

    /**
     * @description Build the request body for the callout. Override in GraphQL strategies to return the query JSON.
     * @param state Current pagination state (used to inject cursor variable)
     * @return String Request body or null for GET requests
     */
    public virtual String buildRequestBody(PaginationState state) {
        return null;
    }

    // Add a new helper method for consistent logging
    protected void logResponseSummary(HttpResponse response, List<Object> records, Boolean hasMoreData) {
        if (response == null) {
            Logger.warn('Response is null, cannot log summary');
            return;
        }
        
        Integer statusCode = response.getStatusCode();
        Integer recordCount = records != null ? records.size() : 0;
        
        Logger.info('API Response Summary - Status: ' + statusCode +
                  ', Records: ' + recordCount +
                  ', Has More: ' + hasMoreData +
                  ', Endpoint: ' + endpoint?.DeveloperName +
                  ', Mapping: ' + mapping?.DeveloperName);

        String responseBody = response.getBody();
        Logger.debug('Response body summary: ' + (responseBody == null ? 'null' : 'len=' + responseBody.length()));
    }
}
