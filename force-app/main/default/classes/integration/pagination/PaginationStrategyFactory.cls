/**
 * @description Factory for creating pagination strategies
 * Supports both built-in and custom strategy implementations
 */
public virtual class PaginationStrategyFactory {
    
    private static Map<String, Type> strategyTypes = new Map<String, Type>();
    
    private static DateTime lastRunTime;
    
    private static Boolean isInitialized = false;
    
    // For test mocking
    @TestVisible private static PaginationStrategy mockStrategyForTest;
    
    /**
     * @description Initialize the factory and register built-in strategies
     */
    private static void initialize() {
        if (isInitialized) return;
        
        registerBuiltInStrategies();
        isInitialized = true;
    }

    @TestVisible
    private static void registerBuiltInStrategies() {
        strategyTypes.put('offset', CompanoOffsetPaginationStrategy.class);
        strategyTypes.put('graphql', GraphQLCursorPaginationStrategy.class);
    }
    
    /**
     * @description Register a custom pagination strategy
     * @param name Name to identify the strategy
     * @param strategyType Apex Type of the strategy class
     */
    public static void registerStrategy(String name, Type strategyType) {
        if (String.isBlank(name)) {
            throw new PaginationException('Strategy name cannot be blank');
        }
        if (strategyType == null) {
            throw new PaginationException('Strategy type cannot be null');
        }
        
        // Store the strategy type
        strategyTypes.put(name.toLowerCase(), strategyType);
    }
    
    /**
     * @description Create a pagination strategy instance
     * @param type Name of the strategy to create
     * @return PaginationStrategy The created strategy instance (uninitialized)
     */
    public static PaginationStrategy createStrategy(String type) {
        initialize();
        
        Type strategyType = strategyTypes.get(type.toLowerCase());
        if (strategyType == null) {
            throw new PaginationException('Unknown pagination strategy: ' + type);
        }
        
        // Create strategy instance
        try {
            
            // For custom types, try default constructor
            Object instance = strategyType.newInstance();
            if (instance instanceof PaginationStrategy) {
                return (PaginationStrategy)instance;
            }
            throw new PaginationException('Type must extend PaginationStrategy: ' + strategyType.getName());
        } catch (Exception e) {
            throw new PaginationException('Failed to create strategy: ' + e.getMessage());
        }
    }
    
    /**
     * @description Set the last run time for incremental sync strategies
     * @param lastRunTime The last successful run time
     */
    public static void setLastRunTime(DateTime lastRunTime) {
        PaginationStrategyFactory.lastRunTime = lastRunTime;
    }

    /**
     * @description Create a pagination strategy from endpoint configuration
     * @param endpoint The endpoint configuration
     * @return PaginationStrategy The created strategy instance
     */
    public static PaginationStrategy createStrategy(Integration_Endpoint__mdt endpoint) {
        initialize();
        
        // Return mock strategy if in test context and mock is set
        if (Test.isRunningTest() && mockStrategyForTest != null) {
            System.debug('PaginationStrategyFactory returning mock strategy');
            return mockStrategyForTest;
        }
        
        if (endpoint == null) {
            throw new PaginationException('Endpoint cannot be null');
        }

        String typeName = endpoint.Pagination_Type__c;
        String customClass = endpoint.Pagination_Config__c;

        // Fetch the mapping configuration - needed for page size and initialization
        List<Integration_Mapping__mdt> mappings = IntegrationMappingCache.getMappingsForEndpoint(endpoint.DeveloperName);
        if (mappings.isEmpty()) {
            throw new PaginationException('No active mappings found for endpoint: ' + endpoint.DeveloperName);
        }

        // Using the first active mapping for initialization context
        Integration_Mapping__mdt mapping = mappings[0];

        PaginationStrategy strategyInstance;
        try {
            Type strategyType;
            if (String.isNotBlank(customClass)) {
                strategyType = System.Type.forName(customClass);
                if (strategyType == null) {
                    throw new PaginationException('Custom strategy class not found: ' + customClass);
                }
            } else if (String.isNotBlank(typeName)) {
                strategyType = strategyTypes.get(typeName.toLowerCase());
                if (strategyType == null) {
                     throw new PaginationException('Unknown pagination strategy type: ' + typeName);
                }
            } else {
                 throw new PaginationException('Pagination type or custom class must be specified on endpoint: ' + endpoint.DeveloperName);
            }

            Object instance = strategyType.newInstance();
            if (instance instanceof PaginationStrategy) {
                strategyInstance = (PaginationStrategy)instance;
            } else {
                throw new PaginationException('Type must extend PaginationStrategy: ' + strategyType.getName());
            }

        } catch (Exception e) {
            throw new PaginationException('Failed to create strategy instance: ' + e.getMessage());
        }

        // Initialize the strategy with endpoint, mapping, and last run time
        strategyInstance.initialize(endpoint, mapping, lastRunTime);
        return strategyInstance;
    }
    
    /**
     * @description Set a mock strategy for testing
     * @param mockStrategy The mock strategy instance to return in test context
     */
    @TestVisible
    public static void setMockStrategy(PaginationStrategy mockStrategy) {
        if (!Test.isRunningTest()) {
            throw new PaginationException('setMockStrategy can only be called in test context');
        }
        mockStrategyForTest = mockStrategy;
    }
    
    /**
     * @description Clear the mock strategy
     */
    @TestVisible
    public static void clearMockStrategy() {
        mockStrategyForTest = null;
    }
    
    /**
     * @description Get all registered strategy names
     * @return Set<String> Names of all registered strategies
     */
    public static Set<String> getRegisteredStrategyNames() {
        return strategyTypes.keySet();
    }
    
    /**
     * @description Check if a strategy type is registered
     * @param name Name of the strategy to check
     * @return Boolean true if the strategy is registered
     */
    public static Boolean isStrategyRegistered(String name) {
        return !String.isBlank(name) && strategyTypes.containsKey(name.toLowerCase());
    }
    
    /**
     * @description Custom exception class for pagination errors
     */
    public class PaginationException extends Exception {}
}
