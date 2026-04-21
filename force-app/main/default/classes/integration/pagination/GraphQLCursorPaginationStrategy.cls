/**
 * @description Pagination strategy for GraphQL endpoints using cursor-based pagination.
 * Sends POST requests with a JSON body containing the query from Integration_Mapping__mdt.GraphQL_Query__c
 * and variables {first: pageSize, after: cursor}. Expects a response with
 * data.<rootField>.edges[] and data.<rootField>.pageInfo.{hasNextPage, endCursor}.
 * @Author: R. Groot Date: 2026-04-21
 */
public class GraphQLCursorPaginationStrategy extends PaginationStrategy {

    private static final String CURSOR_KEY = 'cursor';

    /**
     * @description Returns POST as GraphQL always uses POST requests.
     */
    public override String getHttpMethod() {
        return 'POST';
    }

    /**
     * @description Returns Base_Path__c as the GraphQL endpoint URL (no resource path appended).
     */
    public override String modifyEndpointUrl(String baseUrl, PaginationState state) {
        return String.isNotBlank(endpoint?.Base_Path__c) ? endpoint.Base_Path__c : baseUrl;
    }

    /**
     * @description Builds the GraphQL request body JSON with query and cursor/pageSize variables.
     */
    public override String buildRequestBody(PaginationState state) {
        String query = mapping?.GraphQL_Query__c;
        if (String.isBlank(query)) {
            throw new PaginationStrategyFactory.PaginationException(
                'GraphQL_Query__c is required for GraphQL mappings: ' + mapping?.DeveloperName
            );
        }

        Integer pageSize = getPaginationPageSize();
        String cursor = (state != null && state.hasCustomData(CURSOR_KEY))
            ? (String) state.getCustomData(CURSOR_KEY)
            : null;

        Map<String, Object> variables = new Map<String, Object>{ 'first' => pageSize };
        if (String.isNotBlank(cursor)) {
            variables.put('after', cursor);
        }

        Map<String, Object> body = new Map<String, Object>{
            'query'     => query,
            'variables' => variables
        };
        return JSON.serialize(body);
    }

    /**
     * @description Parses the GraphQL response. Expects data.<rootField>.edges[] and
     * data.<rootField>.pageInfo.{hasNextPage, endCursor}.
     * The root field name is derived from mapping.Source_Object__c (lowercased).
     */
    public override PaginationResult processResponse(HttpResponse response, PaginationState state) {
        String errorMsg = handleErrors(response);
        if (errorMsg != null) {
            return PaginationResult.createError(errorMsg);
        }

        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());

            // Check for GraphQL-level errors
            if (parsed.containsKey('errors')) {
                List<Object> errors = (List<Object>) parsed.get('errors');
                String firstError = errors.isEmpty() ? 'Unknown GraphQL error'
                    : String.valueOf(((Map<String, Object>) errors[0]).get('message'));
                return PaginationResult.createError('GraphQL error: ' + firstError);
            }

            Map<String, Object> data = (Map<String, Object>) parsed.get('data');
            if (data == null) {
                return PaginationResult.createError('GraphQL response missing "data" field');
            }

            // Find the first key in data that contains edges + pageInfo
            List<Object> edges = new List<Object>();
            Boolean hasNextPage = false;
            String endCursor = null;

            for (String rootField : data.keySet()) {
                Object fieldValue = data.get(rootField);
                if (!(fieldValue instanceof Map<String, Object>)) continue;

                Map<String, Object> fieldMap = (Map<String, Object>) fieldValue;
                if (!fieldMap.containsKey('edges')) continue;

                Object edgesObj = fieldMap.get('edges');
                if (!(edgesObj instanceof List<Object>)) continue;
                edges = (List<Object>) edgesObj;

                if (fieldMap.containsKey('pageInfo')) {
                    Object pageInfoObj = fieldMap.get('pageInfo');
                    if (pageInfoObj instanceof Map<String, Object>) {
                        Map<String, Object> pageInfo = (Map<String, Object>) pageInfoObj;
                        hasNextPage = pageInfo.containsKey('hasNextPage')
                            ? (Boolean) pageInfo.get('hasNextPage') : false;
                        endCursor = pageInfo.containsKey('endCursor')
                            ? (String) pageInfo.get('endCursor') : null;
                    }
                }
                break;
            }

            // Extract node objects from edges
            List<Object> records = new List<Object>();
            for (Object edge : edges) {
                if (!(edge instanceof Map<String, Object>)) {
                    Logger.warn('Unexpected edge format, skipping');
                    continue;
                }
                Map<String, Object> edgeMap = (Map<String, Object>) edge;
                if (edgeMap.containsKey('node')) {
                    records.add(edgeMap.get('node'));
                }
            }

            PaginationState nextState = createNextState(response, state);
            if (hasNextPage && nextState != null) {
                if (String.isBlank(endCursor)) {
                    Logger.warn('GraphQL hasNextPage=true but endCursor is blank for mapping: ' + mapping?.DeveloperName + '. Stopping pagination to prevent loop.');
                    hasNextPage = false;
                } else {
                    nextState.setCustomData(CURSOR_KEY, endCursor);
                }
            }

            logResponseSummary(response, records, hasNextPage);
            return PaginationResult.createSuccess(records, nextState, hasNextPage);

        } catch (Exception e) {
            Logger.error('GraphQL response parsing failed: ' + e.getMessage());
            return PaginationResult.createError('Failed to parse GraphQL response: ' + e.getMessage());
        }
    }

    protected override PaginationState createNextState(HttpResponse response, PaginationState currentState) {
        Integer pageSize = getPaginationPageSize();
        if (currentState == null) {
            return new PaginationState(0, pageSize);
        }
        return new PaginationState(currentState.getOffset(), pageSize, currentState.getAllCustomData());
    }
}
