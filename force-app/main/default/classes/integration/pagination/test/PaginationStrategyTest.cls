@IsTest
private class PaginationStrategyTest {

    private static final String TEST_ENDPOINT_NAME = 'TestPS_Endpoint';
    private static final String TEST_MAPPING_NAME = 'TestPS_Mapping';

    // Concrete subclass for testing abstract PaginationStrategy
    private class ConcreteTestStrategy extends PaginationStrategy {
        public override PaginationResult processResponse(HttpResponse response, PaginationState state) {
            if (response != null && response.getStatusCode() >= 400) {
                return PaginationResult.createError('HTTP Error ' + response.getStatusCode());
            }
            List<Object> mockRecords = this.extractRecords(response != null ? response.getBody() : null);
            Boolean hasMore = this.hasMoreRecords(response, mockRecords);
            PaginationState nextState = this.createNextState(response, state);
            return PaginationResult.createSuccess(mockRecords, nextState, hasMore);
        }

        // Expose protected methods for testing
        public String callConstructFullUrl(String basePath, String resourcePath) {
            return constructFullUrl(basePath, resourcePath);
        }
        public List<Object> callExtractRecords(String responseBody) {
            return extractRecords(responseBody);
        }
        public Boolean callHasMoreRecords(HttpResponse response, List<Object> currentRecords) {
            return hasMoreRecords(response, currentRecords);
        }
        public Integer callGetPaginationPageSize() {
            return getPaginationPageSize();
        }
        public PaginationState callCreateNextState(HttpResponse response, PaginationState currentState) {
            return createNextState(response, currentState);
        }
        public String callHandleErrors(HttpResponse response) {
            return handleErrors(response);
        }
        public void callLogResponseSummary(HttpResponse response, List<Object> records, Boolean hasMoreData) {
            logResponseSummary(response, records, hasMoreData);
        }
        public Map<String, String> callGetPaginationHeaders() {
            return getPaginationHeaders();
        }
    }

    // Helper method to setup mocks consistently for tests
    private static Integration_Mapping__mdt setupMocksForTest(Integer mappingPageSize, Integer syncOrder) {
        IntegrationMappingCache.clearCache();
        IntegrationMappingCache.clearMockMappings();

        Integration_Endpoint__mdt mockEndpoint = new Integration_Endpoint__mdt(
            DeveloperName = TEST_ENDPOINT_NAME,
            Active__c = true,
            Base_Path__c = ' /api/v1/ ',
            Named_Credential__c = 'Test_Named_Cred',
            Pagination_Type__c = 'Offset'
        );

        Integration_Mapping__mdt mockMapping = new Integration_Mapping__mdt(
            DeveloperName = TEST_MAPPING_NAME,
            Active__c = true,
            Operation_Type__c = 'Pull',
            Target_Object__c = 'Account',
            Resource_Path__c = ' /accounts/ ',
            Endpoint__r = mockEndpoint,
            Endpoint__c = mockEndpoint.Id,
            Page_Size__c = mappingPageSize,
            Sync_Order__c = syncOrder
        );

        IntegrationMappingCache.setMockMapping(TEST_MAPPING_NAME, mockMapping);
        return mockMapping;
    }

    @IsTest
    static void testInitialize_Success() {
        Integration_Mapping__mdt mapping = setupMocksForTest(100, 1);
        Integration_Endpoint__mdt endpoint = mapping.Endpoint__r;
        ConcreteTestStrategy strategy = new ConcreteTestStrategy();
        DateTime lastRun = DateTime.now().addDays(-1);

        Test.startTest();
        Boolean initSuccess = true;
        try {
            strategy.initialize(endpoint, mapping, lastRun);
        } catch (Exception e) {
            initSuccess = false;
        }
        Test.stopTest();

        System.assert(initSuccess, 'Initialization should succeed with valid inputs.');
    }

    @IsTest
    static void testInitialize_NullChecks() {
        Integration_Mapping__mdt mapping = setupMocksForTest(100, 1);
        Integration_Endpoint__mdt endpoint = mapping.Endpoint__r;
        ConcreteTestStrategy strategy = new ConcreteTestStrategy();
        Boolean endpointNullExceptionThrown = false;
        Boolean mappingNullExceptionThrown = false;

        Test.startTest();
        try {
            strategy.initialize(null, mapping, null);
        } catch (System.IllegalArgumentException e) {
            endpointNullExceptionThrown = e.getMessage().containsIgnoreCase('Endpoint configuration cannot be null');
        }
        try {
            strategy.initialize(endpoint, null, null);
        } catch (System.IllegalArgumentException e) {
            mappingNullExceptionThrown = e.getMessage().containsIgnoreCase('Mapping configuration cannot be null');
        }
        Test.stopTest();

        System.assert(endpointNullExceptionThrown, 'Expected IllegalArgumentException for null endpoint was not thrown or had wrong message.');
        System.assert(mappingNullExceptionThrown, 'Expected IllegalArgumentException for null mapping was not thrown or had wrong message.');
    }

    @IsTest
    static void testProcessSObjects_PassThrough() {
        ConcreteTestStrategy strategy = new ConcreteTestStrategy();
        List<SObject> inputList = new List<Account>{ new Account(Name='Test') };
        List<SObject> nullInput = null;

        Test.startTest();
        List<SObject> result1 = strategy.processSObjects(inputList);
        List<SObject> result2 = strategy.processSObjects(nullInput);
        Test.stopTest();

        System.assertEquals(inputList, result1, 'Should return the same list instance.');
        System.assertNotEquals(null, result2, 'Should return an empty list, not null, for null input.');
        System.assertEquals(0, result2.size(), 'Should return an empty list for null input.');
    }

    @IsTest
    static void testGetSyncServiceInstance() {
        Test.startTest();
        TypedSyncService result1 = PaginationStrategy.getSyncServiceInstance('NonExistentObject');
        TypedSyncService result2 = PaginationStrategy.getSyncServiceInstance('');
        TypedSyncService result3 = PaginationStrategy.getSyncServiceInstance('Account');
        Test.stopTest();

        System.assertEquals(null, result1, 'Should return null for non-existent service.');
        System.assertEquals(null, result2, 'Should return null for blank input.');
        // result3 depends on AccountSyncService existing in the org
        System.debug('AccountSyncService instance (null if not implemented): ' + result3);
    }

    @IsTest
    static void testGetSyncServiceClassCandidates_CustomObject() {
        Test.startTest();
        List<String> candidates = PaginationStrategy.getSyncServiceClassCandidates('PIM_Item__c');
        Test.stopTest();

        System.assertEquals(2, candidates.size(), 'Expected original and normalized candidates.');
        System.assertEquals('PIM_Item__cSyncService', candidates[0]);
        System.assertEquals('PIM_ItemSyncService', candidates[1]);
    }

    @IsTest
    static void testGetPaginationHeaders_Default() {
        ConcreteTestStrategy strategy = new ConcreteTestStrategy();
        Integration_Mapping__mdt mapping = setupMocksForTest(100, 1);
        Integration_Endpoint__mdt endpoint = mapping.Endpoint__r;
        strategy.initialize(endpoint, mapping, null);

        Test.startTest();
        Map<String, String> headers = strategy.callGetPaginationHeaders();
        Test.stopTest();

        System.assertNotEquals(null, headers, 'Headers map should not be null.');
        System.assertEquals(0, headers.size(), 'Default implementation should return empty map.');
    }

    @IsTest
    static void testConstructFullUrl() {
        ConcreteTestStrategy strategy = new ConcreteTestStrategy();

        Test.startTest();
        String url1 = strategy.callConstructFullUrl(' /api/v1/ ', ' /accounts/ ');
        String url2 = strategy.callConstructFullUrl('/api/v1', '/accounts');
        String url3 = strategy.callConstructFullUrl('api/v1', 'accounts');
        String url4 = strategy.callConstructFullUrl(' /api/v1/ ', null);
        String url5 = strategy.callConstructFullUrl(null, ' /accounts/ ');
        String url6 = strategy.callConstructFullUrl('api/v1/', '/accounts');
        Test.stopTest();

        System.assertEquals('/api/v1/accounts', url1, 'URL 1 incorrect.');
        System.assertEquals('/api/v1/accounts', url2, 'URL 2 incorrect.');
        System.assertEquals('/api/v1/accounts', url3, 'URL 3 incorrect.');
        System.assertEquals('/api/v1', url4, 'URL 4 incorrect.');
        System.assertEquals('/accounts', url5, 'URL 5 incorrect.');
        System.assertEquals('/api/v1/accounts', url6, 'URL 6 incorrect.');
    }

    @IsTest
    static void testModifyEndpointUrl_Default() {
        Integration_Mapping__mdt mapping = setupMocksForTest(100, 1);
        Integration_Endpoint__mdt endpoint = mapping.Endpoint__r;
        ConcreteTestStrategy strategy = new ConcreteTestStrategy();
        strategy.initialize(endpoint, mapping, null);

        Test.startTest();
        String modifiedUrl = strategy.modifyEndpointUrl('http://ignored.com', null);
        Test.stopTest();

        String expectedUrl = '/api/v1/accounts';
        System.assertEquals(expectedUrl, modifiedUrl, 'Default modifyEndpointUrl should construct from config.');
    }

    @IsTest
    static void testExtractRecords() {
        ConcreteTestStrategy strategy = new ConcreteTestStrategy();
        String jsonList = '[{"id":"1", "name":"A"}, {"id":"2", "name":"B"}]';
        String jsonMapWithRecords = '{"total":10, "records":[{"id":"3"}]}';
        String jsonMapWithItems = '{"items":[{"id":"4"}], "nextPage":"abc"}';
        String jsonMapWithData = '{"data":[{"id":"5"}]}';
        String jsonMapWithResults = '{"page":1, "results":[{"id":"6"}]}';
        String jsonMapNoArray = '{"total":1, "record":{"id":"7"}}';
        String jsonSingleObject = '{"id":"8"}';
        String invalidJson = '[{"id":]';
        String emptyBody = '';
        String nullBody = null;

        Test.startTest();
        List<Object> result1 = strategy.callExtractRecords(jsonList);
        List<Object> result2 = strategy.callExtractRecords(jsonMapWithRecords);
        List<Object> result3 = strategy.callExtractRecords(jsonMapWithItems);
        List<Object> result4 = strategy.callExtractRecords(jsonMapWithData);
        List<Object> result5 = strategy.callExtractRecords(jsonMapWithResults);
        List<Object> result6 = strategy.callExtractRecords(jsonMapNoArray);
        List<Object> result7 = strategy.callExtractRecords(jsonSingleObject);
        List<Object> result8 = strategy.callExtractRecords(invalidJson);
        List<Object> result9 = strategy.callExtractRecords(emptyBody);
        List<Object> result10 = strategy.callExtractRecords(nullBody);
        Test.stopTest();

        System.assertEquals(2, result1.size(), 'Result 1 size mismatch.');
        System.assertEquals(1, result2.size(), 'Result 2 size mismatch.');
        System.assertEquals(1, result3.size(), 'Result 3 size mismatch.');
        System.assertEquals(1, result4.size(), 'Result 4 size mismatch.');
        System.assertEquals(1, result5.size(), 'Result 5 size mismatch.');
        System.assertEquals(0, result6.size(), 'Result 6 should be empty (no array found).');
        System.assertEquals(0, result7.size(), 'Result 7 should be empty (single object).');
        System.assertEquals(0, result8.size(), 'Result 8 should be empty (invalid JSON).');
        System.assertEquals(0, result9.size(), 'Result 9 should be empty (empty body).');
        System.assertEquals(0, result10.size(), 'Result 10 should be empty (null body).');
    }

    @IsTest
    static void testHasMoreRecords_Default() {
        Integration_Mapping__mdt mapping = setupMocksForTest(100, 1);
        Integration_Endpoint__mdt endpoint = mapping.Endpoint__r;
        ConcreteTestStrategy strategy = new ConcreteTestStrategy();
        strategy.initialize(endpoint, mapping, null);

        HttpResponse mockResponse = new HttpResponse();
        mockResponse.setStatusCode(200);

        List<Object> fullPage = new List<Object>();
        for(Integer i=0; i<100; i++) fullPage.add(new Map<String,Object>());
        List<Object> partialPage = new List<Object>();
        for(Integer i=0; i<99; i++) partialPage.add(new Map<String,Object>());
        List<Object> overPage = new List<Object>();
        for(Integer i=0; i<101; i++) overPage.add(new Map<String,Object>());
        List<Object> emptyPage = new List<Object>();

        Test.startTest();
        Boolean resultFull = strategy.callHasMoreRecords(mockResponse, fullPage);
        Boolean resultPartial = strategy.callHasMoreRecords(mockResponse, partialPage);
        Boolean resultOver = strategy.callHasMoreRecords(mockResponse, overPage);
        Boolean resultEmpty = strategy.callHasMoreRecords(mockResponse, emptyPage);
        Boolean resultNullResponse = strategy.callHasMoreRecords(null, fullPage);
        Boolean resultNullList = strategy.callHasMoreRecords(mockResponse, null);
        Test.stopTest();

        System.assertEquals(true, resultFull, 'Full page should indicate more records.');
        System.assertEquals(false, resultPartial, 'Partial page should not indicate more records.');
        System.assertEquals(true, resultOver, 'Over page size should indicate more records.');
        System.assertEquals(false, resultEmpty, 'Empty page should not indicate more records.');
        System.assertEquals(false, resultNullResponse, 'Null response should result in false.');
        System.assertEquals(false, resultNullList, 'Null list should result in false.');
    }

    @IsTest
    static void testGetPaginationPageSize() {
        Integration_Mapping__mdt mapping1 = setupMocksForTest(123, 1);
        Integration_Endpoint__mdt endpoint1 = mapping1.Endpoint__r;
        ConcreteTestStrategy strategy1 = new ConcreteTestStrategy();
        strategy1.initialize(endpoint1, mapping1, null);

        IntegrationMappingCache.clearCache();
        IntegrationMappingCache.clearMockMappings();
        Integration_Endpoint__mdt mockEndpoint2 = new Integration_Endpoint__mdt(
            DeveloperName = 'TestEP2', Active__c = true, Base_Path__c = '/api', Named_Credential__c = 'NC'
        );
        Integration_Mapping__mdt mockMapping2 = new Integration_Mapping__mdt(
            DeveloperName = 'TestMap2', Active__c = true, Endpoint__r = mockEndpoint2, Endpoint__c = mockEndpoint2.id, Sync_Order__c = 1, Page_Size__c = null
        );
        IntegrationMappingCache.setMockMapping('TestMap2', mockMapping2);
        ConcreteTestStrategy strategy2 = new ConcreteTestStrategy();
        strategy2.initialize(mockEndpoint2, mockMapping2, null);

        Test.startTest();
        Integer size1 = strategy1.callGetPaginationPageSize();
        Integer size2 = strategy2.callGetPaginationPageSize();
        Test.stopTest();

        System.assertEquals(123, size1, 'Size 1: Should use Mapping Page_Size__c.');
        System.assertEquals(100, size2, 'Size 2: Should use default 100.');
    }

    @IsTest
    static void testCreateNextState_Default() {
        Integration_Mapping__mdt mapping = setupMocksForTest(100, 1);
        Integration_Endpoint__mdt endpoint = mapping.Endpoint__r;
        ConcreteTestStrategy strategy = new ConcreteTestStrategy();
        strategy.initialize(endpoint, mapping, null);

        HttpResponse mockResponse = new HttpResponse(); mockResponse.setStatusCode(200);
        PaginationState state1 = new PaginationState(0, 100);
        PaginationState state2 = new PaginationState(100, 100);

        Test.startTest();
        PaginationState nextStateInitial = strategy.callCreateNextState(mockResponse, null);
        PaginationState nextState1 = strategy.callCreateNextState(mockResponse, state1);
        PaginationState nextState2 = strategy.callCreateNextState(mockResponse, state2);
        PaginationState nextStateNullResponse = strategy.callCreateNextState(null, state1);
        Test.stopTest();

        System.assertNotEquals(null, nextStateInitial, 'Next state from null initial should not be null.');
        System.assertEquals(0, nextStateInitial.getOffset(), 'Initial next offset should be 0.');
        System.assertEquals(100, nextStateInitial.getPageSize(), 'Initial next page size should be 100.');

        System.assertNotEquals(null, nextState1, 'Next state 1 should not be null.');
        System.assertEquals(100, nextState1.getOffset(), 'Next state 1 offset should be 100.');

        System.assertNotEquals(null, nextState2, 'Next state 2 should not be null.');
        System.assertEquals(200, nextState2.getOffset(), 'Next state 2 offset should be 200.');

        System.assertEquals(null, nextStateNullResponse, 'Next state should be null if response is null.');
    }

    @IsTest
    static void testHandleErrors() {
        ConcreteTestStrategy strategy = new ConcreteTestStrategy();

        HttpResponse resSuccess = new HttpResponse(); resSuccess.setStatusCode(200); resSuccess.setStatus('OK');
        HttpResponse resBadRequest = new HttpResponse(); resBadRequest.setStatusCode(400); resBadRequest.setStatus('Bad Request'); resBadRequest.setBody('{"error":"Invalid Input"}');
        HttpResponse resServerError = new HttpResponse(); resServerError.setStatusCode(500); resServerError.setStatus('Server Error'); resServerError.setBody('<html>Error</html>');
        HttpResponse resNotFound = new HttpResponse(); resNotFound.setStatusCode(404); resNotFound.setStatus('Not Found'); resNotFound.setBody('{"message": "Resource missing"}');

        Test.startTest();
        String errSuccess = strategy.callHandleErrors(resSuccess);
        String errBadRequest = strategy.callHandleErrors(resBadRequest);
        String errServerError = strategy.callHandleErrors(resServerError);
        String errNotFound = strategy.callHandleErrors(resNotFound);
        String errNullResponse = strategy.callHandleErrors(null);
        Test.stopTest();

        System.assertEquals(null, errSuccess, 'Success response should have null error.');
        System.assert(errBadRequest != null && errBadRequest.contains('400'), 'Bad request error message incorrect.');
        System.assert(errServerError != null && errServerError.contains('500'), 'Server error message incorrect.');
        System.assert(errNotFound != null && errNotFound.contains('404'), 'Not found error message incorrect.');
        System.assert(errNullResponse != null && errNullResponse.contains('No HTTP response'), 'Null response error message incorrect.');
    }
}
