/**
 * @description Test class for CompanoOffsetPaginationStrategy
 * Tests Compano's path-based pagination format: /{startRecord}/{recordCount}/
 * e.g. /API/jsonfeed/products/1/100/ means start at record 1, fetch 100 records
 */
@IsTest
private class CompanoOffsetPaginationStrategyTest {

    // --- Mock HTTP Response Generator ---
    private class MockHttpResponseGenerator implements HttpCalloutMock {
        Integer statusCode;
        String body;

        MockHttpResponseGenerator(Integer code, String responseBody) {
            this.statusCode = code;
            this.body = responseBody != null ? responseBody : '{}';
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(this.statusCode);
            res.setStatus(this.statusCode == 200 ? 'OK' : 'Error');
            res.setBody(this.body);
            if (this.statusCode == 200) {
                res.setHeader('Content-Type', 'application/json');
            }
            return res;
        }
    }

    // --- processResponse tests ---

    @IsTest
    static void testProcessResponse_SuccessWithFullPage() {
        CompanoOffsetPaginationStrategy strategy = new CompanoOffsetPaginationStrategy();
        Integer pageSize = 2;
        PaginationState currentState = new PaginationState(1, pageSize);

        // Build response with 100 records to match default page size from getPaginationPageSize()
        List<Object> data = new List<Object>();
        for (Integer i = 1; i <= 100; i++) {
            data.add(new Map<String, Object>{'id' => i, 'name' => 'Product ' + i});
        }
        String responseBody = JSON.serialize(new Map<String, Object>{'Data' => data});
        HttpResponse mockResponse = new HttpResponse();
        mockResponse.setStatusCode(200);
        mockResponse.setBody(responseBody);
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(200, responseBody));

        Test.startTest();
        PaginationResult result = strategy.processResponse(mockResponse, currentState);
        Test.stopTest();

        System.assertEquals(true, result.isSuccess(), 'Result should be success.');
        System.assertEquals(100, result.getRecords().size(), 'Should return 100 records.');
        System.assertEquals(true, result.getHasMoreData(), 'Full page should indicate more data.');
        System.assertNotEquals(null, result.getNextState(), 'Next state should not be null when there is more data.');
    }

    @IsTest
    static void testProcessResponse_SuccessWithPartialPage() {
        CompanoOffsetPaginationStrategy strategy = new CompanoOffsetPaginationStrategy();
        // Default page size is 100; 1 record = partial page
        PaginationState currentState = new PaginationState(1, 100);

        String responseBody = '{"Data": [{"id": 1, "name": "Only Product"}]}';
        HttpResponse mockResponse = new HttpResponse();
        mockResponse.setStatusCode(200);
        mockResponse.setBody(responseBody);

        Test.startTest();
        PaginationResult result = strategy.processResponse(mockResponse, currentState);
        Test.stopTest();

        System.assertEquals(true, result.isSuccess(), 'Result should be success.');
        System.assertEquals(1, result.getRecords().size(), 'Should return 1 record.');
        System.assertEquals(false, result.getHasMoreData(), 'Partial page should not indicate more data.');
        System.assertEquals(null, result.getNextState(), 'Next state should be null when there is no more data.');
    }

    @IsTest
    static void testProcessResponse_ProductsRootIsSupported() {
        CompanoOffsetPaginationStrategy strategy = new CompanoOffsetPaginationStrategy();
        PaginationState currentState = new PaginationState(1, 100);

        String responseBody = '{"Products": [{"Code": {"Value": "10010"}}], "Count": 1}';
        HttpResponse mockResponse = new HttpResponse();
        mockResponse.setStatusCode(200);
        mockResponse.setBody(responseBody);

        Test.startTest();
        PaginationResult result = strategy.processResponse(mockResponse, currentState);
        Test.stopTest();

        System.assertEquals(true, result.isSuccess(), 'Products root should be handled successfully.');
        System.assertEquals(1, result.getRecords().size(), 'Should return the product record.');
        System.assertEquals(false, result.getHasMoreData(), 'Count=1 should not indicate more data.');
        Map<String, Object> firstRecord = (Map<String, Object>) result.getRecords()[0];
        System.assertEquals(true, firstRecord.containsKey('Code'), 'Expected product record payload.');
    }

    @IsTest
    static void testProcessResponse_UsesCountToAvoidExtraPage() {
        CompanoOffsetPaginationStrategy strategy = new CompanoOffsetPaginationStrategy();
        PaginationState currentState = new PaginationState(101, 100);

        List<Object> data = new List<Object>();
        for (Integer i = 101; i <= 200; i++) {
            data.add(new Map<String, Object>{'id' => i});
        }
        String responseBody = JSON.serialize(new Map<String, Object>{
            'Products' => data,
            'Count' => 200
        });
        HttpResponse mockResponse = new HttpResponse();
        mockResponse.setStatusCode(200);
        mockResponse.setBody(responseBody);

        Test.startTest();
        PaginationResult result = strategy.processResponse(mockResponse, currentState);
        Test.stopTest();

        System.assertEquals(true, result.isSuccess(), 'Response should be processed successfully.');
        System.assertEquals(100, result.getRecords().size(), 'Should return a full page of records.');
        System.assertEquals(false, result.getHasMoreData(), 'Exact total count should stop pagination.');
        System.assertEquals(null, result.getNextState(), 'No next page expected when seen count equals total count.');
    }

    @IsTest
    static void testProcessResponse_EmptyDataArray() {
        CompanoOffsetPaginationStrategy strategy = new CompanoOffsetPaginationStrategy();
        PaginationState currentState = new PaginationState(1, 100);

        String responseBody = '{"Data": []}';
        HttpResponse mockResponse = new HttpResponse();
        mockResponse.setStatusCode(200);
        mockResponse.setBody(responseBody);

        Test.startTest();
        PaginationResult result = strategy.processResponse(mockResponse, currentState);
        Test.stopTest();

        System.assertEquals(true, result.isSuccess(), 'Empty result should still be success.');
        System.assertEquals(0, result.getRecords().size(), 'Should return 0 records on empty Data array.');
        System.assertEquals(false, result.getHasMoreData(), 'Empty page should not indicate more data.');
        System.assertEquals(null, result.getNextState(), 'Next state should be null for empty response.');
    }

    @IsTest
    static void testProcessResponse_NullDataKey() {
        CompanoOffsetPaginationStrategy strategy = new CompanoOffsetPaginationStrategy();
        PaginationState currentState = new PaginationState(1, 100);

        String responseBody = '{"Count": 0}';
        HttpResponse mockResponse = new HttpResponse();
        mockResponse.setStatusCode(200);
        mockResponse.setBody(responseBody);

        Test.startTest();
        PaginationResult result = strategy.processResponse(mockResponse, currentState);
        Test.stopTest();

        System.assertEquals(true, result.isSuccess(), 'Response without Data key should succeed with 0 records.');
        System.assertEquals(0, result.getRecords().size(), 'Should return 0 records when Data key is absent.');
    }

    @IsTest
    static void testProcessResponse_HttpError() {
        CompanoOffsetPaginationStrategy strategy = new CompanoOffsetPaginationStrategy();
        PaginationState currentState = new PaginationState(1, 100);

        HttpResponse mockResponse = new HttpResponse();
        mockResponse.setStatusCode(500);
        mockResponse.setBody('Internal Server Error');

        Test.startTest();
        PaginationResult result = strategy.processResponse(mockResponse, currentState);
        Test.stopTest();

        System.assertEquals(false, result.isSuccess(), 'HTTP error should produce failure result.');
        System.assert(result.getErrorMessage().contains('HTTP Error'), 'Error message should mention HTTP error.');
    }

    @IsTest
    static void testProcessResponse_HttpNotFound() {
        CompanoOffsetPaginationStrategy strategy = new CompanoOffsetPaginationStrategy();
        PaginationState currentState = new PaginationState(1, 100);

        HttpResponse mockResponse = new HttpResponse();
        mockResponse.setStatusCode(404);
        mockResponse.setBody('Not Found');

        Test.startTest();
        PaginationResult result = strategy.processResponse(mockResponse, currentState);
        Test.stopTest();

        System.assertEquals(false, result.isSuccess(), 'HTTP 404 should produce failure result.');
    }

    @IsTest
    static void testProcessResponse_InvalidJson() {
        CompanoOffsetPaginationStrategy strategy = new CompanoOffsetPaginationStrategy();
        PaginationState currentState = new PaginationState(1, 100);

        HttpResponse mockResponse = new HttpResponse();
        mockResponse.setStatusCode(200);
        mockResponse.setBody('Invalid JSON {{{{');

        Test.startTest();
        PaginationResult result = strategy.processResponse(mockResponse, currentState);
        Test.stopTest();

        System.assertEquals(false, result.isSuccess(), 'Invalid JSON should produce failure result.');
        System.assert(result.getErrorMessage().contains('Failed to process response'), 'Error message should indicate parse failure.');
    }

    @IsTest
    static void testProcessResponse_DataAsSingleObject() {
        CompanoOffsetPaginationStrategy strategy = new CompanoOffsetPaginationStrategy();
        PaginationState currentState = new PaginationState(1, 100);

        // Data is a single object (not an array)
        String responseBody = '{"Data": {"id": 1, "name": "Single Product"}}';
        HttpResponse mockResponse = new HttpResponse();
        mockResponse.setStatusCode(200);
        mockResponse.setBody(responseBody);

        Test.startTest();
        PaginationResult result = strategy.processResponse(mockResponse, currentState);
        Test.stopTest();

        System.assertEquals(true, result.isSuccess(), 'Single object Data should succeed.');
        System.assertEquals(1, result.getRecords().size(), 'Single object Data should yield 1 record.');
    }

    @IsTest
    static void testProcessResponse_NullState() {
        CompanoOffsetPaginationStrategy strategy = new CompanoOffsetPaginationStrategy();

        String responseBody = '{"Data": [{"id": 1}]}';
        HttpResponse mockResponse = new HttpResponse();
        mockResponse.setStatusCode(200);
        mockResponse.setBody(responseBody);

        Test.startTest();
        PaginationResult result = strategy.processResponse(mockResponse, null);
        Test.stopTest();

        // Should not throw, offset defaults to 1
        System.assertEquals(true, result.isSuccess(), 'Null state should not cause failure.');
    }

    // --- modifyEndpointUrl tests ---

    @IsTest
    static void testModifyEndpointUrl_FirstPage() {
        CompanoOffsetPaginationStrategy strategy = new CompanoOffsetPaginationStrategy();
        String baseUrl = '/API/jsonfeed/products';

        Test.startTest();
        String result = strategy.modifyEndpointUrl(baseUrl, null);
        Test.stopTest();

        // Null state => offset defaults to 1, page size defaults to 100
        System.assert(result.startsWith('/API/jsonfeed/products/1/'), 'URL should start with base + /1/.');
        System.assert(result.endsWith('/'), 'URL should end with trailing slash.');
        System.debug('Modified URL (null state): ' + result);
    }

    @IsTest
    static void testModifyEndpointUrl_WithState() {
        CompanoOffsetPaginationStrategy strategy = new CompanoOffsetPaginationStrategy();
        String baseUrl = '/API/jsonfeed/products';
        PaginationState state = new PaginationState(101, 100);

        Test.startTest();
        String result = strategy.modifyEndpointUrl(baseUrl, state);
        Test.stopTest();

        System.assert(result.contains('/101/100/'), 'URL should contain /101/100/ for offset 101 and page size 100.');
        System.assertEquals('/API/jsonfeed/products/101/100/', result, 'URL should match expected Compano pagination format.');
    }

    @IsTest
    static void testModifyEndpointUrl_TrailingSlashStripped() {
        CompanoOffsetPaginationStrategy strategy = new CompanoOffsetPaginationStrategy();
        String baseUrlWithSlash = '/API/jsonfeed/products/';
        PaginationState state = new PaginationState(1, 100); // Use default page size

        Test.startTest();
        String result = strategy.modifyEndpointUrl(baseUrlWithSlash, state);
        Test.stopTest();

        // Trailing slash should be stripped before appending pagination path
        System.assertEquals('/API/jsonfeed/products/1/100/', result, 'Trailing slash on base URL should be handled correctly.');
    }

    @IsTest
    static void testModifyEndpointUrl_CustomPageSize() {
        CompanoOffsetPaginationStrategy strategy = new CompanoOffsetPaginationStrategy();

        // Initialize with a mapping that has a custom page size
        Integration_Endpoint__mdt mockEndpoint = new Integration_Endpoint__mdt(
            DeveloperName = 'CompanoTest',
            Active__c = true,
            Named_Credential__c = 'Compano_Named_Credentials'
        );
        Integration_Mapping__mdt mockMapping = new Integration_Mapping__mdt(
            DeveloperName = 'CompanoProducts',
            Active__c = true,
            Page_Size__c = 25,
            Endpoint__r = mockEndpoint
        );
        strategy.initialize(mockEndpoint, mockMapping, null);

        String baseUrl = '/API/jsonfeed/products';
        PaginationState state = new PaginationState(26, 25);

        Test.startTest();
        String result = strategy.modifyEndpointUrl(baseUrl, state);
        Test.stopTest();

        System.assertEquals('/API/jsonfeed/products/26/25/', result, 'URL should use custom page size from mapping.');
    }

    @IsTest
    static void testModifyEndpointUrl_Pagination_Sequence() {
        // Simulate a full pagination sequence: page 1, page 2, page 3
        CompanoOffsetPaginationStrategy strategy = new CompanoOffsetPaginationStrategy();
        String baseUrl = '/API/jsonfeed/products';
        Integer pageSize = 100;

        Test.startTest();
        // Page 1: offset = 1
        String url1 = strategy.modifyEndpointUrl(baseUrl, new PaginationState(1, pageSize));
        // Page 2: offset = 101
        String url2 = strategy.modifyEndpointUrl(baseUrl, new PaginationState(1 + pageSize, pageSize));
        // Page 3: offset = 201
        String url3 = strategy.modifyEndpointUrl(baseUrl, new PaginationState(1 + pageSize * 2, pageSize));
        Test.stopTest();

        System.assertEquals('/API/jsonfeed/products/1/100/', url1, 'Page 1 URL incorrect.');
        System.assertEquals('/API/jsonfeed/products/101/100/', url2, 'Page 2 URL incorrect.');
        System.assertEquals('/API/jsonfeed/products/201/100/', url3, 'Page 3 URL incorrect.');
    }
}
