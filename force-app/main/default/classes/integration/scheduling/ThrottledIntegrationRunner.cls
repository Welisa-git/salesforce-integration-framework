public without sharing class ThrottledIntegrationRunner implements Schedulable {
    private static final Integer DEFAULT_MAX_CONCURRENT = 3;
    private static final Integer DEFAULT_COOLDOWN_SECONDS = 60;

    private final String endpointName;
    private final Integer syncOrder;
    private final Integer maxConcurrent;
    private final Integer coolDownSeconds;
    private final Boolean invokeIntegration;

    @TestVisible static Integer runningJobsOverride;
    @TestVisible static Datetime lastRunOverride;
    @TestVisible static Boolean integrationInvoked = false;
    @TestVisible static IntegrationStarter integrationStarterMock;

    public ThrottledIntegrationRunner() {
        this(null);
    }

    public ThrottledIntegrationRunner(String endpointName) {
        this(endpointName, 1, DEFAULT_MAX_CONCURRENT, DEFAULT_COOLDOWN_SECONDS, true);
    }

    public ThrottledIntegrationRunner(String endpointName, Integer syncOrder) {
        this(endpointName, syncOrder, DEFAULT_MAX_CONCURRENT, DEFAULT_COOLDOWN_SECONDS, true);
    }

    public ThrottledIntegrationRunner(String endpointName, Integer syncOrder, Integer maxConcurrent, Integer coolDownSeconds, Boolean invokeIntegration) {
        this.endpointName = endpointName;
        this.syncOrder = (syncOrder == null || syncOrder <= 0) ? 1 : syncOrder;
        this.maxConcurrent = (maxConcurrent == null || maxConcurrent <= 0) ? DEFAULT_MAX_CONCURRENT : maxConcurrent;
        this.coolDownSeconds = (coolDownSeconds == null || coolDownSeconds < 0) ? DEFAULT_COOLDOWN_SECONDS : coolDownSeconds;
        this.invokeIntegration = (invokeIntegration == null) ? true : invokeIntegration;
    }

    public void execute(SchedulableContext context) {
        if (String.isBlank(endpointName)) {
            Logger.error('ThrottledIntegrationRunner invoked with no endpoint name.');
            return;
        }

        if (hasInFlightPullQueueables()) {
            Logger.warn('ThrottledIntegrationRunner skipped for endpoint ' + endpointName + ' because PullQueueable jobs are still running.');
            return;
        }

        if (!coolDownElapsed()) {
            Logger.warn('ThrottledIntegrationRunner skipped for endpoint ' + endpointName + ' because cooldown has not elapsed.');
            return;
        }

        if (!invokeIntegration) {
            integrationInvoked = true;
            return;
        }

        startIntegration(endpointName, syncOrder);
        integrationInvoked = true;
    }

    @TestVisible
    Boolean hasInFlightPullQueueables() {
        Integer running;
        if (runningJobsOverride != null) {
            running = runningJobsOverride;
        } else {
            String countQuery = 'SELECT COUNT() FROM AsyncApexJob WHERE JobType = \'Queueable\' ' +
                'AND ApexClass.Name = \'PullQueueable\' ' +
                'AND Status IN (\'Processing\', \'Queued\')';
            running = Database.countQuery(countQuery);
        }
        return running >= maxConcurrent;
    }

    @TestVisible
    Boolean coolDownElapsed() {
        Datetime lastRun = (lastRunOverride != null)
            ? lastRunOverride
            : AbstractPullQueueable.getLastRunTime(endpointName);
        if (lastRun == null) return true;
        Long elapsedMs = Datetime.now().getTime() - lastRun.getTime();
        return elapsedMs >= coolDownSeconds * 1000L;
    }

    public static void schedule(String jobName, String cronExpression, String endpointName) {
        System.schedule(jobName, cronExpression, new ThrottledIntegrationRunner(endpointName));
    }

    private static void startIntegration(String endpointName, Integer syncOrder) {
        if (Test.isRunningTest() && integrationStarterMock != null) {
            integrationStarterMock.start(endpointName, syncOrder);
        } else {
            IntegrationSchedulable.startIntegrationForEndpointAndOrder(endpointName, syncOrder);
        }
    }

    public interface IntegrationStarter {
        void start(String endpointName, Integer syncOrder);
    }
}