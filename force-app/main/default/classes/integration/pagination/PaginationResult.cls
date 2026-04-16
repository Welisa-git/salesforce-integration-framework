/**
 * @description Represents the result of a paginated operation
 * Extensible to support custom pagination implementations
 */
public virtual class PaginationResult {
    
    private List<Object> records;
    private List<SObject> sObjects;
    private PaginationState nextState;
    private Boolean hasMoreData;
    private String errorMessage;
    private Map<String, Object> customData;
    
    /**
     * @description Constructor for successful result with raw records
     * @param records List of records from this page
     * @param nextState State for the next page
     * @param hasMoreData Whether more records exist
     */
    public PaginationResult(List<Object> records, PaginationState nextState, Boolean hasMoreData) {
        this.records = records;
        this.sObjects = null;
        this.nextState = nextState;
        this.hasMoreData = hasMoreData;
        this.errorMessage = null;
        this.customData = new Map<String, Object>();
    }
    
    /**
     * @description Constructor for successful result with SObjects
     * @param sObjects List of SObjects from this page
     * @param nextState State for the next page
     * @param hasMoreData Whether more records exist
     */
    public PaginationResult(List<SObject> sObjects, PaginationState nextState, Boolean hasMoreData) {
        this.records = null;
        this.sObjects = sObjects;
        this.nextState = nextState;
        this.hasMoreData = hasMoreData;
        this.errorMessage = null;
        this.customData = new Map<String, Object>();
    }
    
    /**
     * @description Constructor for error result
     * @param errorMessage Error message describing what went wrong
     */
    public PaginationResult(String errorMessage) {
        this.records = new List<Object>();
        this.sObjects = new List<SObject>();
        this.nextState = null;
        this.hasMoreData = false;
        this.errorMessage = errorMessage;
        this.customData = new Map<String, Object>();
    }
    
    /**
     * @description Get the raw records from this page
     * @return List<Object> The records
     */
    public List<Object> getRecords() {
        return this.records;
    }
    
    /**
     * @description Get the SObject records from this page
     * @return List<SObject> The SObject records
     */
    public List<SObject> getSObjects() {
        return this.sObjects;
    }
    
    /**
     * @description Get the state for the next page
     * @return PaginationState Next state or null if no more pages
     */
    public PaginationState getNextState() {
        return this.nextState;
    }
    
    /**
     * @description Check if more records exist
     * @return Boolean true if more records exist
     */
    public Boolean getHasMoreData() {
        return this.hasMoreData;
    }
    
    /**
     * @description Get any error message
     * @return String Error message or null if no error
     */
    public String getErrorMessage() {
        return this.errorMessage;
    }
    
    /**
     * @description Check if the operation was successful
     * @return Boolean true if no error occurred
     */
    public Boolean isSuccess() {
        return String.isBlank(this.errorMessage);
    }
    
    /**
     * @description Store custom result data
     * @param key Key for the custom data
     * @param value Value to store
     */
    public void setCustomData(String key, Object value) {
        this.customData.put(key, value);
    }
    
    /**
     * @description Retrieve custom result data
     * @param key Key for the custom data
     * @return Object The stored value or null if not found
     */
    public Object getCustomData(String key) {
        return this.customData.get(key);
    }
    
    /**
     * @description Check if custom data exists
     * @param key Key to check
     * @return Boolean true if the key exists
     */
    public Boolean hasCustomData(String key) {
        return this.customData.containsKey(key);
    }
    
    /**
     * @description Get all custom data
     * @return Map<String, Object> All custom result data
     */
    public Map<String, Object> getAllCustomData() {
        return this.customData.clone();
    }
    
    /**
     * @description Create a success result with raw records
     * @param records The records from this page
     * @param nextState State for the next page
     * @param hasMoreData Whether more records exist
     * @return PaginationResult A success result
     */
    public static PaginationResult createSuccess(List<Object> records, 
                                               PaginationState nextState, 
                                               Boolean hasMoreData) {
        return new PaginationResult(records, nextState, hasMoreData);
    }
    
    /**
     * @description Create a success result with SObjects
     * @param sObjects The SObject records from this page
     * @param nextState State for the next page
     * @param hasMoreData Whether more records exist
     * @return PaginationResult A success result
     */
    public static PaginationResult createSuccess(List<SObject> sObjects, 
                                               PaginationState nextState, 
                                               Boolean hasMoreData) {
        return new PaginationResult(sObjects, nextState, hasMoreData);
    }
    
    /**
     * @description Create an error result
     * @param errorMessage Message describing what went wrong
     * @return PaginationResult An error result
     */
    public static PaginationResult createError(String errorMessage) {
        return new PaginationResult(errorMessage);
    }
}