/**
 * @description Test class for PullQueueable
 */
@IsTest
private class PullQueueableTest {

    private static String testEndpointName = 'TestPullQueueEndpoint';
    private static String testMappingName1 = 'TestPullMapping1';
    private static String testMappingName2 = 'TestPullMapping2';
    private static String testNamedCredential = 'Test_Named_Cred';
    private static String mockBasePath = 'https://mock.api.example.com';
    private static String mockStrategyClassName = 'PullQueueableTest.MockPaginationStrategy';

    // --- Mock HTTP Callout ---
    private class MockHttpResponseGenerator implements HttpCalloutMock {
        Map<String, HttpResponse> responses = new Map<String, HttpResponse>();

        public void addResponse(String url, Integer statusCode, String body) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            this.responses.put(url, res);
        }

        public void addResponse(String url, Integer statusCode, String status, String body) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setStatus(status);
            res.setBody(body);
            this.responses.put(url, res);
        }

        public HttpResponse respond(HttpRequest req) {
            String url = req.getEndpoint();
            if (responses.containsKey(url)) {
                return responses.get(url);
            } else {
                HttpResponse res = new HttpResponse();
                res.setStatusCode(404);
                res.setStatus('Not Found in Mock');
                res.setBody('{"error": "Mock response not configured for this URL"}');
                return res;
            }
        }
    }

    // --- Mock Pagination Strategy ---
    public class MockPaginationStrategy extends PaginationStrategy {
        public Boolean processSObjectsCalled = false;
        public List<Object> responseRecords = new List<Object>();
        public PaginationState nextStateToReturn = null;
        public Boolean hasMoreDataToReturn = false;
        public String modifyUrlReturnValue = '';

        public override PaginationResult processResponse(HttpResponse response, PaginationState state) {
            if (response.getStatusCode() >= 400) {
                return PaginationResult.createError('Mock HTTP Error: ' + response.getStatusCode());
            }
            return PaginationResult.createSuccess(this.responseRecords, this.nextStateToReturn, this.hasMoreDataToReturn);
        }

        public override String modifyEndpointUrl(String baseUrl, PaginationState state) {
            return this.modifyUrlReturnValue;
        }

        public override List<SObject> processSObjects(List<SObject> sObjects) {
            this.processSObjectsCalled = true;
            for(SObject s : sObjects) {
                if(s.getSObjectType() == Account.SObjectType) {
                    ((Account)s).Description = 'Processed by Mock';
                }
            }
            return sObjects;
        }
    }

    private class FilterInspectingPullQueueable extends PullQueueable {
        public FilterInspectingPullQueueable(String endpointName, String mappingName, String operationName,
                                            DateTime lastRunTime, PaginationState paginationState, Integer syncOrder) {
            super(endpointName, mappingName, operationName, lastRunTime, paginationState, syncOrder);
        }

        public List<SObject> callFilterAndProcessRecords(List<SObject> records) {
            return filterAndProcessRecords(records);
        }

        public void setExternalIdFieldForTest(String fieldName) {
            endpoint.External_ID_Field__c = fieldName;
        }
    }

    private static void setupMockEndpointAndMapping(String endpointName, String mappingName, Decimal syncOrder) {
        Integration_Endpoint__mdt mockEndpoint = new Integration_Endpoint__mdt(
            DeveloperName = endpointName,
            Active__c = true,
            Base_Path__c = mockBasePath,
            Named_Credential__c = testNamedCredential,
            External_ID_Field__c = 'ExternalId__c',
            Pagination_Config__c = mockStrategyClassName,
            Timeout__c = 30000
        );

        Integration_Mapping__mdt mockMapping = new Integration_Mapping__mdt(
            DeveloperName = mappingName,
            Endpoint__c = mockEndpoint.Id,
            Endpoint__r = mockEndpoint,
            Active__c = true,
            Operation_Type__c = 'Pull',
            Target_Object__c = 'Account',
            Resource_Path__c = '/accounts',
            Sync_Order__c = syncOrder,
            Dataweave_Map_Name__c = 'AccountPullMap'
        );

        IntegrationMappingCache.setMockMapping(mappingName, mockMapping);
    }

    private static MockPaginationStrategy setupMockPaginationStrategy(String urlToReturn, Boolean hasMoreData) {
        MockPaginationStrategy mockStrategy = new MockPaginationStrategy();
        mockStrategy.modifyUrlReturnValue = urlToReturn;
        mockStrategy.hasMoreDataToReturn = hasMoreData;

        mockStrategy.responseRecords = new List<Object>{
            new Map<String, Object>{
                'id' => 'test123',
                'name' => 'Test Record',
                'attributes' => new Map<String, Object>{
                    'type' => 'Account'
                }
            }
        };

        PaginationStrategyFactory.setMockStrategy(mockStrategy);

        return mockStrategy;
    }

    @TestSetup
    static void setupTestData() {
        IntegrationMappingCache.clearMockMappings();
        PaginationStrategyFactory.clearMockStrategy();
    }

    @IsTest
    static void testExecute_SinglePage_SingleMapping() {
        IntegrationMappingCache.clearMockMappings();
        PaginationStrategyFactory.clearMockStrategy();

        String endpointDevName = testEndpointName;
        String mappingDevName = testMappingName1;
        Integer syncOrder = 1;
        DateTime runTime = DateTime.now();

        setupMockEndpointAndMapping(endpointDevName, mappingDevName, syncOrder);

        MockHttpResponseGenerator mockHttp = new MockHttpResponseGenerator();
        String expectedUrl = mockBasePath + '/accounts';
        String responseBody = '[{"id": "extAcc1", "name": "Test Account 1", "attributes": {"type": "Account"}}, {"id": "extAcc2", "name": "Test Account 2", "attributes": {"type": "Account"}}]';
        mockHttp.addResponse(expectedUrl, 200, responseBody);
        Test.setMock(HttpCalloutMock.class, mockHttp);

        MockPaginationStrategy mockStrategy = setupMockPaginationStrategy(expectedUrl, false);

        Test.startTest();
        System.enqueueJob(new PullQueueable(endpointDevName, mappingDevName, mappingDevName, runTime, null, syncOrder));
        Test.stopTest();

        Integer queueableJobs = [SELECT count() FROM AsyncApexJob WHERE JobType = 'Queueable' AND ApexClass.Name = 'PullQueueable' AND Status = 'Queued'];
        System.assertEquals(0, queueableJobs, 'Should be 0 remaining queued jobs after single-page run.');
    }

    @IsTest
    static void testExecute_MultiPage_SingleMapping() {
        IntegrationMappingCache.clearMockMappings();
        PaginationStrategyFactory.clearMockStrategy();

        String endpointDevName = testEndpointName;
        String mappingDevName = testMappingName1;
        Integer syncOrder = 1;
        DateTime runTime = DateTime.now();

        setupMockEndpointAndMapping(endpointDevName, mappingDevName, syncOrder);

        MockHttpResponseGenerator mockHttp = new MockHttpResponseGenerator();
        String urlPage1 = mockBasePath + '/accounts?page=1';
        String urlPage2 = mockBasePath + '/accounts?page=2';
        String responseBody1 = '[{"id": "page1Acc1", "name": "Page 1 Acc 1", "attributes": {"type": "Account"}}]';
        String responseBody2 = '[{"id": "page2Acc1", "name": "Page 2 Acc 1", "attributes": {"type": "Account"}}]';
        mockHttp.addResponse(urlPage1, 200, responseBody1);
        mockHttp.addResponse(urlPage2, 200, responseBody2);
        Test.setMock(HttpCalloutMock.class, mockHttp);

        MockPaginationStrategy mockStrategy = setupMockPaginationStrategy(urlPage1, true);

        Test.startTest();
        System.enqueueJob(new PullQueueable(endpointDevName, mappingDevName, mappingDevName, runTime, null, syncOrder));
        Test.stopTest();

        Integer queueableJobs = [SELECT count() FROM AsyncApexJob WHERE JobType = 'Queueable' AND ApexClass.Name = 'PullQueueable' AND Status = 'Queued'];
        System.assertEquals(0, queueableJobs, 'No remaining queued jobs after multi-page test.');
    }

    @IsTest
    static void testExecute_LastPage_ChainToNextMapping() {
        IntegrationMappingCache.clearMockMappings();
        PaginationStrategyFactory.clearMockStrategy();

        String endpointDevName = testEndpointName;
        String mapping1DevName = testMappingName1;
        String mapping2DevName = testMappingName2;
        Integer syncOrder1 = 1;
        Integer syncOrder2 = 2;
        DateTime runTime = DateTime.now();

        setupMockEndpointAndMapping(endpointDevName, mapping1DevName, syncOrder1);
        setupMockEndpointAndMapping(endpointDevName, mapping2DevName, syncOrder2);

        MockHttpResponseGenerator mockHttp = new MockHttpResponseGenerator();
        String expectedUrl = mockBasePath + '/accounts';
        String responseBody = '[{"id": "lastAcc", "name": "Last Account", "attributes": {"type": "Account"}}]';
        mockHttp.addResponse(expectedUrl, 200, responseBody);
        Test.setMock(HttpCalloutMock.class, mockHttp);

        MockPaginationStrategy mockStrategy = setupMockPaginationStrategy(expectedUrl, false);

        Test.startTest();
        System.enqueueJob(new PullQueueable(endpointDevName, mapping1DevName, mapping1DevName, runTime, null, syncOrder1));
        Test.stopTest();

        System.debug('INFO: Chain-to-next-mapping test completed successfully.');
    }

    @IsTest
    static void testFilterAndProcessRecords_SkipsMissingExternalId() {
        IntegrationMappingCache.clearMockMappings();
        PaginationStrategyFactory.clearMockStrategy();

        String endpointDevName = testEndpointName;
        String mappingDevName = testMappingName1;
        Integer syncOrder = 1;

        setupMockEndpointAndMapping(endpointDevName, mappingDevName, syncOrder);

        FilterInspectingPullQueueable queueable = new FilterInspectingPullQueueable(
            endpointDevName,
            mappingDevName,
            mappingDevName,
            null,
            null,
            syncOrder
        );
        queueable.setExternalIdFieldForTest('AccountNumber');

        List<SObject> filteredRecords = queueable.callFilterAndProcessRecords(new List<SObject>{
            new Account(Name = 'Keep Me', AccountNumber = 'ACC-001'),
            new Account(Name = 'Skip Me')
        });

        System.assertEquals(1, filteredRecords.size(), 'Only records with an external ID should remain.');
        System.assertEquals('ACC-001', (String) filteredRecords[0].get('AccountNumber'), 'Expected the record with AccountNumber to remain.');
    }
}
