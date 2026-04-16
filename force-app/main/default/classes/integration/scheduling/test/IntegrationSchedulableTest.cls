@IsTest
private class IntegrationSchedulableTest {

    private static String testEndpointName = 'TestScheduleEndpoint';
    private static String testMappingName = 'TestScheduleMapping';

    @IsTest
    static void testConstructor_Valid() {
        String endpointName = 'ValidEndpoint';
        IntegrationSchedulable sched = null;
        Exception thrownEx = null;

        Test.startTest();
        try {
            sched = new IntegrationSchedulable(endpointName);
        } catch (Exception e) {
            thrownEx = e;
        }
        Test.stopTest();

        System.assertEquals(null, thrownEx, 'No exception should be thrown for valid endpoint name.');
        System.assertNotEquals(null, sched, 'Scheduler should be instantiated.');
        Map<String, Object> schedMap = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(sched));
        System.assertEquals(endpointName, schedMap.get('endpointName'), 'Endpoint name should be stored.');
    }

    @IsTest
    static void testConstructor_Invalid() {
        String endpointName = '';
        IntegrationSchedulable sched = null;
        Exception thrownEx = null;

        Test.startTest();
        try {
            sched = new IntegrationSchedulable(endpointName);
        } catch (Exception e) {
            thrownEx = e;
        }
        Test.stopTest();

        System.assertNotEquals(null, thrownEx, 'IllegalArgumentException should be thrown.');
        System.assert(thrownEx.getMessage().contains('Endpoint name cannot be null or empty'), 'Correct exception message.');
        System.assertEquals(null, sched, 'Scheduler should not be instantiated.');
    }

    @IsTest
    static void testExecute_Success() {
        IntegrationSchedulable sched = new IntegrationSchedulable(testEndpointName);
        Exception caughtEx = null;

        Test.startTest();
        String cronExpr = '0 0 1 * * ?';
        String jobId = System.schedule('TestJobExecute_' + System.now().getTime(), cronExpr, sched);
        CronTrigger ct = [SELECT Id, CronJobDetail.Id FROM CronTrigger WHERE Id = :jobId];

        try {
            sched.execute(null);
        } catch (Exception e) {
            caughtEx = e;
        }
        Test.stopTest();

        System.assertEquals(null, caughtEx, 'sched.execute should run without unexpected exceptions for a valid endpoint name.');
    }

    @IsTest
    static void testExecute_NoMappingFound() {
        String endpointName = 'EndpointWithNoMapping_NotInOrg';

        IntegrationSchedulable sched = new IntegrationSchedulable(endpointName);
        Exception caughtEx = null;
        Integer jobsBefore = Limits.getQueueableJobs();

        Test.startTest();
        try {
            sched.execute(null);
        } catch (Exception e) {
            caughtEx = e;
        }
        Integer jobsAfter = Limits.getQueueableJobs();
        Test.stopTest();

        System.assertEquals(null, caughtEx, 'execute should not throw unexpected exceptions even if mapping not found.');
        System.assertEquals(jobsBefore, jobsAfter, 'No job should be enqueued if mapping is not found.');
    }

    @IsTest
    static void testExecute_BlankEndpointStored() {
        IntegrationSchedulable sched = new IntegrationSchedulable('TemporaryValid');
        Map<String, Object> schedMap = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(sched));
        schedMap.put('endpointName', '');
        IntegrationSchedulable schedInvalid = (IntegrationSchedulable) JSON.deserialize(JSON.serialize(schedMap), IntegrationSchedulable.class);

        Test.startTest();
        Integer jobsBefore = Limits.getQueueableJobs();
        schedInvalid.execute(null);
        Integer jobsAfter = Limits.getQueueableJobs();
        Test.stopTest();

        System.assertEquals(jobsBefore, jobsAfter, 'No job should be enqueued if stored endpoint name is blank.');
    }

    @IsTest
    static void testStartIntegrationForEndpointAndOrder_Success() {
        Integer syncOrder = 1;
        Exception caughtEx = null;

        Test.startTest();
        try {
            IntegrationSchedulable.startIntegrationForEndpointAndOrder(testEndpointName, syncOrder);
        } catch (Exception e) {
            caughtEx = e;
        }
        Test.stopTest();

        System.assertEquals(null, caughtEx, 'startIntegrationForEndpointAndOrder should run without unexpected exceptions for valid inputs.');
    }

    @IsTest
    static void testStartIntegrationForEndpointAndOrder_BlankEndpoint() {
        Test.startTest();
        Integer jobsBefore = Limits.getQueueableJobs();
        IntegrationSchedulable.startIntegrationForEndpointAndOrder('', 1);
        Integer jobsAfter = Limits.getQueueableJobs();
        Test.stopTest();

        System.assertEquals(jobsBefore, jobsAfter, 'No job should be enqueued for blank endpoint.');
    }

    @IsTest
    static void testStartIntegrationForEndpointAndOrder_InvalidOrder() {
        Test.startTest();
        Integer jobsBefore = Limits.getQueueableJobs();
        IntegrationSchedulable.startIntegrationForEndpointAndOrder('ValidEndpoint', 0);
        Integer jobsAfter = Limits.getQueueableJobs();
        Test.stopTest();

        System.assertEquals(jobsBefore, jobsAfter, 'No job should be enqueued for invalid sync order.');
    }

    @IsTest
    static void testStartIntegrationForEndpointAndOrder_NoMapping() {
        String nonExistentEndpoint = 'NonExistentEndpoint_NotInOrg';

        Integer jobsBefore = Limits.getQueueableJobs();
        Exception caughtEx = null;

        Test.startTest();
        try {
            IntegrationSchedulable.startIntegrationForEndpointAndOrder(nonExistentEndpoint, 1);
        } catch (Exception e) {
            caughtEx = e;
        }
        Integer jobsAfter = Limits.getQueueableJobs();
        Test.stopTest();

        System.assertEquals(null, caughtEx, 'startIntegration... should not throw unexpected exceptions even if mapping not found.');
        System.assertEquals(jobsBefore, jobsAfter, 'No job should be enqueued if mapping is not found.');
    }

    @IsTest
    static void testScheduleIntegration_Success() {
        String endpointName = 'TestScheduleEndpoint';
        String cronExp = '0 0 2 * * ?';

        List<CronTrigger> existingJobs = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE 'Integration_TestScheduleEndpoint_%'];
        for(CronTrigger job : existingJobs) {
            System.abortJob(job.Id);
        }

        Test.startTest();
        String jobId = IntegrationSchedulable.scheduleIntegration(endpointName, cronExp);
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Job ID should be returned after scheduling.');
        CronTrigger ct = [SELECT Id, State FROM CronTrigger WHERE Id = :jobId LIMIT 1];
        System.assertNotEquals(null, ct, 'CronTrigger should exist for the scheduled job.');
    }

    @IsTest
    static void testScheduleIntegration_BlankEndpoint() {
        Exception thrownEx = null;

        Test.startTest();
        try {
            IntegrationSchedulable.scheduleIntegration('', '0 0 2 * * ?');
        } catch (Exception e) {
            thrownEx = e;
        }
        Test.stopTest();

        System.assertNotEquals(null, thrownEx, 'Exception expected for blank endpoint.');
    }

    @IsTest
    static void testScheduleIntegration_BlankCron() {
        Exception thrownEx = null;

        Test.startTest();
        try {
            IntegrationSchedulable.scheduleIntegration('ValidEndpoint', '');
        } catch (Exception e) {
            thrownEx = e;
        }
        Test.stopTest();

        System.assertNotEquals(null, thrownEx, 'Exception expected for blank cron expression.');
    }
}
