/**
 * @description Universal scheduler for managing integration frequency across all mappings
 * Runs periodically (every 5-15 minutes) and checks each mapping against its frequency settings
 * Enqueues PullQueueable jobs only when the execution frequency is due
 * @Author: R. Groot Date: 21-04-2026
 */
public class UniversalIntegrationScheduler implements Schedulable {
    
    private static final Integer DEFAULT_CHECK_INTERVAL = 5; // minutes
    
    /**
     * @description Execute method called by Salesforce scheduler
     * Iterates through all active Integration_Mapping__mdt records and checks frequency
     * @param sc The SchedulableContext provided by Salesforce
     */
    public void execute(SchedulableContext sc) {
        Logger.info('=== UNIVERSAL INTEGRATION SCHEDULER STARTING ===');
        
        try {
            // Get all active endpoints with their mappings
            List<Integration_Endpoint__mdt> endpoints = IntegrationMappingCache.getAllActiveEndpoints();
            
            if (endpoints == null || endpoints.isEmpty()) {
                Logger.info('No active endpoints found');
                return;
            }
            
            Integer jobsEnqueued = 0;
            
            // Check each endpoint and its mappings
            for (Integration_Endpoint__mdt endpoint : endpoints) {
                if (!endpoint.Active__c) {
                    continue;
                }
                
                List<Integration_Mapping__mdt> mappings = IntegrationMappingCache.getMappingsForEndpoint(endpoint.DeveloperName);
                
                if (mappings == null || mappings.isEmpty()) {
                    continue;
                }
                
                // Check each mapping for frequency and enqueue if needed
                for (Integration_Mapping__mdt mapping : mappings) {
                    if (mapping.Active__c && shouldExecuteMapping(mapping)) {
                        enqueueMapping(mapping, endpoint.DeveloperName);
                        jobsEnqueued++;
                    }
                }
            }
            
            Logger.info('Universal Integration Scheduler completed - Enqueued ' + jobsEnqueued + ' jobs');
            
        } catch (Exception e) {
            Logger.error('Error in UniversalIntegrationScheduler: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
    }
    
    /**
     * @description Determines if a mapping should execute based on its frequency settings
     * @param mapping The Integration_Mapping__mdt record to check
     * @return Boolean True if the mapping should execute now
     */
    private static Boolean shouldExecuteMapping(Integration_Mapping__mdt mapping) {
        // Use default values if frequency fields are not set
        String frequencyType = String.isBlank(mapping.Execution_Frequency_Type__c) 
            ? IntegrationFrequencyCalculator.FREQUENCY_DAILY 
            : mapping.Execution_Frequency_Type__c;
        
        Integer frequencyValue = mapping.Execution_Frequency_Value__c != null 
            ? mapping.Execution_Frequency_Value__c.intValue() 
            : 1;
        
        // Get last run time from execution state
        DateTime lastRunTime = getLastExecutionTime(mapping.DeveloperName);
        
        return IntegrationFrequencyCalculator.shouldExecuteNow(frequencyType, frequencyValue, lastRunTime);
    }
    
    /**
     * @description Gets the last execution time for a mapping from the execution state
     * @param mappingName The DeveloperName of the mapping
     * @return DateTime The last run time or null if never run
     */
    private static DateTime getLastExecutionTime(String mappingName) {
        try {
            IntegrationExecutionState__c state = IntegrationExecutionState__c.getInstance(mappingName);
            return state?.Last_Run_Date__c;
        } catch (Exception e) {
            Logger.debug('Could not retrieve execution state for ' + mappingName + ': ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * @description Enqueues a PullQueueable job for the specified mapping
     * @param mapping The Integration_Mapping__mdt record to execute
     * @param endpointName The endpoint name for the mapping
     */
    private static void enqueueMapping(Integration_Mapping__mdt mapping, String endpointName) {
        try {
            DateTime lastRunTime = getLastExecutionTime(mapping.DeveloperName);
            
            PullQueueable queueableJob = new PullQueueable(
                endpointName,
                mapping.DeveloperName,
                endpointName,
                lastRunTime,
                null,
                mapping.Sync_Order__c != null ? mapping.Sync_Order__c.intValue() : 1
            );
            
            System.enqueueJob(queueableJob);
            
            Logger.info(
                'Enqueued PullQueueable for mapping: ' + mapping.DeveloperName + 
                ' (Endpoint: ' + endpointName + 
                ', Frequency: ' + mapping.Execution_Frequency_Type__c + ')'
            );
            
        } catch (Exception e) {
            Logger.error('Failed to enqueue mapping ' + mapping.DeveloperName + ': ' + e.getMessage());
        }
    }
    
    /**
     * @description Schedules the UniversalIntegrationScheduler to run at regular intervals
     * @param jobName The name for the scheduled job
     * @param intervalMinutes The interval in minutes (e.g., 5, 15, 30)
     * @return String The job ID of the scheduled job
     */
    public static String scheduleUniversalSchedler(String jobName, Integer intervalMinutes) {
        if (String.isBlank(jobName)) {
            throw new IllegalArgumentException('Job name cannot be blank');
        }
        
        if (intervalMinutes == null || intervalMinutes <= 0 || intervalMinutes > 59) {
            throw new IllegalArgumentException('Interval must be between 1 and 59 minutes');
        }
        
        try {
            // Build cron expression: every N minutes
            // Format: 0 0/N * * * ? (every N minutes)
            String cronExp = buildCronExpression(intervalMinutes);
            
            UniversalIntegrationScheduler scheduler = new UniversalIntegrationScheduler();
            String jobId = System.schedule(jobName, cronExp, scheduler);
            
            Logger.info('Scheduled UniversalIntegrationScheduler with job ID: ' + jobId + ' (Interval: ' + intervalMinutes + ' minutes)');
            
            return jobId;
        } catch (Exception e) {
            Logger.error('Failed to schedule UniversalIntegrationScheduler: ' + e.getMessage());
            throw e;
        }
    }
    
    /**
     * @description Builds a cron expression for the specified interval
     * Salesforce cron does not support minute-level intervals directly
     * For intervals < 60 minutes, we use a workaround with multiple scheduled jobs
     * @param intervalMinutes The interval in minutes
     * @return String A cron expression that approximates the interval
     */
    private static String buildCronExpression(Integer intervalMinutes) {
        // Note: Salesforce cron expressions have limitations for minute intervals
        // This creates an expression that runs at specific hours/minutes
        // For production, consider using a scheduled action or Flow Timer trigger instead
        
        if (intervalMinutes <= 5) {
            return '0 * * * * ?'; // Every minute (closest approximation)
        } else if (intervalMinutes <= 15) {
            return '0 0/15 * * * ?'; // Every 15 minutes
        } else if (intervalMinutes <= 30) {
            return '0 0/30 * * * ?'; // Every 30 minutes
        } else {
            return '0 0 * * * ?'; // Every hour (default fallback)
        }
    }
    
    /**
     * @description Helper method to get or create an integration execution state record
     * @param mappingName The mapping name
     * @return IntegrationExecutionState__c The execution state record
     */
    public static IntegrationExecutionState__c getOrCreateExecutionState(String mappingName) {
        if (String.isBlank(mappingName)) {
            return null;
        }
        try {
            IntegrationExecutionState__c state = IntegrationExecutionState__c.getInstance(mappingName);
            if (state == null) {
                state = new IntegrationExecutionState__c(Name = mappingName);
            }
            return state;
        } catch (Exception e) {
            Logger.error('Error getting execution state for ' + mappingName + ': ' + e.getMessage());
            return null;
        }
    }
}
