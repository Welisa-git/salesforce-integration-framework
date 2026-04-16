@IsTest
private class ThrottledIntegrationRunnerTest {

    @IsTest
    static void testSkipsWhenJobsRunning() {
        ThrottledIntegrationRunner.runningJobsOverride = 5;
        ThrottledIntegrationRunner.lastRunOverride = null;
        ThrottledIntegrationRunner.integrationInvoked = false;

        ThrottledIntegrationRunner runner = new ThrottledIntegrationRunner('EndpointA', 1, 3, 0, false);

        Test.startTest();
        runner.execute(null);
        Test.stopTest();

        System.assertEquals(false, ThrottledIntegrationRunner.integrationInvoked,
            'Execution should skip when too many PullQueueable jobs are running.');

        resetOverrides();
    }

    @IsTest
    static void testSkipsWhenCooldownNotElapsed() {
        ThrottledIntegrationRunner.runningJobsOverride = 0;
        ThrottledIntegrationRunner.lastRunOverride = Datetime.now().addSeconds(-10);
        ThrottledIntegrationRunner.integrationInvoked = false;

        ThrottledIntegrationRunner runner = new ThrottledIntegrationRunner('EndpointB', 1, 3, 60, false);

        Test.startTest();
        runner.execute(null);
        Test.stopTest();

        System.assertEquals(false, ThrottledIntegrationRunner.integrationInvoked,
            'Execution should skip when cooldown has not elapsed.');

        resetOverrides();
    }

    @IsTest
    static void testRunsWhenAllowed() {
        ThrottledIntegrationRunner.runningJobsOverride = 0;
        ThrottledIntegrationRunner.lastRunOverride = Datetime.now().addSeconds(-120);
        ThrottledIntegrationRunner.integrationInvoked = false;
        ThrottledIntegrationRunner.integrationStarterMock = new IntegrationStarterMock();

        ThrottledIntegrationRunner runner = new ThrottledIntegrationRunner('EndpointC', 1, 3, 60, true);

        Test.startTest();
        runner.execute(null);
        Test.stopTest();

        System.assertEquals(true, ThrottledIntegrationRunner.integrationInvoked,
            'Execution should proceed when limits allow.');

        resetOverrides();
    }

    @IsTest
    static void testExecuteSkipsWhenEndpointMissing() {
        ThrottledIntegrationRunner.integrationInvoked = false;
        ThrottledIntegrationRunner runner = new ThrottledIntegrationRunner(null, 1, 3, 60, true);

        Test.startTest();
        runner.execute(null);
        Test.stopTest();

        System.assertEquals(false, ThrottledIntegrationRunner.integrationInvoked,
            'Execution should skip when no endpoint name is provided.');

        resetOverrides();
    }

    @IsTest
    static void testScheduleRegistersCronTrigger() {
        resetOverrides();
        String jobName = 'Throttled Runner Test Job';
        String cronExpr = '0 0 0 1 1 ?';

        Test.startTest();
        ThrottledIntegrationRunner.schedule(jobName, cronExpr, 'EndpointSchedule');
        Test.stopTest();

        CronTrigger ct = [
            SELECT CronJobDetail.Name, State
            FROM CronTrigger
            WHERE CronJobDetail.Name = :jobName
            LIMIT 1
        ];
        System.assertEquals(jobName, ct.CronJobDetail.Name, 'Scheduled job should exist.');
        System.assertEquals('WAITING', ct.State, 'Scheduled job should be waiting.');
    }

    private static void resetOverrides() {
        ThrottledIntegrationRunner.runningJobsOverride = null;
        ThrottledIntegrationRunner.lastRunOverride = null;
        ThrottledIntegrationRunner.integrationInvoked = false;
        ThrottledIntegrationRunner.integrationStarterMock = null;
    }

    private class IntegrationStarterMock implements ThrottledIntegrationRunner.IntegrationStarter {
        public void start(String endpointName, Integer syncOrder) {
            System.assertEquals('EndpointC', endpointName, 'Endpoint should match the runner configuration.');
            System.assertEquals(1, syncOrder, 'Sync order should match the runner configuration.');
        }
    }
}
