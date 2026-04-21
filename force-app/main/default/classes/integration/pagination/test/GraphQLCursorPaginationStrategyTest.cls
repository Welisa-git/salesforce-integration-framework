/**
 * @description Test class for GraphQLCursorPaginationStrategy
 * @Author: R. Groot Date: 2026-04-21
 */
@IsTest
private class GraphQLCursorPaginationStrategyTest {

    private static final String SAMPLE_QUERY = 'query GetProducts($first: Int, $after: String) { products(first: $first, after: $after) { edges { node { id name } } pageInfo { hasNextPage endCursor } } }';

    private static GraphQLCursorPaginationStrategy buildStrategy(String query, Integer pageSize) {
        Integration_Endpoint__mdt mockEndpoint = new Integration_Endpoint__mdt(
            DeveloperName = 'TestGQLEndpoint',
            Active__c = true,
            Named_Credential__c = 'Test_NC',
            Base_Path__c = '/graphql'
        );
        Integration_Mapping__mdt mockMapping = new Integration_Mapping__mdt(
            DeveloperName = 'TestGQLMapping',
            Active__c = true,
            Target_Object__c = 'Product2',
            Source_Object__c = 'products',
            GraphQL_Query__c = query,
            Page_Size__c = pageSize != null ? pageSize : 50,
            Endpoint__r = mockEndpoint
        );
        GraphQLCursorPaginationStrategy strategy = new GraphQLCursorPaginationStrategy();
        strategy.initialize(mockEndpoint, mockMapping, null);
        return strategy;
    }

    private static HttpResponse buildResponse(Integer statusCode, String body) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(statusCode);
        res.setStatus(statusCode == 200 ? 'OK' : 'Error');
        res.setBody(body);
        return res;
    }

    // --- getHttpMethod ---

    @IsTest
    static void testGetHttpMethod_ReturnsPost() {
        GraphQLCursorPaginationStrategy strategy = buildStrategy(SAMPLE_QUERY, 50);
        System.assertEquals('POST', strategy.getHttpMethod(), 'GraphQL strategy must use POST');
    }

    // --- modifyEndpointUrl ---

    @IsTest
    static void testModifyEndpointUrl_ReturnsBasePath() {
        GraphQLCursorPaginationStrategy strategy = buildStrategy(SAMPLE_QUERY, 50);
        String result = strategy.modifyEndpointUrl('/ignored/resource', null);
        System.assertEquals('/graphql', result, 'modifyEndpointUrl should return Base_Path__c');
    }

    // --- buildRequestBody ---

    @IsTest
    static void testBuildRequestBody_FirstPage_NoCursor() {
        GraphQLCursorPaginationStrategy strategy = buildStrategy(SAMPLE_QUERY, 50);
        PaginationState state = new PaginationState(0, 50);

        Test.startTest();
        String body = strategy.buildRequestBody(state);
        Test.stopTest();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
        System.assertEquals(SAMPLE_QUERY, (String) parsed.get('query'), 'Query should match mapping query');

        Map<String, Object> variables = (Map<String, Object>) parsed.get('variables');
        System.assertEquals(50, (Integer) variables.get('first'), 'first variable should equal page size');
        System.assertEquals(false, variables.containsKey('after'), 'after variable should not be present on first page');
    }

    @IsTest
    static void testBuildRequestBody_WithCursor() {
        GraphQLCursorPaginationStrategy strategy = buildStrategy(SAMPLE_QUERY, 50);
        PaginationState state = new PaginationState(0, 50);
        state.setCustomData('cursor', 'abc123cursor');

        Test.startTest();
        String body = strategy.buildRequestBody(state);
        Test.stopTest();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
        Map<String, Object> variables = (Map<String, Object>) parsed.get('variables');
        System.assertEquals('abc123cursor', (String) variables.get('after'), 'after variable should contain the cursor');
    }

    @IsTest
    static void testBuildRequestBody_NullState_NoCursor() {
        GraphQLCursorPaginationStrategy strategy = buildStrategy(SAMPLE_QUERY, 50);

        Test.startTest();
        String body = strategy.buildRequestBody(null);
        Test.stopTest();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
        Map<String, Object> variables = (Map<String, Object>) parsed.get('variables');
        System.assertEquals(false, variables.containsKey('after'), 'after should not be set when state is null');
    }

    @IsTest
    static void testBuildRequestBody_MissingQuery_ThrowsException() {
        GraphQLCursorPaginationStrategy strategy = buildStrategy(null, 50);
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            strategy.buildRequestBody(null);
        } catch (PaginationStrategyFactory.PaginationException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Should throw PaginationException when GraphQL_Query__c is blank');
    }

    // --- processResponse ---

    @IsTest
    static void testProcessResponse_SuccessWithMorePages() {
        GraphQLCursorPaginationStrategy strategy = buildStrategy(SAMPLE_QUERY, 2);

        String responseBody = JSON.serialize(new Map<String, Object>{
            'data' => new Map<String, Object>{
                'products' => new Map<String, Object>{
                    'edges' => new List<Object>{
                        new Map<String, Object>{'node' => new Map<String, Object>{'id' => '1', 'name' => 'Product A'}},
                        new Map<String, Object>{'node' => new Map<String, Object>{'id' => '2', 'name' => 'Product B'}}
                    },
                    'pageInfo' => new Map<String, Object>{
                        'hasNextPage' => true,
                        'endCursor' => 'cursor_page2'
                    }
                }
            }
        });

        Test.startTest();
        PaginationResult result = strategy.processResponse(buildResponse(200, responseBody), new PaginationState(0, 2));
        Test.stopTest();

        System.assertEquals(true, result.isSuccess(), 'Should succeed');
        System.assertEquals(2, result.getRecords().size(), 'Should return 2 node records');
        System.assertEquals(true, result.getHasMoreData(), 'Should indicate more pages');
        System.assertEquals('cursor_page2', (String) result.getNextState().getCustomData('cursor'), 'Next state should carry cursor');
    }

    @IsTest
    static void testProcessResponse_LastPage_NoMoreData() {
        GraphQLCursorPaginationStrategy strategy = buildStrategy(SAMPLE_QUERY, 50);

        String responseBody = JSON.serialize(new Map<String, Object>{
            'data' => new Map<String, Object>{
                'products' => new Map<String, Object>{
                    'edges' => new List<Object>{
                        new Map<String, Object>{'node' => new Map<String, Object>{'id' => '99'}}
                    },
                    'pageInfo' => new Map<String, Object>{
                        'hasNextPage' => false,
                        'endCursor' => null
                    }
                }
            }
        });

        Test.startTest();
        PaginationResult result = strategy.processResponse(buildResponse(200, responseBody), new PaginationState(0, 50));
        Test.stopTest();

        System.assertEquals(true, result.isSuccess(), 'Should succeed');
        System.assertEquals(1, result.getRecords().size(), 'Should return 1 record');
        System.assertEquals(false, result.getHasMoreData(), 'No more pages');
    }

    @IsTest
    static void testProcessResponse_EmptyEdges() {
        GraphQLCursorPaginationStrategy strategy = buildStrategy(SAMPLE_QUERY, 50);

        String responseBody = JSON.serialize(new Map<String, Object>{
            'data' => new Map<String, Object>{
                'products' => new Map<String, Object>{
                    'edges' => new List<Object>(),
                    'pageInfo' => new Map<String, Object>{'hasNextPage' => false, 'endCursor' => null}
                }
            }
        });

        Test.startTest();
        PaginationResult result = strategy.processResponse(buildResponse(200, responseBody), null);
        Test.stopTest();

        System.assertEquals(true, result.isSuccess(), 'Empty edges should still succeed');
        System.assertEquals(0, result.getRecords().size(), 'Should return 0 records');
        System.assertEquals(false, result.getHasMoreData(), 'No records = no more pages');
    }

    @IsTest
    static void testProcessResponse_GraphQLErrors() {
        GraphQLCursorPaginationStrategy strategy = buildStrategy(SAMPLE_QUERY, 50);

        String responseBody = JSON.serialize(new Map<String, Object>{
            'errors' => new List<Object>{
                new Map<String, Object>{'message' => 'Field not found'}
            }
        });

        Test.startTest();
        PaginationResult result = strategy.processResponse(buildResponse(200, responseBody), null);
        Test.stopTest();

        System.assertEquals(false, result.isSuccess(), 'GraphQL errors should produce failure result');
        System.assert(result.getErrorMessage().contains('Field not found'), 'Error message should contain GraphQL error text');
    }

    @IsTest
    static void testProcessResponse_HttpError() {
        GraphQLCursorPaginationStrategy strategy = buildStrategy(SAMPLE_QUERY, 50);

        Test.startTest();
        PaginationResult result = strategy.processResponse(buildResponse(500, 'Server Error'), null);
        Test.stopTest();

        System.assertEquals(false, result.isSuccess(), 'HTTP 500 should produce failure result');
    }

    @IsTest
    static void testProcessResponse_MissingDataField() {
        GraphQLCursorPaginationStrategy strategy = buildStrategy(SAMPLE_QUERY, 50);

        Test.startTest();
        PaginationResult result = strategy.processResponse(buildResponse(200, '{"something":"else"}'), null);
        Test.stopTest();

        System.assertEquals(false, result.isSuccess(), 'Missing data field should produce failure result');
        System.assert(result.getErrorMessage().contains('"data"'), 'Error should mention missing data field');
    }

    @IsTest
    static void testProcessResponse_InvalidJson() {
        GraphQLCursorPaginationStrategy strategy = buildStrategy(SAMPLE_QUERY, 50);

        Test.startTest();
        PaginationResult result = strategy.processResponse(buildResponse(200, '{{invalid json'), null);
        Test.stopTest();

        System.assertEquals(false, result.isSuccess(), 'Invalid JSON should produce failure result');
    }
}
