/**
 * @description Custom pagination strategy for Compano JSON Feeds API
 * Implements Compano's path-based pagination format: /startRecord/recordCount/
 * Reference: Compano Manual JSON Feeds documentation, Section 5: Pagination
 * Example: /1/100/ means start at record 1, show 100 records per page
 */
public class CompanoOffsetPaginationStrategy extends PaginationStrategy {
    @TestVisible
    private static final List<String> ROOT_COLLECTION_KEYS = new List<String>{
        'Data',
        'data',
        'Products',
        'products',
        'Items',
        'items',
        'Records',
        'records',
        'Results',
        'results',
        'Attachments',
        'attachments'
    };

    @TestVisible
    private static final Set<String> METADATA_KEYS = new Set<String>{
        'Count',
        'count',
        'Total',
        'total',
        'HasMore',
        'hasMore'
    };

    /**
     * @description Default constructor required by the framework
     */
    public CompanoOffsetPaginationStrategy() {
        super();
    }
    
    /**
     * @description Process API response and handle pagination
     * @param response The HTTP response from the API call
     * @param state Current pagination state
     * @return PaginationResult containing processed records and next state
     */
    public override PaginationResult processResponse(HttpResponse response, PaginationState state) {
        if (response.getStatusCode() >= 400) {
            return PaginationResult.createError('HTTP Error: ' + response.getStatusCode());
        }
        
        try {
            Object parsedResponse = JSON.deserializeUntyped(response.getBody());
            List<Object> records = new List<Object>();
            Integer totalCount;

            if (parsedResponse instanceof Map<String, Object>) {
                Map<String, Object> responseMap = (Map<String, Object>) parsedResponse;
                records = extractCompanoRecords(responseMap);
                totalCount = extractTotalCount(responseMap);
            } else if (parsedResponse instanceof List<Object>) {
                records = (List<Object>) parsedResponse;
            }
            
            // If empty array or no records, we've reached the end
            if (records == null || records.isEmpty()) {
                return PaginationResult.createSuccess(new List<Object>(), null, false);
            }
            
            // Calculate next state
            Integer pageSize = getPaginationPageSize();
            Integer currentOffset = state != null ? state.getOffset() : 1; // Compano uses 1-based indexing
            
            Integer seenRecordCount = Math.max(0, currentOffset - 1) + records.size();
            Boolean hasMorePages = totalCount != null ?
                seenRecordCount < totalCount :
                records.size() >= pageSize;
            PaginationState nextState = hasMorePages ? 
                new PaginationState(currentOffset + pageSize, pageSize) : 
                null;
                
            return PaginationResult.createSuccess(records, nextState, hasMorePages);
            
        } catch (Exception e) {
            return PaginationResult.createError('Failed to process response: ' + e.getMessage());
        }
    }

    @TestVisible
    private static List<Object> extractCompanoRecords(Map<String, Object> responseMap) {
        if (responseMap == null) {
            return new List<Object>();
        }

        for (String key : ROOT_COLLECTION_KEYS) {
            List<Object> records = asRecordList(responseMap.get(key));
            if (!records.isEmpty()) {
                return records;
            }
        }

        for (String key : responseMap.keySet()) {
            if (METADATA_KEYS.contains(key)) {
                continue;
            }

            List<Object> records = asRecordList(responseMap.get(key));
            if (!records.isEmpty()) {
                return records;
            }
        }

        return new List<Object>();
    }

    @TestVisible
    private static Integer extractTotalCount(Map<String, Object> responseMap) {
        if (responseMap == null) {
            return null;
        }

        for (String key : new List<String>{ 'Count', 'count', 'Total', 'total' }) {
            Object countValue = responseMap.get(key);
            if (countValue instanceof Integer) {
                return (Integer) countValue;
            }
            if (countValue instanceof Long) {
                return Integer.valueOf(String.valueOf(countValue));
            }
            if (countValue instanceof Decimal) {
                return ((Decimal) countValue).intValue();
            }
            if (countValue instanceof Double) {
                return Integer.valueOf(Math.round((Double) countValue));
            }
            if (countValue instanceof String && String.isNotBlank((String) countValue)) {
                try {
                    return Integer.valueOf((String) countValue);
                } catch (Exception ignored) {
                }
            }
        }

        return null;
    }

    private static List<Object> asRecordList(Object value) {
        if (value instanceof List<Object>) {
            return (List<Object>) value;
        }
        if (value instanceof Map<String, Object>) {
            return new List<Object>{ value };
        }
        return new List<Object>();
    }
    
    /**
     * @description Modify the endpoint URL for Compano pagination
     * Compano format: {baseUrl}/startRecord/recordCount/
     * Example: /api/jsonfeed/products/1/100/ (start at record 1, fetch 100 records)
     * @param baseUrl The base endpoint URL
     * @param state Current pagination state
     * @return Modified URL with pagination path parameters
     */
    @TestVisible
    public override String modifyEndpointUrl(String baseUrl, PaginationState state) {
        // Get pagination parameters
        Integer pageSize = getPaginationPageSize();
        Integer currentOffset = (state != null ? state.getOffset() : 1); // Compano uses 1-based indexing
        
        // Construct Compano pagination format: /startRecord/recordCount/
        // Ensure baseUrl doesn't have trailing slash
        String url = baseUrl;
        if (url.endsWith('/')) {
            url = url.substring(0, url.length() - 1);
        }
        
        return url + '/' + currentOffset + '/' + pageSize + '/';
    }
}
