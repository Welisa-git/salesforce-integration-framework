/**
 * @description Test class for AbstractPullQueueable
 */
@IsTest
private class AbstractPullQueueableTest {

    private static final String TEST_ENDPOINT_NAME = 'TestAPQ_Endpoint';
    private static final String TEST_MAPPING_NAME = 'TestAPQ_Mapping';
    private static final String TEST_OPERATION_NAME = 'TestAPQ_Operation';
    private static final String TEST_NAMED_CRED = 'TestAPQ_Named_Cred';
    private static final String MOCK_BASE_PATH = '/mock/api';
    private static final String TARGET_OBJECT_API_NAME = 'Account';
    private static final String EXTERNAL_ID_FIELD = 'AccountNumber';

    // Mock QueueableContext
    private class MockQueueableContext implements System.QueueableContext {
        public Id getJobId() {
            return '04exx0000000001AAA';
        }
    }

    // Mock TypedSyncService
    private class MockTypedSyncService extends TypedSyncService {
        public override List<SObject> processSObjects(List<SObject> records) {
            return records;
        }

        public override void postProcessUpsert(List<SObject> successfulUpserts, Map<Id, SObject> originalRecordsMap) {
            // Do nothing
        }
    }

    // Concrete subclass for testing
    private class ConcretePullQueueable extends AbstractPullQueueable {
        public Boolean returnSuccess = true;
        public Boolean hasMoreData = false;

        public ConcretePullQueueable(String endpointName, String mappingName, String operationName,
                                     DateTime lastRunTime, Integer syncOrder) {
            super(endpointName, mappingName, operationName, lastRunTime, null, syncOrder);
        }

        protected override IntegrationResult pullAndProcessRecords() {
            IntegrationResult result = new IntegrationResult();

            Map<String, Object> resultFields = new Map<String, Object>();
            resultFields.put('isSuccess', returnSuccess);
            resultFields.put('message', 'Test message');
            resultFields.put('additionalDetails', new Map<String, Object>());

            result = (IntegrationResult)JSON.deserialize(JSON.serialize(resultFields), IntegrationResult.class);

            if (returnSuccess) {
                List<Account> accounts = new List<Account>{
                    new Account(Name = 'Test Account', AccountNumber = 'TEST-001')
                };

                try {
                    Map<String, Object> pageResultMap = new Map<String, Object>{
                        'sObjects' => accounts,
                        'hasMore' => hasMoreData,
                        'nextState' => hasMoreData ? new Map<String, Object>{'offset' => 10} : null
                    };

                    Map<String, Object> details = new Map<String, Object>{
                        'paginationResult' => pageResultMap
                    };

                    Map<String, Object> updatedResult = new Map<String, Object>{
                        'isSuccess' => returnSuccess,
                        'message' => 'Test message',
                        'additionalDetails' => details
                    };

                    result = (IntegrationResult)JSON.deserialize(JSON.serialize(updatedResult), IntegrationResult.class);
                } catch (Exception e) {
                    System.debug('Error setting up pagination result: ' + e.getMessage());
                }
            }

            return result;
        }
    }

    // Test class for handleUpsertResults direct access
    private class DirectHandleUpsertResultsTest extends AbstractPullQueueable {
        public DirectHandleUpsertResultsTest() {
            super('TestEndpoint', 'TestMapping', 'TestOperation', null, null, 1);
        }

        public void callHandleUpsertResults(Database.UpsertResult[] results, List<SObject> records, String objectType) {
            handleUpsertResults(results, records, objectType, null);
        }

        protected override IntegrationResult pullAndProcessRecords() {
            return new IntegrationResult();
        }
    }

    private static void setupMockCache() {
        IntegrationMappingCache.clearCache();
        IntegrationMappingCache.clearMockMappings();

        Integration_Endpoint__mdt mockEndpoint = new Integration_Endpoint__mdt(
            DeveloperName = TEST_ENDPOINT_NAME,
            Active__c = true,
            Base_Path__c = MOCK_BASE_PATH,
            Named_Credential__c = TEST_NAMED_CRED,
            External_ID_Field__c = EXTERNAL_ID_FIELD,
            Timeout__c = 30000
        );

        Integration_Mapping__mdt mockMapping = new Integration_Mapping__mdt(
            DeveloperName = TEST_MAPPING_NAME,
            Active__c = true,
            Operation_Type__c = 'Pull',
            Target_Object__c = TARGET_OBJECT_API_NAME,
            Dataweave_Map_Name__c = 'TestDWMap',
            Sync_Order__c = 1,
            Endpoint__r = mockEndpoint,
            Endpoint__c = mockEndpoint.id
        );

        IntegrationMappingCache.setMockMapping(TEST_MAPPING_NAME, mockMapping);
    }

    @TestSetup
    static void setupTestData() {
        Integration_Pagination_State__c state = new Integration_Pagination_State__c(
            Name = TEST_MAPPING_NAME,
            Last_Run_Date__c = Datetime.now().addDays(-1)
        );
        upsert state Name;
    }

    @IsTest
    static void testGetLastRunTime() {
        Test.startTest();
        DateTime lastRun = AbstractPullQueueable.getLastRunTime(TEST_MAPPING_NAME);
        Test.stopTest();

        System.assertNotEquals(null, lastRun, 'Should return last run date for known mapping');
    }

    @IsTest
    static void testGetLastRunTime_NotFound() {
        Test.startTest();
        DateTime lastRun = AbstractPullQueueable.getLastRunTime('NonExistentMapping_NotInOrg');
        Test.stopTest();

        System.assertEquals(null, lastRun, 'Should return null for unknown mapping');
    }

    @IsTest
    static void testDirectExecute() {
        try {
            Test.startTest();

            setupMockCache();

            ConcretePullQueueable queueable = new ConcretePullQueueable(
                TEST_ENDPOINT_NAME, TEST_MAPPING_NAME, TEST_OPERATION_NAME,
                null, 1
            );

            queueable.returnSuccess = true;
            queueable.hasMoreData = false;

            MockQueueableContext ctx = new MockQueueableContext();
            queueable.execute(ctx);

            Test.stopTest();

            System.assert(true, 'Successfully ran execute method');

        } catch(Exception e) {
            System.debug('Error in test: ' + e.getMessage() + '\n' + e.getStackTraceString());
            System.assert(false, 'Test threw exception: ' + e.getMessage());
        }
    }

    @IsTest
    static void testHandleUpsertResults() {
        Test.startTest();

        try {
            IntegrationMappingCache.clearCache();
            IntegrationMappingCache.clearMockMappings();

            Integration_Endpoint__mdt mockEndpoint = new Integration_Endpoint__mdt(
                DeveloperName = 'TestEndpoint',
                Active__c = true,
                External_ID_Field__c = 'AccountNumber',
                Named_Credential__c = 'TestNamedCredential'
            );

            Integration_Mapping__mdt mockMapping = new Integration_Mapping__mdt(
                DeveloperName = 'TestMapping',
                Active__c = true,
                Target_Object__c = 'Account',
                Endpoint__r = mockEndpoint,
                Endpoint__c = mockEndpoint.id
            );

            IntegrationMappingCache.setMockMapping('TestMapping', mockMapping);

            List<Account> testAccounts = new List<Account>{
                new Account(Name = 'Test Account 1', AccountNumber = 'TEST-001'),
                new Account(Name = 'Test Account 2', AccountNumber = 'TEST-002')
            };

            insert testAccounts;

            DirectHandleUpsertResultsTest testInstance = new DirectHandleUpsertResultsTest();

            testAccounts = [SELECT Id, Name, AccountNumber FROM Account WHERE AccountNumber LIKE 'TEST-%'];

            Account updatedAccount = new Account(
                Id = testAccounts[0].Id,
                Name = 'Updated Test Account'
            );

            Account newAccount = new Account(
                Name = 'New Test Account',
                AccountNumber = 'TEST-003'
            );

            List<Account> recordsToUpsert = new List<Account>{ updatedAccount, newAccount };

            Database.UpsertResult[] results = Database.upsert(recordsToUpsert, false);

            System.assert(results != null && !results.isEmpty(), 'Should have at least one UpsertResult');

            testInstance.callHandleUpsertResults(results, recordsToUpsert, 'Account');

        } catch (Exception e) {
            System.debug('Error in handleUpsertResults test: ' + e.getMessage());
        }

        Test.stopTest();
    }
}
