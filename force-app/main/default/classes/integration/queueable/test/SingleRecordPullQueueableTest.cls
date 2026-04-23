/**
 * @description Test class for SingleRecordPullQueueable
 * @Author: R. Groot Date: 23-04-2026
 */
@IsTest
private class SingleRecordPullQueueableTest {

    private static final String TEST_ENDPOINT = 'TestSRPQ_Endpoint';
    private static final String TEST_MAPPING  = 'TestSRPQ_Mapping';
    private static final String TEST_EXT_ID   = 'EXT-001';

    private class MockHttp implements HttpCalloutMock {
        Integer statusCode;
        String   body;
        MockHttp(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body       = body;
        }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            return res;
        }
    }

    private static void setupMockCache(String extIdField) {
        Integration_Endpoint__mdt ep = new Integration_Endpoint__mdt(
            DeveloperName        = TEST_ENDPOINT,
            Active__c            = true,
            Base_Path__c         = '/api/v1',
            Named_Credential__c  = 'Test_Cred',
            External_ID_Field__c = extIdField,
            Pagination_Type__c   = 'offset',
            Timeout__c           = 30000
        );
        Integration_Mapping__mdt mp = new Integration_Mapping__mdt(
            DeveloperName        = TEST_MAPPING,
            Active__c            = true,
            Operation_Type__c    = 'Pull',
            Target_Object__c     = 'Account',
            Resource_Path__c     = 'products',
            Dataweave_Map_Name__c = 'AccountMap',
            Sync_Order__c        = 1,
            Endpoint__r          = ep
        );
        IntegrationMappingCache.clearCache();
        IntegrationMappingCache.clearMockMappings();
        IntegrationMappingCache.setMockMapping(TEST_MAPPING, mp);
    }

    // ─── URL building ────────────────────────────────────────────────────────

    @IsTest
    static void testBuildSingleRecordUrl_standardPaths() {
        setupMockCache('AccountNumber');
        SingleRecordPullQueueable q = new SingleRecordPullQueueable(TEST_ENDPOINT, TEST_MAPPING, TEST_EXT_ID);
        String url = q.buildSingleRecordUrl();
        System.assertEquals('/api/v1/products/' + TEST_EXT_ID + '/', url,
            'URL should be base + resource + id + trailing slash');
    }

    @IsTest
    static void testBuildSingleRecordUrl_trailingSlashesAreNormalised() {
        Integration_Endpoint__mdt ep = new Integration_Endpoint__mdt(
            DeveloperName        = TEST_ENDPOINT,
            Active__c            = true,
            Base_Path__c         = '/api/v1/',
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
            Resource_Path__c     = 'products/',
            Dataweave_Map_Name__c = 'AccountMap',
            Sync_Order__c        = 1,
            Endpoint__r          = ep
        );
        IntegrationMappingCache.clearCache();
        IntegrationMappingCache.clearMockMappings();
        IntegrationMappingCache.setMockMapping(TEST_MAPPING, mp);

        SingleRecordPullQueueable q = new SingleRecordPullQueueable(TEST_ENDPOINT, TEST_MAPPING, TEST_EXT_ID);
        String url = q.buildSingleRecordUrl();
        System.assertEquals('/api/v1/products/' + TEST_EXT_ID + '/', url,
            'Trailing slashes on base and resource should be stripped before joining');
    }

    // ─── JSON normalisation ──────────────────────────────────────────────────

    @IsTest
    static void testNormaliseToJsonArray_objectGetsWrapped() {
        String result = SingleRecordPullQueueable.normaliseToJsonArray('{"id":"1"}');
        System.assertEquals('[{"id":"1"}]', result, 'Single object should be wrapped in array');
    }

    @IsTest
    static void testNormaliseToJsonArray_arrayPassesThrough() {
        String result = SingleRecordPullQueueable.normaliseToJsonArray('[{"id":"1"}]');
        System.assertEquals('[{"id":"1"}]', result, 'Array should pass through unchanged');
    }

    @IsTest
    static void testNormaliseToJsonArray_blankBody() {
        System.assertEquals('[]', SingleRecordPullQueueable.normaliseToJsonArray(null));
        System.assertEquals('[]', SingleRecordPullQueueable.normaliseToJsonArray(''));
        System.assertEquals('[]', SingleRecordPullQueueable.normaliseToJsonArray('   '));
    }

    // ─── pullAndProcessRecords error paths ───────────────────────────────────

    @IsTest
    static void testPullAndProcess_blankExternalId() {
        setupMockCache('AccountNumber');
        Test.setMock(HttpCalloutMock.class, new MockHttp(200, '[]'));

        Test.startTest();
        SingleRecordPullQueueable q = new SingleRecordPullQueueable(TEST_ENDPOINT, TEST_MAPPING, '');
        IntegrationResult result = q.pullAndProcessRecords();
        Test.stopTest();

        System.assertEquals(false, result.isSuccess, 'Blank externalRecordId should return error result');
    }

    @IsTest
    static void testPullAndProcess_httpError() {
        setupMockCache('AccountNumber');
        Test.setMock(HttpCalloutMock.class, new MockHttp(404, '{"error":"not found"}'));

        Test.startTest();
        SingleRecordPullQueueable q = new SingleRecordPullQueueable(TEST_ENDPOINT, TEST_MAPPING, TEST_EXT_ID);
        IntegrationResult result = q.pullAndProcessRecords();
        Test.stopTest();

        System.assertEquals(false, result.isSuccess, 'HTTP 404 should return error result');
    }

    @IsTest
    static void testPullAndProcess_http500() {
        setupMockCache('AccountNumber');
        Test.setMock(HttpCalloutMock.class, new MockHttp(500, 'Internal Server Error'));

        Test.startTest();
        SingleRecordPullQueueable q = new SingleRecordPullQueueable(TEST_ENDPOINT, TEST_MAPPING, TEST_EXT_ID);
        IntegrationResult result = q.pullAndProcessRecords();
        Test.stopTest();

        System.assertEquals(false, result.isSuccess, 'HTTP 500 should return error result');
    }

    // ─── Full execute (no DataWeave available in unit tests) ─────────────────

    @IsTest
    static void testExecute_runsWithoutInfiniteLoop() {
        setupMockCache('AccountNumber');
        Test.setMock(HttpCalloutMock.class, new MockHttp(200, '[{"AccountNumber":"EXT-001","Name":"Test"}]'));

        Test.startTest();
        System.enqueueJob(new SingleRecordPullQueueable(TEST_ENDPOINT, TEST_MAPPING, TEST_EXT_ID));
        Test.stopTest();

        // Verify no additional queueable jobs were spawned (no pagination loop)
        Integer queued = [SELECT COUNT() FROM AsyncApexJob
            WHERE JobType = 'Queueable'
            AND ApexClass.Name = 'SingleRecordPullQueueable'
            AND Status = 'Queued'];
        System.assertEquals(0, queued, 'Single record sync should not re-enqueue itself');
    }
}
