/**
 * @description Test class for UniversalIntegrationScheduler
 * @Author: R. Groot Date: 21-04-2026
 */
@IsTest
private class UniversalIntegrationSchedulerTest {
    
    private static final String TEST_ENDPOINT_NAME = 'TestEndpoint_Universal';
    private static final String TEST_MAPPING_NAME = 'TestMapping_Universal';
    
    @TestSetup
    static void setupTestData() {
        // Setup is minimal - we'll use mock data in tests
    }
    
    @IsTest
    static void testExecute_WithoutActiveEndpoints() {
        Test.startTest();
        try {
            UniversalIntegrationScheduler scheduler = new UniversalIntegrationScheduler();
            scheduler.execute(null);
        } catch (Exception e) {
            System.assert(false, 'Should not throw exception with no endpoints: ' + e.getMessage());
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testScheduleUniversalScheduler_Valid() {
        Test.startTest();
        try {
            String jobId = UniversalIntegrationScheduler.scheduleUniversalScheduler('Test Scheduler', 15);
            System.assertNotEquals(null, jobId, 'Job ID should be returned');
        } catch (Exception e) {
            System.assert(false, 'Should not throw exception for valid parameters: ' + e.getMessage());
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testScheduleUniversalScheduler_BlankJobName() {
        Test.startTest();
        try {
            UniversalIntegrationScheduler.scheduleUniversalScheduler('', 15);
            System.assert(false, 'Should throw exception for blank job name');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('Job name cannot be blank'));
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testScheduleUniversalScheduler_InvalidInterval() {
        Test.startTest();
        try {
            UniversalIntegrationScheduler.scheduleUniversalScheduler('Test', 0);
            System.assert(false, 'Should throw exception for invalid interval');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('Interval must be greater than 0'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testScheduleUniversalScheduler_IntervalHighValid() {
        Test.startTest();
        try {
            String jobId = UniversalIntegrationScheduler.scheduleUniversalScheduler('120 Min Scheduler', 120);
            System.assertNotEquals(null, jobId, 'Interval >= 60 should schedule hourly and be valid');
        } catch (Exception e) {
            System.assert(false, 'Interval of 120 should not throw: ' + e.getMessage());
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testGetOrCreateExecutionState_New() {
        String mappingName = 'NewMapping_ExecutionState';
        
        Test.startTest();
        IntegrationExecutionState__c state = UniversalIntegrationScheduler.getOrCreateExecutionState(mappingName);
        Test.stopTest();
        
        System.assertNotEquals(null, state, 'Should return execution state');
        System.assertEquals(mappingName, state.Name, 'Name should match mapping name');
    }
    
    @IsTest
    static void testGetOrCreateExecutionState_Existing() {
        String mappingName = 'ExistingMapping_ExecutionState';
        
        // Create initial state
        IntegrationExecutionState__c initialState = new IntegrationExecutionState__c(Name = mappingName);
        insert initialState;
        
        Test.startTest();
        IntegrationExecutionState__c retrievedState = UniversalIntegrationScheduler.getOrCreateExecutionState(mappingName);
        Test.stopTest();
        
        System.assertNotEquals(null, retrievedState, 'Should return existing execution state');
        System.assertEquals(initialState.Id, retrievedState.Id, 'Should return the same state');
    }
    
    @IsTest
    static void testScheduleUniversalScheduler_5MinuteInterval() {
        Test.startTest();
        try {
            String jobId = UniversalIntegrationScheduler.scheduleUniversalScheduler('5 Min Scheduler', 5);
            System.assertNotEquals(null, jobId, '5 minute interval should be valid');
        } catch (Exception e) {
            System.assert(false, '5 minute interval should not throw: ' + e.getMessage());
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testScheduleUniversalScheduler_30MinuteInterval() {
        Test.startTest();
        try {
            String jobId = UniversalIntegrationScheduler.scheduleUniversalScheduler('30 Min Scheduler', 30);
            System.assertNotEquals(null, jobId, '30 minute interval should be valid');
        } catch (Exception e) {
            System.assert(false, '30 minute interval should not throw: ' + e.getMessage());
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testGetOrCreateExecutionState_BlankName() {
        Test.startTest();
        try {
            IntegrationExecutionState__c state = UniversalIntegrationScheduler.getOrCreateExecutionState('');
            // Should return null or empty state for blank name
            System.assertEquals(null, state, 'Should return null for blank name');
        } catch (Exception e) {
            // Exception is acceptable too
        }
        Test.stopTest();
    }
}
