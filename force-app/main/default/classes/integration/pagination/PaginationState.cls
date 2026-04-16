/**
 * @description Represents pagination state that can be stored and retrieved
 * Extensible to support custom pagination implementations
 */
public virtual class PaginationState {
    
    private Integer offset;
    private Integer pageSize;
    private Map<String, Object> customData;
    
    /**
     * @description Constructor for basic pagination state
     * @param offset Current offset in the result set
     * @param pageSize Number of records per page
     */
    public PaginationState(Integer offset, Integer pageSize) {
        this.offset = offset;
        this.pageSize = pageSize;
        this.customData = new Map<String, Object>();
    }
    
    /**
     * @description Constructor with custom state data
     * @param offset Current offset in the result set
     * @param pageSize Number of records per page
     * @param customData Additional custom state data
     */
    public PaginationState(Integer offset, Integer pageSize, Map<String, Object> customData) {
        this(offset, pageSize);
        if (customData != null) {
            this.customData = customData;
        }
    }
    
    /**
     * @description Get the current offset
     * @return Integer offset value
     */
    public Integer getOffset() {
        return this.offset;
    }
    
    /**
     * @description Get the page size
     * @return Integer page size value
     */
    public Integer getPageSize() {
        return this.pageSize;
    }
    
    /**
     * @description Store custom state data
     * @param key Key for the custom data
     * @param value Value to store
     */
    public void setCustomData(String key, Object value) {
        this.customData.put(key, value);
    }
    
    /**
     * @description Retrieve custom state data
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
     * @return Map<String, Object> All custom state data
     */
    public Map<String, Object> getAllCustomData() {
        return this.customData.clone();
    }
    
    /**
     * @description Convert state to JSON string
     * Can be overridden to handle custom serialization
     * @return String JSON representation of state
     */
    public virtual String toJson() {
        Map<String, Object> stateMap = new Map<String, Object>{
            'offset' => this.offset,
            'pageSize' => this.pageSize,
            'customData' => this.customData
        };
        return JSON.serialize(stateMap);
    }
    
    /**
     * @description Create state from JSON string
     * Can be overridden to handle custom deserialization
     * @param jsonStr JSON string representing state
     * @return PaginationState New state instance
     */
    public static PaginationState fromJson(String jsonStr) {
        Map<String, Object> stateMap = (Map<String, Object>)JSON.deserializeUntyped(jsonStr);
        Integer offset = (Integer)stateMap.get('offset');
        Integer pageSize = (Integer)stateMap.get('pageSize');
        Map<String, Object> customData = stateMap.containsKey('customData') ? 
            (Map<String, Object>)stateMap.get('customData') : 
            new Map<String, Object>();
        
        return new PaginationState(offset, pageSize, customData);
    }
    
    /**
     * @description Create a copy of this state
     * Can be overridden to handle custom state copying
     * @return PaginationState New copy of the state
     */
    public virtual PaginationState copy() {
        return new PaginationState(
            this.offset,
            this.pageSize,
            this.customData.clone()
        );
    }
}