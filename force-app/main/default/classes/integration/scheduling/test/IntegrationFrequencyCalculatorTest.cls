/**
 * @description Test class for IntegrationFrequencyCalculator
 * @Author: R. Groot Date: 21-04-2026
 */
@IsTest
private class IntegrationFrequencyCalculatorTest {
    
    private static final String TEST_MAPPING_NAME = 'TestMapping_Frequency';
    
    @IsTest
    static void testShouldExecuteNow_NeverRun() {
        Test.startTest();
        Boolean shouldRun = IntegrationFrequencyCalculator.shouldExecuteNow(
            IntegrationFrequencyCalculator.FREQUENCY_DAILY,
            1,
            null
        );
        Test.stopTest();
        
        System.assertEquals(true, shouldRun, 'Should execute when never run before');
    }
    
    @IsTest
    static void testShouldExecuteNow_HourlyNotReady() {
        DateTime lastRun = DateTime.now().addMinutes(-30);
        
        Test.startTest();
        Boolean shouldRun = IntegrationFrequencyCalculator.shouldExecuteNow(
            IntegrationFrequencyCalculator.FREQUENCY_HOURLY,
            1,
            lastRun
        );
        Test.stopTest();
        
        System.assertEquals(false, shouldRun, 'Should not execute within 1 hour if just ran 30 minutes ago');
    }
    
    @IsTest
    static void testShouldExecuteNow_HourlyReady() {
        DateTime lastRun = DateTime.now().addHours(-2);
        
        Test.startTest();
        Boolean shouldRun = IntegrationFrequencyCalculator.shouldExecuteNow(
            IntegrationFrequencyCalculator.FREQUENCY_HOURLY,
            1,
            lastRun
        );
        Test.stopTest();
        
        System.assertEquals(true, shouldRun, 'Should execute after 1 hour has passed for hourly frequency');
    }
    
    @IsTest
    static void testShouldExecuteNow_DailyNotReady() {
        DateTime lastRun = DateTime.now().addHours(-12);
        
        Test.startTest();
        Boolean shouldRun = IntegrationFrequencyCalculator.shouldExecuteNow(
            IntegrationFrequencyCalculator.FREQUENCY_DAILY,
            1,
            lastRun
        );
        Test.stopTest();
        
        System.assertEquals(false, shouldRun, 'Should not execute within 1 day if just ran 12 hours ago');
    }
    
    @IsTest
    static void testShouldExecuteNow_DailyReady() {
        DateTime lastRun = DateTime.now().addDays(-2);
        
        Test.startTest();
        Boolean shouldRun = IntegrationFrequencyCalculator.shouldExecuteNow(
            IntegrationFrequencyCalculator.FREQUENCY_DAILY,
            1,
            lastRun
        );
        Test.stopTest();
        
        System.assertEquals(true, shouldRun, 'Should execute after 1 day has passed for daily frequency');
    }
    
    @IsTest
    static void testShouldExecuteNow_WeeklyNotReady() {
        DateTime lastRun = DateTime.now().addDays(-5);
        
        Test.startTest();
        Boolean shouldRun = IntegrationFrequencyCalculator.shouldExecuteNow(
            IntegrationFrequencyCalculator.FREQUENCY_WEEKLY,
            1,
            lastRun
        );
        Test.stopTest();
        
        System.assertEquals(false, shouldRun, 'Should not execute within 1 week if just ran 5 days ago');
    }
    
    @IsTest
    static void testShouldExecuteNow_WeeklyReady() {
        DateTime lastRun = DateTime.now().addDays(-10);
        
        Test.startTest();
        Boolean shouldRun = IntegrationFrequencyCalculator.shouldExecuteNow(
            IntegrationFrequencyCalculator.FREQUENCY_WEEKLY,
            1,
            lastRun
        );
        Test.stopTest();
        
        System.assertEquals(true, shouldRun, 'Should execute after 1 week has passed for weekly frequency');
    }
    
    @IsTest
    static void testShouldExecuteNow_CustomMinutesNotReady() {
        DateTime lastRun = DateTime.now().addMinutes(-10);
        
        Test.startTest();
        Boolean shouldRun = IntegrationFrequencyCalculator.shouldExecuteNow(
            IntegrationFrequencyCalculator.FREQUENCY_CUSTOM_MINUTES,
            15,
            lastRun
        );
        Test.stopTest();
        
        System.assertEquals(false, shouldRun, 'Should not execute within 15 minutes if just ran 10 minutes ago');
    }
    
    @IsTest
    static void testShouldExecuteNow_CustomMinutesReady() {
        DateTime lastRun = DateTime.now().addMinutes(-20);
        
        Test.startTest();
        Boolean shouldRun = IntegrationFrequencyCalculator.shouldExecuteNow(
            IntegrationFrequencyCalculator.FREQUENCY_CUSTOM_MINUTES,
            15,
            lastRun
        );
        Test.stopTest();
        
        System.assertEquals(true, shouldRun, 'Should execute after custom interval minutes has passed');
    }
    
    @IsTest
    static void testShouldExecuteNow_InvalidFrequencyType() {
        DateTime lastRun = DateTime.now().addHours(-1);
        
        Test.startTest();
        Boolean shouldRun = IntegrationFrequencyCalculator.shouldExecuteNow(
            'InvalidType',
            1,
            lastRun
        );
        Test.stopTest();
        
        System.assertEquals(false, shouldRun, 'Should return false for invalid frequency type');
    }
    
    @IsTest
    static void testShouldExecuteNow_InvalidFrequencyValue() {
        DateTime lastRun = DateTime.now().addHours(-1);
        
        Test.startTest();
        Boolean shouldRun = IntegrationFrequencyCalculator.shouldExecuteNow(
            IntegrationFrequencyCalculator.FREQUENCY_DAILY,
            -1,
            lastRun
        );
        Test.stopTest();
        
        System.assertEquals(false, shouldRun, 'Should return false for negative frequency value');
    }
    
    @IsTest
    static void testGetNextExecutionTime_Hourly() {
        DateTime lastRun = DateTime.newInstance(2026, 4, 21, 10, 0, 0);
        
        Test.startTest();
        DateTime nextTime = IntegrationFrequencyCalculator.getNextExecutionTime(
            IntegrationFrequencyCalculator.FREQUENCY_HOURLY,
            2,
            lastRun
        );
        Test.stopTest();
        
        DateTime expectedTime = DateTime.newInstance(2026, 4, 21, 12, 0, 0);
        System.assertEquals(expectedTime, nextTime, 'Should calculate next time as 2 hours later');
    }
    
    @IsTest
    static void testGetNextExecutionTime_Daily() {
        DateTime lastRun = DateTime.newInstance(2026, 4, 21, 10, 0, 0);
        
        Test.startTest();
        DateTime nextTime = IntegrationFrequencyCalculator.getNextExecutionTime(
            IntegrationFrequencyCalculator.FREQUENCY_DAILY,
            3,
            lastRun
        );
        Test.stopTest();
        
        DateTime expectedTime = DateTime.newInstance(2026, 4, 24, 10, 0, 0);
        System.assertEquals(expectedTime, nextTime, 'Should calculate next time as 3 days later');
    }
    
    @IsTest
    static void testGetNextExecutionTime_Weekly() {
        DateTime lastRun = DateTime.newInstance(2026, 4, 21, 10, 0, 0);
        
        Test.startTest();
        DateTime nextTime = IntegrationFrequencyCalculator.getNextExecutionTime(
            IntegrationFrequencyCalculator.FREQUENCY_WEEKLY,
            2,
            lastRun
        );
        Test.stopTest();
        
        DateTime expectedTime = DateTime.newInstance(2026, 5, 5, 10, 0, 0);
        System.assertEquals(expectedTime, nextTime, 'Should calculate next time as 2 weeks later');
    }
    
    @IsTest
    static void testGetNextExecutionTime_CustomMinutes() {
        DateTime lastRun = DateTime.newInstance(2026, 4, 21, 10, 30, 0);
        
        Test.startTest();
        DateTime nextTime = IntegrationFrequencyCalculator.getNextExecutionTime(
            IntegrationFrequencyCalculator.FREQUENCY_CUSTOM_MINUTES,
            45,
            lastRun
        );
        Test.stopTest();
        
        DateTime expectedTime = DateTime.newInstance(2026, 4, 21, 11, 15, 0);
        System.assertEquals(expectedTime, nextTime, 'Should calculate next time as 45 minutes later');
    }
    
    @IsTest
    static void testUpdateExecutionState() {
        Test.startTest();
        IntegrationFrequencyCalculator.updateExecutionState(
            TEST_MAPPING_NAME,
            IntegrationFrequencyCalculator.FREQUENCY_DAILY,
            1,
            DateTime.now()
        );
        Test.stopTest();
        
        IntegrationExecutionState__c state = IntegrationExecutionState__c.getInstance(TEST_MAPPING_NAME);
        System.assertNotEquals(null, state, 'Execution state should be created');
        System.assertEquals('Success', state.Last_Status__c, 'Status should be Success');
        System.assertNotEquals(null, state.Next_Scheduled_Time__c, 'Next scheduled time should be set');
    }
    
    @IsTest
    static void testRecordFailedExecution() {
        Test.startTest();
        IntegrationFrequencyCalculator.recordFailedExecution(TEST_MAPPING_NAME, 'Test error message');
        Test.stopTest();
        
        IntegrationExecutionState__c state = IntegrationExecutionState__c.getInstance(TEST_MAPPING_NAME);
        System.assertNotEquals(null, state, 'Execution state should be created');
        System.assertEquals('Failed', state.Last_Status__c, 'Status should be Failed');
    }
}
