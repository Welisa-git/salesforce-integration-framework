public class IntegrationSchedulable implements Schedulable {
    
    private String endpointName;
    
    public IntegrationSchedulable(String endpointName) {
        // Input validation
        if (String.isBlank(endpointName)) {
            throw new IllegalArgumentException('Endpoint name cannot be null or empty');
        }
        this.endpointName = endpointName;
    }
    
    public void execute(SchedulableContext sc) {
        Logger.info('Starting scheduled integration for endpoint: ' + this.endpointName);
        
        // Validate context (defensive)
        if (sc == null) {
            Logger.warn('Schedulable context is null in IntegrationSchedulable.execute');
        }
        
        // Validate stored endpoint name
        if (String.isBlank(this.endpointName)) {
            Logger.error('Cannot execute integration: endpoint name is blank');
            return;
        }
        
        startIntegrationForEndpointAndOrder(this.endpointName, 1);
    }
    
    /**
     * @description Start integration for a specific mapping of an endpoint
     * @param endpointName The developer name of the Integration_Endpoint__mdt
     * @param syncOrder The sync order to process
     */
    public static void startIntegrationForEndpointAndOrder(String endpointName, Integer syncOrder) {
        // Input validation
        if (String.isBlank(endpointName)) {
            Logger.error('Cannot start integration: endpoint name is blank');
            return;
        }
        
        if (syncOrder == null || syncOrder <= 0) {
            Logger.error('Invalid sync order: ' + syncOrder);
            return;
        }
        
        try {
            Integration_Mapping__mdt mapping = IntegrationMappingCache.getMappingByEndpointAndOrder(endpointName, syncOrder);
            
            if (mapping == null) {
                Logger.error('No mapping found for endpoint ' + endpointName + ' with sync order ' + syncOrder);
                return;
            }
            
            DateTime lastRunTime = AbstractPullQueueable.getLastRunTime(endpointName);
            String lastRunDisplay = lastRunTime != null ? lastRunTime.format() : 'Never run';
            
            // More visible logging of integration start
            Logger.info('=== STARTING INTEGRATION ===');
            Logger.info('Endpoint: ' + endpointName);
            Logger.info('Mapping: ' + mapping.DeveloperName);
            Logger.info('Target Object: ' + (mapping.Target_Object__c != null ? mapping.Target_Object__c : 'Unknown'));
            Logger.info('Sync Order: ' + (mapping.Sync_Order__c != null ? String.valueOf(mapping.Sync_Order__c) : 'Unknown'));
            Logger.info('Last Run Time: ' + lastRunDisplay);
            Logger.info('========================');
            
            System.enqueueJob(new PullQueueable(
                endpointName,
                mapping.DeveloperName,
                endpointName,
                lastRunTime,
                null,
                syncOrder
            ));
        } catch (Exception e) {
            Logger.error('Failed to start integration: ' + e.getMessage() + '\n' + e.getStackTraceString());
            throw e;
        }
    }
    
    /**
     * @description Schedule integration for an endpoint
     * @param endpointName The developer name of the Integration_Endpoint__mdt
     * @param cronExp The cron expression for scheduling
     * @return String The scheduled job ID
     */
    public static String scheduleIntegration(String endpointName, String cronExp) {
        // Input validation
        if (String.isBlank(endpointName)) {
            throw new IllegalArgumentException('Endpoint name cannot be null or empty');
        }
        
        if (String.isBlank(cronExp)) {
            throw new IllegalArgumentException('Cron expression cannot be null or empty');
        }
        
        try {
            IntegrationSchedulable scheduler = new IntegrationSchedulable(endpointName);
            String jobName = 'Integration_' + endpointName + '_' + System.now().getTime();
            
            return System.schedule(jobName, cronExp, scheduler);
        } catch (Exception e) {
            Logger.error('Failed to schedule integration: ' + e.getMessage() + '\n' + e.getStackTraceString());
            throw e;
        }
    }
}