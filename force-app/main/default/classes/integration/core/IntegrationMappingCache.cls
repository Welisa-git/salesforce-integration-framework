public virtual class IntegrationMappingCache {
    private static Map<String, Map<Decimal, Integration_Mapping__mdt>> mappingCache = 
        new Map<String, Map<Decimal, Integration_Mapping__mdt>>();
    
    private static Map<String, Integration_Mapping__mdt> mappingByNameCache = 
        new Map<String, Integration_Mapping__mdt>();
        
    // --- Additions for Test Mocking ---
    @TestVisible private static Map<String, Integration_Mapping__mdt> mockMappingsByName = null;
    @TestVisible private static Map<String, Map<Decimal, Integration_Mapping__mdt>> mockMappingsByEndpoint = null;
    
    public static Integration_Mapping__mdt getMappingByEndpointAndOrder(String endpointName, Decimal syncOrder) {
        // Input validation
        if (String.isBlank(endpointName)) {
            Logger.error('Endpoint name cannot be null or empty');
            return null;
        }
        
        if (syncOrder == null) {
            Logger.error('Sync order cannot be null');
            return null;
        }
        
        if (!mappingCache.containsKey(endpointName)) {
            loadMappingsForEndpoint(endpointName);
        }
        
        // Null safety with defensive access
        Map<Decimal, Integration_Mapping__mdt> endpointMappings = mappingCache.get(endpointName);
        if (endpointMappings == null) {
            return null;
        }
        
        Integration_Mapping__mdt mapping = endpointMappings.get(syncOrder);
        if (mapping != null) {
            return mapping;
        }

        // Decimal map keys can differ by scale, e.g. 1 versus 1.0.
        for (Decimal cachedSyncOrder : endpointMappings.keySet()) {
            if (cachedSyncOrder != null && cachedSyncOrder == syncOrder) {
                return endpointMappings.get(cachedSyncOrder);
            }
        }

        return null;
    }
    
    public static Integration_Mapping__mdt getMappingByName(String mappingName) {
        // Input validation & Lowercase for consistency
        if (String.isBlank(mappingName)) {
            Logger.error('Mapping name cannot be null or empty');
            return null;
        }
        String lowerCaseName = mappingName.toLowerCase();
        
        // --- Check Mocks First in Test Context ---
        if (Test.isRunningTest() && mockMappingsByName != null && mockMappingsByName.containsKey(lowerCaseName)) {
            System.debug('IntegrationMappingCache: Returning mock mapping for ' + mappingName);
            return mockMappingsByName.get(lowerCaseName);
        }
        
        // --- Existing Cache/SOQL Logic ---
        if (!mappingByNameCache.containsKey(mappingName)) {
            loadMappingByName(mappingName);
        }
        
        return mappingByNameCache.get(mappingName);
    }
    
    public static List<Integration_Mapping__mdt> getMappingsForEndpoint(String endpointName) {
        // Input validation
        if (String.isBlank(endpointName)) {
            Logger.error('Endpoint name cannot be null or empty');
            return new List<Integration_Mapping__mdt>();
        }
        
        if (!mappingCache.containsKey(endpointName)) {
            loadMappingsForEndpoint(endpointName);
        }
        
        // Null safety with defensive return
        Map<Decimal, Integration_Mapping__mdt> endpointMappings = mappingCache.get(endpointName);
        return endpointMappings != null ? endpointMappings.values() : new List<Integration_Mapping__mdt>();
    }
    
    public static Decimal getMaxSyncOrderForEndpoint(String endpointName) {
        // Input validation
        if (String.isBlank(endpointName)) {
            Logger.error('Endpoint name cannot be null or empty');
            return 0;
        }
        
        if (!mappingCache.containsKey(endpointName)) {
            loadMappingsForEndpoint(endpointName);
        }
        
        // Null safety with defensive iteration
        Decimal maxOrder = 0;
        Map<Decimal, Integration_Mapping__mdt> endpointMappings = mappingCache.get(endpointName);
        
        if (endpointMappings != null) {
            for (Decimal syncOrder : endpointMappings.keySet()) {
                if (syncOrder > maxOrder) {
                    maxOrder = syncOrder;
                }
            }
        }
        
        return maxOrder;
    }
    
    /**
     * @description Clears the entire cache, forcing reload on next request
     */
    public static void clearCache() {
        // --- Clear mocks too when the main cache is cleared during tests ---
        if(Test.isRunningTest()) {
            clearMockMappings();
        }
        mappingCache.clear();
        mappingByNameCache.clear();
        Logger.debug('Integration mapping cache cleared');
    }
    
    /**
     * @description Clears cache for a specific endpoint
     * @param endpointName The endpoint name to clear from cache
     */
    public static void clearCacheForEndpoint(String endpointName) {
        if (String.isBlank(endpointName)) {
            return;
        }
        
        // Remove endpoint mappings
        mappingCache.remove(endpointName);
        
        // Remove mappings by name that belong to this endpoint
        Set<String> keysToRemove = new Set<String>();
        for (String mappingName : mappingByNameCache.keySet()) {
            Integration_Mapping__mdt mapping = mappingByNameCache.get(mappingName);
            if (mapping != null && mapping.Endpoint__r != null && 
                endpointName.equals(mapping.Endpoint__r.DeveloperName)) {
                keysToRemove.add(mappingName);
            }
        }
        
        for (String key : keysToRemove) {
            mappingByNameCache.remove(key);
        }
        
        Logger.debug('Cleared cache for endpoint: ' + endpointName);
    }
    
    /**
     * @description Refreshes cache for a specific endpoint
     * @param endpointName The endpoint name to refresh
     */
    public static void refreshEndpointCache(String endpointName) {
        if (String.isBlank(endpointName)) {
            return;
        }
        
        clearCacheForEndpoint(endpointName);
        loadMappingsForEndpoint(endpointName);
        Logger.debug('Refreshed cache for endpoint: ' + endpointName);
    }
    
    /**
     * @description Gets all active Integration_Endpoint__mdt records
     * Used by UniversalIntegrationScheduler to iterate through endpoints for frequency checking
     * @return List<Integration_Endpoint__mdt> List of all active endpoints
     */
    public static List<Integration_Endpoint__mdt> getAllActiveEndpoints() {
        try {
            List<Integration_Endpoint__mdt> endpoints = [
                SELECT DeveloperName, Active__c, Named_Credential__c, Timeout__c,
                       Base_Path__c, Pagination_Type__c, Pagination_Config__c,
                       External_ID_Field__c
                FROM Integration_Endpoint__mdt
                WHERE Active__c = true
                ORDER BY DeveloperName
            ];

            Logger.debug('Retrieved ' + endpoints.size() + ' active endpoints');
            return endpoints;
        } catch (Exception e) {
            Logger.error('Error loading active endpoints: ' + e.getMessage());
            return new List<Integration_Endpoint__mdt>();
        }
    }

    private static void loadMappingsForEndpoint(String endpointName) {
        // --- Check for mock mappings first in test context ---
        if (Test.isRunningTest() && mockMappingsByEndpoint != null && mockMappingsByEndpoint.containsKey(endpointName.toLowerCase())) {
            System.debug('IntegrationMappingCache: Using mock endpoint mappings for ' + endpointName);
            mappingCache.put(endpointName, mockMappingsByEndpoint.get(endpointName.toLowerCase()));
            return;
        }
        
        try {
            List<Integration_Mapping__mdt> mappings = [
                SELECT DeveloperName, Operation_Type__c, Source_Object__c, Dataweave_Map_Name__c,
                       Target_Object__c, Last_Modified_Date_Field__c, Active__c,
                       Last_Modified_Date_Override__c, Resource_Path__c,
                       Sync_Order__c, Page_Size__c, External_Id_Field_Overide__c,
                       Endpoint__r.DeveloperName, Endpoint__r.Id,
                       Endpoint__r.Named_Credential__c,
                       Endpoint__r.Timeout__c, Endpoint__r.Active__c,
                       Endpoint__r.Pagination_Type__c,
                       Endpoint__r.Pagination_Config__c, Endpoint__r.External_ID_Field__c,
                       Endpoint__r.Base_Path__c
                FROM Integration_Mapping__mdt 
                WHERE Endpoint__r.DeveloperName = :endpointName
                AND Active__c = true 
                AND Operation_Type__c = 'Pull'
            ];
            
            Map<Decimal, Integration_Mapping__mdt> endpointMappings = new Map<Decimal, Integration_Mapping__mdt>();
            for (Integration_Mapping__mdt mapping : mappings) {
                endpointMappings.put(mapping.Sync_Order__c, mapping);
                mappingByNameCache.put(mapping.DeveloperName, mapping);
            }
            
            mappingCache.put(endpointName, endpointMappings);
            Logger.debug('Loaded ' + mappings.size() + ' mappings for endpoint: ' + endpointName);
        } catch (Exception e) {
            Logger.error('Error loading mappings for endpoint ' + endpointName + ': ' + e.getMessage());
            // Create empty map to prevent repeated query attempts
            mappingCache.put(endpointName, new Map<Decimal, Integration_Mapping__mdt>());
        }
    }
    
    private static void loadMappingByName(String mappingName) {
        try {
            List<Integration_Mapping__mdt> mappings = [
                SELECT DeveloperName, Operation_Type__c, Source_Object__c, Dataweave_Map_Name__c,
                       Target_Object__c, Last_Modified_Date_Field__c, Active__c,
                       Last_Modified_Date_Override__c, Resource_Path__c,
                       Sync_Order__c, Page_Size__c, External_Id_Field_Overide__c,
                       Endpoint__r.DeveloperName, Endpoint__r.Id,
                       Endpoint__r.Named_Credential__c,
                       Endpoint__r.Timeout__c, Endpoint__r.Active__c,
                       Endpoint__r.Pagination_Type__c,
                       Endpoint__r.Pagination_Config__c, Endpoint__r.External_ID_Field__c,
                       Endpoint__r.Base_Path__c
                FROM Integration_Mapping__mdt
                WHERE DeveloperName = :mappingName
                LIMIT 1
            ];
            
            if (!mappings.isEmpty()) {
                Integration_Mapping__mdt mapping = mappings[0];
                mappingByNameCache.put(mappingName, mapping);
                
                // Also cache by endpoint if not already cached
                String endpointName = mapping.Endpoint__r?.DeveloperName;
                if (String.isNotBlank(endpointName) && !mappingCache.containsKey(endpointName)) {
                    loadMappingsForEndpoint(endpointName);
                }
            } else {
                Logger.warn('No mapping found with name: ' + mappingName);
            }
        } catch (Exception e) {
            Logger.error('Error loading mapping ' + mappingName + ': ' + e.getMessage());
        }
    }
    
    // --- Test Mocking Methods ---
    /**
     * @description Clears all mock mappings. Only usable within a test context.
     */
    @TestVisible
    public static void clearMockMappings() {
        if (!Test.isRunningTest()) {
            System.debug(LoggingLevel.ERROR, 'IntegrationMappingCache.clearMockMappings called outside test context.');
            return;
        }
        mockMappingsByName = null;
        mockMappingsByEndpoint = null;
        System.debug('Mock mappings cleared.');
    }

    /**
     * @description Sets a mock Integration_Mapping__mdt record for testing by name.
     *              Only usable within a test context.
     * @param mappingName The DeveloperName of the mapping to mock (case-insensitive).
     * @param mockMapping The mock Integration_Mapping__mdt instance.
     */
    @TestVisible
    public static void setMockMapping(String mappingName, Integration_Mapping__mdt mockMapping) {
        if (!Test.isRunningTest()) {
            System.debug(LoggingLevel.ERROR, 'IntegrationMappingCache.setMockMapping called outside test context.');
            return;
        }
        if (mockMappingsByName == null) {
            mockMappingsByName = new Map<String, Integration_Mapping__mdt>();
        }
        // Use lower case for case-insensitivity
        mockMappingsByName.put(mappingName.toLowerCase(), mockMapping); 
        System.debug('Mock mapping set for: ' + mappingName);
        
        // Also add to endpoint-based cache if endpoint relationship exists
        if (mockMapping.Endpoint__r != null && String.isNotBlank(mockMapping.Endpoint__r.DeveloperName)) {
            String endpointName = mockMapping.Endpoint__r.DeveloperName.toLowerCase();
            Decimal syncOrder = mockMapping.Sync_Order__c;
            
            if (mockMappingsByEndpoint == null) {
                mockMappingsByEndpoint = new Map<String, Map<Decimal, Integration_Mapping__mdt>>();
            }
            
            if (!mockMappingsByEndpoint.containsKey(endpointName)) {
                mockMappingsByEndpoint.put(endpointName, new Map<Decimal, Integration_Mapping__mdt>());
            }
            
            mockMappingsByEndpoint.get(endpointName).put(syncOrder, mockMapping);
            System.debug('Mock mapping also added for endpoint: ' + endpointName + ', sync order: ' + syncOrder);
            
            // Update real cache if it exists
            if (mappingCache.containsKey(mockMapping.Endpoint__r.DeveloperName)) {
                mappingCache.get(mockMapping.Endpoint__r.DeveloperName).put(syncOrder, mockMapping);
            }
        }
    }
}
