/**
 * @description Wrapper class for integration operation results
 */
public class IntegrationResult {
    @AuraEnabled public Boolean isSuccess { get; private set; }
    @AuraEnabled public String message { get; private set; }
    @AuraEnabled public List<Id> processedRecords { get; private set; }
    @AuraEnabled public String errorDetails { get; private set; }
    public Map<String, Object> additionalDetails { get; private set; }
    public Queueable nextJob { get; set; }
    
    public IntegrationResult() {
        this.isSuccess = false;
        this.processedRecords = new List<Id>();
        this.additionalDetails = new Map<String, Object>();
    }
    
    /**
     * @description Creates a success result
     * @param message Success message
     * @return IntegrationResult
     */
    public static IntegrationResult createSuccess(String message) {
        IntegrationResult result = new IntegrationResult();
        result.isSuccess = true;
        result.message = message;
        return result;
    }
    
    /**
     * @description Creates an error result
     * @param message Error message
     * @param errorDetails Detailed error information
     * @return IntegrationResult
     */
    public static IntegrationResult createError(String message, String errorDetails) {
        IntegrationResult result = new IntegrationResult();
        result.isSuccess = false;
        result.message = message;
        result.errorDetails = errorDetails;
        return result;
    }
    
    /**
     * @description Adds processed record IDs to the result
     * @param recordIds List of processed record IDs
     * @return IntegrationResult
     */
    public IntegrationResult withProcessedRecords(List<Id> recordIds) {
        this.processedRecords.addAll(recordIds);
        return this;
    }
    
    /**
     * @description Adds additional details to the result
     * @param key Detail key
     * @param value Detail value
     * @return IntegrationResult
     */
    public IntegrationResult withAdditionalDetail(String key, Object value) {
        this.additionalDetails.put(key, value);
        return this;
    }
}