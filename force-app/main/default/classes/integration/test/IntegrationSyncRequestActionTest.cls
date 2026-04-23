/**
 * @description Test class for IntegrationSyncRequestAction
 * @Author: R. Groot Date: 23-04-2026
 */
@IsTest
private class IntegrationSyncRequestActionTest {

    private static final String TEST_ENDPOINT = 'TestISRA_Endpoint';
    private static final String TEST_MAPPING  = 'TestISRA_Mapping';

    private static void setupMockCache() {
        Integration_Endpoint__mdt ep = new Integration_Endpoint__mdt(
            DeveloperName        = TEST_ENDPOINT,
            Active__c            = true,
            Base_Path__c         = '/api/',
            Named_Credential__c  = 'Test_Cred',
            External_ID_Field__c = 'AccountNumber',
            Pagination_Type__c   = 'offset',
            Timeout__c           = 30000
        );
        Integration_Mapping__mdt mp = new Integration_Mapping__mdt(
            DeveloperName        = TEST_MAPPING,
            Active__c            = true,
            Operation_Type__c    = 'Pull',
            Target_Object__c     = 'Account',
            Resource_Path__c     = 'accounts',
            Dataweave_Map_Name__c = 'AccountMap',
            Sync_Order__c        = 1,
            Endpoint__r          = ep
        );
        IntegrationMappingCache.clearCache();
        IntegrationMappingCache.clearMockMappings();
        IntegrationMappingCache.setMockMapping(TEST_MAPPING, mp);
    }

    // ─── Input validation ────────────────────────────────────────────────────

    @IsTest
    static void testTriggerSync_blankMappingName_returnsError() {
        IntegrationSyncRequestAction.Request req = new IntegrationSyncRequestAction.Request();
        req.mappingName = '';

        Test.startTest();
        List<IntegrationSyncRequestAction.Result> results =
            IntegrationSyncRequestAction.triggerSync(new List<IntegrationSyncRequestAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].isSuccess, 'Blank mapping name should return error');
        System.assert(results[0].errorMessage.contains('mappingName is required'), 'Error message should mention mappingName');
    }

    @IsTest
    static void testTriggerSync_mappingNotFound_returnsError() {
        IntegrationMappingCache.clearCache();
        IntegrationMappingCache.clearMockMappings();

        IntegrationSyncRequestAction.Request req = new IntegrationSyncRequestAction.Request();
        req.mappingName = 'NonExistentMapping_ISRA';

        Test.startTest();
        List<IntegrationSyncRequestAction.Result> results =
            IntegrationSyncRequestAction.triggerSync(new List<IntegrationSyncRequestAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(false, results[0].isSuccess, 'Unknown mapping should return error');
    }

    // ─── Batch sync ──────────────────────────────────────────────────────────

    @IsTest
    static void testTriggerSync_batchSync_enqueuesPullQueueable() {
        setupMockCache();

        IntegrationSyncRequestAction.Request req = new IntegrationSyncRequestAction.Request();
        req.mappingName = TEST_MAPPING;
        // No externalRecordId → batch sync

        Test.startTest();
        List<IntegrationSyncRequestAction.Result> results =
            IntegrationSyncRequestAction.triggerSync(new List<IntegrationSyncRequestAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(true, results[0].isSuccess, 'Batch sync should succeed');
        System.assertEquals(null, results[0].errorMessage, 'No error message expected');

        Integer jobs = [SELECT COUNT() FROM AsyncApexJob
            WHERE JobType = 'Queueable'
            AND ApexClass.Name = 'PullQueueable'];
        System.assert(jobs >= 1, 'PullQueueable should be enqueued');
    }

    @IsTest
    static void testTriggerSync_batchSync_customOperationName() {
        setupMockCache();

        IntegrationSyncRequestAction.Request req = new IntegrationSyncRequestAction.Request();
        req.mappingName  = TEST_MAPPING;
        req.operationName = 'MyCustomOp';

        Test.startTest();
        List<IntegrationSyncRequestAction.Result> results =
            IntegrationSyncRequestAction.triggerSync(new List<IntegrationSyncRequestAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(true, results[0].isSuccess, 'Custom operation name should not affect success');
    }

    // ─── Single record sync ──────────────────────────────────────────────────

    @IsTest
    static void testTriggerSync_singleRecord_enqueuesSingleRecordPullQueueable() {
        setupMockCache();

        IntegrationSyncRequestAction.Request req = new IntegrationSyncRequestAction.Request();
        req.mappingName      = TEST_MAPPING;
        req.externalRecordId = 'EXT-123';

        Test.startTest();
        List<IntegrationSyncRequestAction.Result> results =
            IntegrationSyncRequestAction.triggerSync(new List<IntegrationSyncRequestAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(true, results[0].isSuccess, 'Single record sync should succeed');

        Integer jobs = [SELECT COUNT() FROM AsyncApexJob
            WHERE JobType = 'Queueable'
            AND ApexClass.Name = 'SingleRecordPullQueueable'];
        System.assert(jobs >= 1, 'SingleRecordPullQueueable should be enqueued');
    }

    // ─── Bulk invocable (multiple requests in one call) ──────────────────────

    @IsTest
    static void testTriggerSync_multipleRequestsProcessedIndependently() {
        setupMockCache();

        IntegrationSyncRequestAction.Request r1 = new IntegrationSyncRequestAction.Request();
        r1.mappingName = TEST_MAPPING;

        IntegrationSyncRequestAction.Request r2 = new IntegrationSyncRequestAction.Request();
        r2.mappingName = ''; // intentionally invalid

        Test.startTest();
        List<IntegrationSyncRequestAction.Result> results =
            IntegrationSyncRequestAction.triggerSync(
                new List<IntegrationSyncRequestAction.Request>{ r1, r2 });
        Test.stopTest();

        System.assertEquals(2, results.size(), 'Should return one result per request');
        System.assertEquals(true,  results[0].isSuccess, 'First request should succeed');
        System.assertEquals(false, results[1].isSuccess, 'Second request should fail');
    }
}
