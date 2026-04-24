/**
 * @description Calculates whether a mapping should execute based on its frequency settings
 * Supports Hourly, Daily, Weekly, and custom minute intervals
 * @Author: R. Groot Date: 21-04-2026
 */
public class IntegrationFrequencyCalculator {
    
    // Frequency type constants
    public static final String FREQUENCY_HOURLY = 'Hourly';
    public static final String FREQUENCY_DAILY = 'Daily';
    public static final String FREQUENCY_WEEKLY = 'Weekly';
    public static final String FREQUENCY_CUSTOM_MINUTES = 'Custom Minutes';
    
    /**
     * @description Determines if a mapping should execute now based on frequency and last run time
     * @param frequencyType The frequency type (Hourly, Daily, Weekly, Custom Minutes)
     * @param frequencyValue The numeric value (hours for Hourly, days for Daily/Weekly, minutes for Custom Minutes)
     * @param lastRunTime The last successful execution time (null if never run)
     * @return Boolean True if the mapping should execute now
     */
    public static Boolean shouldExecuteNow(
        String frequencyType,
        Integer frequencyValue,
        DateTime lastRunTime
    ) {
        // Validate inputs
        if (String.isBlank(frequencyType) || frequencyValue == null || frequencyValue <= 0) {
            Logger.error('Invalid frequency parameters: type=' + frequencyType + ', value=' + frequencyValue);
            return false;
        }
        
        // Always execute if never run before
        if (lastRunTime == null) {
            return true;
        }
        
        DateTime nextExecutionTime = getNextExecutionTime(frequencyType, frequencyValue, lastRunTime);
        DateTime now = DateTime.now();
        
        boolean shouldRun = now >= nextExecutionTime;
        
        Logger.debug(
            'Frequency check - Type: ' + frequencyType + 
            ', Value: ' + frequencyValue + 
            ', Last Run: ' + lastRunTime + 
            ', Next Run: ' + nextExecutionTime + 
            ', Now: ' + now + 
            ', Should Run: ' + shouldRun
        );
        
        return shouldRun;
    }
    
    /**
     * @description Calculates the next execution time based on frequency and last run time
     * @param frequencyType The frequency type (Hourly, Daily, Weekly, Custom Minutes)
     * @param frequencyValue The numeric value (hours for Hourly, days for Daily/Weekly, minutes for Custom Minutes)
     * @param lastRunTime The last successful execution time
     * @return DateTime The calculated next execution time
     */
    public static DateTime getNextExecutionTime(
        String frequencyType,
        Integer frequencyValue,
        DateTime lastRunTime
    ) {
        if (lastRunTime == null || String.isBlank(frequencyType) || frequencyValue == null) {
            return DateTime.now();
        }
        
        DateTime nextTime = lastRunTime;
        String normalizedType = String.isBlank(frequencyType) ? '' : frequencyType.toLowerCase();

        switch on normalizedType {
            when 'hourly' {
                nextTime = lastRunTime.addHours(frequencyValue);
            }
            when 'daily' {
                nextTime = lastRunTime.addDays(frequencyValue);
            }
            when 'weekly' {
                nextTime = lastRunTime.addDays(frequencyValue * 7);
            }
            when 'custom minutes' {
                nextTime = lastRunTime.addMinutes(frequencyValue);
            }
            when else {
                Logger.warn('Unknown frequency type: ' + frequencyType + '. Defaulting to Daily.');
                nextTime = lastRunTime.addDays(1);
            }
        }
        
        return nextTime;
    }
    
    /**
     * @description Updates the execution state in the custom setting with next scheduled time
     * @param mappingName The name of the mapping
     * @param frequencyType The frequency type
     * @param frequencyValue The frequency value
     * @param lastRunTime The last run time
     */
    public static void updateExecutionState(
        String mappingName,
        String frequencyType,
        Integer frequencyValue,
        DateTime lastRunTime
    ) {
        if (String.isBlank(mappingName)) {
            Logger.error('Cannot update execution state: mapping name is blank');
            return;
        }
        
        try {
            List<IntegrationExecutionState__c> existing = [
                SELECT Id, Name, Last_Run_Date__c, Next_Scheduled_Time__c, Last_Status__c
                FROM IntegrationExecutionState__c WHERE Name = :mappingName LIMIT 1
            ];
            IntegrationExecutionState__c state = existing.isEmpty()
                ? new IntegrationExecutionState__c(Name = mappingName)
                : existing[0];

            state.Last_Run_Date__c = lastRunTime != null ? lastRunTime : DateTime.now();
            state.Next_Scheduled_Time__c = getNextExecutionTime(frequencyType, frequencyValue, state.Last_Run_Date__c);
            state.Last_Status__c = 'Success';

            upsert state Name;
            
            Logger.debug(
                'Updated execution state for ' + mappingName + 
                ' - Next scheduled: ' + state.Next_Scheduled_Time__c
            );
        } catch (Exception e) {
            Logger.error('Failed to update execution state for ' + mappingName + ': ' + e.getMessage());
        }
    }
    
    /**
     * @description Records a failed execution in the execution state
     * @param mappingName The name of the mapping
     * @param errorMessage The error message from the failed execution
     */
    public static void recordFailedExecution(String mappingName, String errorMessage) {
        if (String.isBlank(mappingName)) {
            return;
        }
        
        try {
            List<IntegrationExecutionState__c> existing = [
                SELECT Id, Name, Last_Status__c FROM IntegrationExecutionState__c WHERE Name = :mappingName LIMIT 1
            ];
            IntegrationExecutionState__c state = existing.isEmpty()
                ? new IntegrationExecutionState__c(Name = mappingName)
                : existing[0];

            state.Last_Status__c = 'Failed';
            upsert state Name;
            
            Logger.error('Recorded failed execution for ' + mappingName + ': ' + errorMessage);
        } catch (Exception e) {
            Logger.error('Failed to record execution failure for ' + mappingName + ': ' + e.getMessage());
        }
    }
}
