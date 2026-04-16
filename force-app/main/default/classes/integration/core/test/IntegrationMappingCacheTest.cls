/**
 * @description Test class for IntegrationMappingCache
 * NOTE: Tests in this class verify cache behavior (clearing, invalid inputs) 
 * but CANNOT reliably verify successful retrieval of specific MDT records 
 * without SeeAllData=true or an MDT mocking framework, as they depend on 
 * MDT records existing in the target org.
 */
@IsTest
private class IntegrationMappingCacheTest {

    private static String testEndpointName = 'TestCacheEndpoint_NotInOrg';
    private static String testMappingName1 = 'TestCacheMapping1_NotInOrg';
    private static String testMappingName2 = 'TestCacheMapping2_NotInOrg';
    private static String inactiveMappingName = 'InactiveCacheMapping_NotInOrg';
    private static String anotherEndpointName = 'AnotherCacheEndpoint_NotInOrg';
    private static String anotherMappingName = 'AnotherCacheMapping_NotInOrg';

    @IsTest
    static void testGetMappingByEndpointAndOrder_SuccessPathRuns() {
        IntegrationMappingCache.clearCache();

        Integration_Mapping__mdt mapping1 = null;
        Integration_Mapping__mdt mapping2 = null;
        Exception caughtEx = null;

        Test.startTest();
        try {
            mapping1 = IntegrationMappingCache.getMappingByEndpointAndOrder(testEndpointName, 1);
            mapping2 = IntegrationMappingCache.getMappingByEndpointAndOrder(testEndpointName, 2);
        } catch (Exception e) {
            caughtEx = e;
        }
        Test.stopTest();

        System.assertEquals(null, caughtEx, 'getMappingByEndpointAndOrder should not throw unexpected errors.');
        System.debug('Result for mapping1 (expected null if MDT missing): ' + mapping1);
        System.debug('Result for mapping2 (expected null if MDT missing): ' + mapping2);
    }

    @IsTest
    static void testGetMappingByEndpointAndOrder_NotFound() {
        IntegrationMappingCache.clearCache();

        Test.startTest();
        Integration_Mapping__mdt mappingNotFoundOrder = IntegrationMappingCache.getMappingByEndpointAndOrder(testEndpointName, 99);
        Integration_Mapping__mdt mappingNotFoundEndpoint = IntegrationMappingCache.getMappingByEndpointAndOrder('NonExistentEndpoint_NotInOrg', 1);
        Integration_Mapping__mdt mappingInactive = IntegrationMappingCache.getMappingByEndpointAndOrder(testEndpointName, 3);
        Test.stopTest();

        System.assertEquals(null, mappingNotFoundOrder, 'Should return null for non-existent sync order.');
        System.assertEquals(null, mappingNotFoundEndpoint, 'Should return null for non-existent endpoint.');
        System.assertEquals(null, mappingInactive, 'Should return null for inactive mapping sync order (due to Active__c filter).');
    }

    @IsTest
    static void testGetMappingByEndpointAndOrder_InvalidInput() {
        IntegrationMappingCache.clearCache();

        Test.startTest();
        Integration_Mapping__mdt mappingNullEndpoint = IntegrationMappingCache.getMappingByEndpointAndOrder(null, 1);
        Integration_Mapping__mdt mappingBlankEndpoint = IntegrationMappingCache.getMappingByEndpointAndOrder('', 1);
        Integration_Mapping__mdt mappingNullOrder = IntegrationMappingCache.getMappingByEndpointAndOrder(testEndpointName, null);
        Test.stopTest();

        System.assertEquals(null, mappingNullEndpoint, 'Should return null for null endpoint.');
        System.assertEquals(null, mappingBlankEndpoint, 'Should return null for blank endpoint.');
        System.assertEquals(null, mappingNullOrder, 'Should return null for null sync order.');
    }

    @IsTest
    static void testGetMappingByName_SuccessPathRuns() {
        IntegrationMappingCache.clearCache();

        Integration_Mapping__mdt mapping = null;
        Exception caughtEx = null;

        Test.startTest();
        try {
            mapping = IntegrationMappingCache.getMappingByName(testMappingName1);
        } catch (Exception e) {
            caughtEx = e;
        }
        Test.stopTest();

        System.assertEquals(null, caughtEx, 'getMappingByName should not throw unexpected errors.');
        System.debug('Result for mappingByName (expected null if MDT missing): ' + mapping);
    }

    @IsTest
    static void testGetMappingByName_NotFound() {
        IntegrationMappingCache.clearCache();

        Test.startTest();
        Integration_Mapping__mdt mappingNotFound = IntegrationMappingCache.getMappingByName('NonExistentMappingName_NotInOrg');
        Integration_Mapping__mdt mappingInactive = IntegrationMappingCache.getMappingByName(inactiveMappingName);
        Test.stopTest();

        System.assertEquals(null, mappingNotFound, 'Should return null for non-existent mapping name.');
        System.assertEquals(null, mappingInactive, 'Should return null for inactive mapping name (due to Active__c filter).');
    }

    @IsTest
    static void testGetMappingByName_InvalidInput() {
        IntegrationMappingCache.clearCache();

        Test.startTest();
        Integration_Mapping__mdt mappingNull = IntegrationMappingCache.getMappingByName(null);
        Integration_Mapping__mdt mappingBlank = IntegrationMappingCache.getMappingByName('');
        Test.stopTest();

        System.assertEquals(null, mappingNull, 'Should return null for null name.');
        System.assertEquals(null, mappingBlank, 'Should return null for blank name.');
    }

    @IsTest
    static void testGetMappingByName_MockMapping() {
        IntegrationMappingCache.clearCache();
        IntegrationMappingCache.clearMockMappings();

        Integration_Endpoint__mdt mockEndpoint = new Integration_Endpoint__mdt(
            DeveloperName = testEndpointName,
            Active__c = true,
            Named_Credential__c = 'TestNC'
        );
        Integration_Mapping__mdt mockMapping = new Integration_Mapping__mdt(
            DeveloperName = testMappingName1,
            Active__c = true,
            Endpoint__r = mockEndpoint
        );
        IntegrationMappingCache.setMockMapping(testMappingName1, mockMapping);

        Test.startTest();
        Integration_Mapping__mdt result = IntegrationMappingCache.getMappingByName(testMappingName1);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return mock mapping.');
        System.assertEquals(testMappingName1, result.DeveloperName, 'DeveloperName should match mock.');
    }

    @IsTest
    static void testGetMappingByEndpointAndOrder_MockMappingDecimalScaleMismatch() {
        IntegrationMappingCache.clearCache();
        IntegrationMappingCache.clearMockMappings();

        Integration_Endpoint__mdt mockEndpoint = new Integration_Endpoint__mdt(
            DeveloperName = testEndpointName,
            Active__c = true,
            Named_Credential__c = 'TestNC'
        );
        Integration_Mapping__mdt mockMapping = new Integration_Mapping__mdt(
            DeveloperName = testMappingName1,
            Active__c = true,
            Sync_Order__c = 1.0,
            Endpoint__r = mockEndpoint
        );
        IntegrationMappingCache.setMockMapping(testMappingName1, mockMapping);

        Test.startTest();
        Integration_Mapping__mdt result = IntegrationMappingCache.getMappingByEndpointAndOrder(testEndpointName, 1);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Lookup should work even when sync order scale differs.');
        System.assertEquals(testMappingName1, result.DeveloperName, 'DeveloperName should match the mock mapping.');
    }

    @IsTest
    static void testGetMappingsForEndpoint_SuccessPathRuns() {
        IntegrationMappingCache.clearCache();

        List<Integration_Mapping__mdt> mappings = null;
        Exception caughtEx = null;

        Test.startTest();
        try {
            mappings = IntegrationMappingCache.getMappingsForEndpoint(testEndpointName);
        } catch (Exception e) {
            caughtEx = e;
        }
        Test.stopTest();

        System.assertEquals(null, caughtEx, 'getMappingsForEndpoint should not throw unexpected errors.');
        System.assertNotEquals(null, mappings, 'Mapping list should not be null (expect empty list).');
        System.debug('Result for getMappingsForEndpoint (expected empty if MDT missing): size = ' + mappings.size());
    }

    @IsTest
    static void testGetMappingsForEndpoint_NotFound() {
        IntegrationMappingCache.clearCache();

        Test.startTest();
        List<Integration_Mapping__mdt> mappings = IntegrationMappingCache.getMappingsForEndpoint('NonExistentEndpoint_NotInOrg');
        Test.stopTest();

        System.assertNotEquals(null, mappings, 'Should return empty list, not null.');
        System.assertEquals(0, mappings.size(), 'Should return empty list for non-existent endpoint.');
    }

    @IsTest
    static void testGetMappingsForEndpoint_InvalidInput() {
        IntegrationMappingCache.clearCache();

        Test.startTest();
        List<Integration_Mapping__mdt> mappingsNull = IntegrationMappingCache.getMappingsForEndpoint(null);
        List<Integration_Mapping__mdt> mappingsBlank = IntegrationMappingCache.getMappingsForEndpoint('');
        Test.stopTest();

        System.assertNotEquals(null, mappingsNull, 'Should not be null for null endpoint.');
        System.assertEquals(0, mappingsNull.size(), 'Should be empty for null endpoint.');
        System.assertNotEquals(null, mappingsBlank, 'Should not be null for blank endpoint.');
        System.assertEquals(0, mappingsBlank.size(), 'Should be empty for blank endpoint.');
    }

    @IsTest
    static void testGetMaxSyncOrderForEndpoint_SuccessPathRuns() {
        IntegrationMappingCache.clearCache();

        Decimal maxOrder = -1;
        Exception caughtEx = null;

        Test.startTest();
        try {
            maxOrder = IntegrationMappingCache.getMaxSyncOrderForEndpoint(testEndpointName);
        } catch (Exception e) {
            caughtEx = e;
        }
        Test.stopTest();

        System.assertEquals(null, caughtEx, 'getMaxSyncOrderForEndpoint should not throw unexpected errors.');
        System.debug('Result for getMaxSyncOrderForEndpoint (expected 0 if MDT missing): ' + maxOrder);
    }

    @IsTest
    static void testGetMaxSyncOrderForEndpoint_NotFound() {
        IntegrationMappingCache.clearCache();

        Test.startTest();
        Decimal maxOrder = IntegrationMappingCache.getMaxSyncOrderForEndpoint('NonExistentEndpoint_NotInOrg');
        Test.stopTest();

        System.assertEquals(0, maxOrder, 'Max sync order should be 0 for non-existent endpoint.');
    }

    @IsTest
    static void testGetMaxSyncOrderForEndpoint_InvalidInput() {
        IntegrationMappingCache.clearCache();

        Test.startTest();
        Decimal maxOrderNull = IntegrationMappingCache.getMaxSyncOrderForEndpoint(null);
        Decimal maxOrderBlank = IntegrationMappingCache.getMaxSyncOrderForEndpoint('');
        Test.stopTest();

        System.assertEquals(0, maxOrderNull, 'Should be 0 for null endpoint.');
        System.assertEquals(0, maxOrderBlank, 'Should be 0 for blank endpoint.');
    }

    @IsTest
    static void testCacheClearingAndReloading() {
        IntegrationMappingCache.clearCache();

        IntegrationMappingCache.getMappingByEndpointAndOrder(testEndpointName, 1);
        IntegrationMappingCache.getMappingByName(testMappingName2);
        IntegrationMappingCache.getMappingsForEndpoint(testEndpointName);
        IntegrationMappingCache.getMaxSyncOrderForEndpoint(testEndpointName);
        IntegrationMappingCache.getMappingByName(anotherMappingName);

        Test.startTest();

        IntegrationMappingCache.clearCacheForEndpoint(testEndpointName);

        Integration_Mapping__mdt reloadedMapping1 = IntegrationMappingCache.getMappingByEndpointAndOrder(testEndpointName, 1);
        List<Integration_Mapping__mdt> reloadedList = IntegrationMappingCache.getMappingsForEndpoint(testEndpointName);
        Integration_Mapping__mdt reloadedMappingName = IntegrationMappingCache.getMappingByName(testMappingName2);

        Integration_Mapping__mdt otherMapping = IntegrationMappingCache.getMappingByName(anotherMappingName);

        IntegrationMappingCache.clearCache();

        Integration_Mapping__mdt finalMapping1 = IntegrationMappingCache.getMappingByEndpointAndOrder(testEndpointName, 1);
        Integration_Mapping__mdt finalOtherMapping = IntegrationMappingCache.getMappingByName(anotherMappingName);

        Test.stopTest();

        System.assertEquals(null, reloadedMapping1, 'Mapping 1 should be null after endpoint cache clear (as MDT likely missing).');
        System.assertNotEquals(null, reloadedList, 'Mapping list should be non-null after endpoint cache clear.');
        System.assertEquals(0, reloadedList.size(), 'Mapping list should be empty after endpoint cache clear (as MDT likely missing).');
        System.assertEquals(null, reloadedMappingName, 'Mapping 2 by name should be null if cleared by endpoint or MDT missing.');

        System.debug('Other mapping after endpoint clear (expected null if MDT missing): ' + otherMapping);

        System.assertEquals(null, finalMapping1, 'Mapping 1 should be null after full clear.');
        System.assertEquals(null, finalOtherMapping, 'Other endpoint mapping should be null after full clear.');
    }

    @IsTest
    static void testRefreshEndpointCache() {
        IntegrationMappingCache.clearCache();

        Exception caughtEx = null;
        Test.startTest();
        try {
            IntegrationMappingCache.refreshEndpointCache(testEndpointName);
            IntegrationMappingCache.refreshEndpointCache(null);
            IntegrationMappingCache.refreshEndpointCache('');
        } catch (Exception e) {
            caughtEx = e;
        }
        Test.stopTest();

        System.assertEquals(null, caughtEx, 'refreshEndpointCache should not throw unexpected errors.');
    }
}
