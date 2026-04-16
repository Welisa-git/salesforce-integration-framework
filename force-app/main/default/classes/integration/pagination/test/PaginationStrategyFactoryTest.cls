@IsTest
private class PaginationStrategyFactoryTest {

    // Dummy Strategy Implementation for testing
    public class TestPaginationStrategy extends PaginationStrategy {
        public TestPaginationStrategy() { super(); }
        public override PaginationResult processResponse(HttpResponse res, PaginationState state) { return null; }
        public override String modifyEndpointUrl(String url, PaginationState state) { return url; }
    }

    // Dummy Strategy without default constructor
    public class TestPaginationStrategyNoDefault extends PaginationStrategy {
        public TestPaginationStrategyNoDefault(String arg) { super(); }
        public override PaginationResult processResponse(HttpResponse res, PaginationState state) { return null; }
        public override String modifyEndpointUrl(String url, PaginationState state) { return url; }
    }

    // Class that does not extend PaginationStrategy
    public class NotAStrategy {}

    @IsTest
    static void testRegisterAndCreateStrategy() {
        String strategyName = 'MyCustomStrategy';
        Type strategyType = TestPaginationStrategy.class;

        Test.startTest();
        System.assertEquals(false, PaginationStrategyFactory.isStrategyRegistered(strategyName.toUpperCase()));

        PaginationStrategyFactory.registerStrategy(strategyName, strategyType);

        System.assertEquals(true, PaginationStrategyFactory.isStrategyRegistered(strategyName.toLowerCase()));
        System.assert(PaginationStrategyFactory.getRegisteredStrategyNames().contains(strategyName.toLowerCase()), 'Strategy name should be in registered list.');

        PaginationStrategy instance = PaginationStrategyFactory.createStrategy(strategyName);
        Test.stopTest();

        System.assertNotEquals(null, instance, 'Strategy instance should be created.');
        System.assert(instance instanceof TestPaginationStrategy, 'Instance should be of the correct type.');
    }

    @IsTest
    static void testBuiltInOffsetStrategyIsRegistered() {
        Test.startTest();
        PaginationStrategy instance = PaginationStrategyFactory.createStrategy('offset');
        Test.stopTest();

        System.assertNotEquals(null, instance, 'Built-in offset strategy should be creatable.');
        System.assert(instance instanceof CompanoOffsetPaginationStrategy, 'Offset should resolve to CompanoOffsetPaginationStrategy.');
    }

    @IsTest
    static void testRegisterStrategy_InvalidInputs() {
        Exception ex1 = null;
        try {
            PaginationStrategyFactory.registerStrategy('', TestPaginationStrategy.class);
        } catch (Exception e) { ex1 = e; }
        System.assertNotEquals(null, ex1, 'Exception expected for blank name.');
        System.assert(ex1 instanceof PaginationStrategyFactory.PaginationException && ex1.getMessage().contains('name cannot be blank'));

        Exception ex2 = null;
        try {
            PaginationStrategyFactory.registerStrategy('ValidName', null);
        } catch (Exception e) { ex2 = e; }
        System.assertNotEquals(null, ex2, 'Exception expected for null type.');
        System.assert(ex2 instanceof PaginationStrategyFactory.PaginationException && ex2.getMessage().contains('type cannot be null'));
    }

    @IsTest
    static void testCreateStrategy_Unknown() {
        Exception ex = null;
        Test.startTest();
        try {
            PaginationStrategyFactory.createStrategy('NonExistentStrategy');
        } catch (Exception e) { ex = e; }
        Test.stopTest();

        System.assertNotEquals(null, ex, 'Exception expected for unknown strategy.');
        System.assert(ex instanceof PaginationStrategyFactory.PaginationException && ex.getMessage().contains('Unknown pagination strategy'));
    }

    @IsTest
    static void testCreateStrategy_NoDefaultConstructor() {
        String name = 'NoDefaultConstructor';
        PaginationStrategyFactory.registerStrategy(name, TestPaginationStrategyNoDefault.class);

        Exception ex = null;
        Test.startTest();
        try {
            PaginationStrategyFactory.createStrategy(name);
        } catch (Exception e) { ex = e; }
        Test.stopTest();

        System.assertNotEquals(null, ex, 'Exception expected when creating strategy without default constructor.');
        System.assert(ex instanceof PaginationStrategyFactory.PaginationException && ex.getMessage().contains('Failed to create strategy'));
    }

    @IsTest
    static void testCreateStrategy_NotAStrategyClass() {
        String name = 'NotAStrategy';
        PaginationStrategyFactory.registerStrategy(name, NotAStrategy.class);

        Exception ex = null;
        Test.startTest();
        try {
            PaginationStrategyFactory.createStrategy(name);
        } catch (Exception e) { ex = e; }
        Test.stopTest();

        System.assertNotEquals(null, ex, 'Exception expected when creating non-strategy class.');
        System.assert(ex instanceof PaginationStrategyFactory.PaginationException && ex.getMessage().contains('must extend PaginationStrategy'));
    }

    @IsTest
    static void testCreateStrategyFromEndpoint_NoMappings() {
        String endpointDevName = 'EndpointWithNoMappings_NotInOrg';
        Integration_Endpoint__mdt mockEndpoint = new Integration_Endpoint__mdt(
            DeveloperName = endpointDevName,
            Pagination_Type__c = 'MockTypeNameStrategy'
        );

        IntegrationMappingCache.clearCacheForEndpoint(endpointDevName);

        Exception ex = null;
        Test.startTest();
        try {
            PaginationStrategyFactory.createStrategy(mockEndpoint);
        } catch(Exception e) { ex = e; }
        Test.stopTest();

        System.assertNotEquals(null, ex, 'Exception expected when no mappings found.');
        System.assert(ex instanceof PaginationStrategyFactory.PaginationException, 'Expected PaginationException type.');
        System.assert(ex.getMessage().contains('No active mappings found'), 'Exception message should indicate no active mappings found.');
    }

    @IsTest
    static void testSetMockStrategy() {
        TestPaginationStrategy mockStrategy = new TestPaginationStrategy();
        PaginationStrategyFactory.setMockStrategy(mockStrategy);

        // Setup a mock endpoint to avoid NoMappings exception
        String epName = 'MockEP_Test';
        Integration_Endpoint__mdt mockEndpoint = new Integration_Endpoint__mdt(
            DeveloperName = epName,
            Active__c = true,
            Named_Credential__c = 'TestNC',
            Pagination_Config__c = 'PaginationStrategyFactoryTest.TestPaginationStrategy'
        );
        IntegrationMappingCache.clearMockMappings();
        Integration_Mapping__mdt mockMapping = new Integration_Mapping__mdt(
            DeveloperName = 'MockMap_Test',
            Active__c = true,
            Endpoint__r = mockEndpoint,
            Sync_Order__c = 1
        );
        IntegrationMappingCache.setMockMapping('MockMap_Test', mockMapping);

        Test.startTest();
        PaginationStrategy result = PaginationStrategyFactory.createStrategy(mockEndpoint);
        Test.stopTest();

        System.assertEquals(mockStrategy, result, 'Should return the mock strategy instance.');

        PaginationStrategyFactory.clearMockStrategy();
    }

    @IsTest
    static void testCreateStrategyFromEndpoint_BuiltInOffsetSuccess() {
        String epName = 'CompanoOffsetEP_Test';
        Integration_Endpoint__mdt mockEndpoint = new Integration_Endpoint__mdt(
            DeveloperName = epName,
            Active__c = true,
            Named_Credential__c = 'TestNC',
            Pagination_Type__c = 'offset'
        );
        IntegrationMappingCache.clearMockMappings();
        Integration_Mapping__mdt mockMapping = new Integration_Mapping__mdt(
            DeveloperName = 'CompanoOffsetMap_Test',
            Active__c = true,
            Endpoint__r = mockEndpoint,
            Endpoint__c = mockEndpoint.Id,
            Sync_Order__c = 1,
            Page_Size__c = 25
        );
        IntegrationMappingCache.setMockMapping('CompanoOffsetMap_Test', mockMapping);

        Test.startTest();
        PaginationStrategy result = PaginationStrategyFactory.createStrategy(mockEndpoint);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Built-in offset strategy should be created from endpoint metadata.');
        System.assert(result instanceof CompanoOffsetPaginationStrategy, 'Expected CompanoOffsetPaginationStrategy instance.');
    }

    @IsTest
    static void testCreateStrategyFromEndpoint_CustomClassSuccess() {
        String epName = 'CustomClassEP_Test';
        Integration_Endpoint__mdt mockEndpoint = new Integration_Endpoint__mdt(
            DeveloperName = epName,
            Active__c = true,
            Named_Credential__c = 'TestNC',
            Pagination_Config__c = 'PaginationStrategyFactoryTest.TestPaginationStrategy'
        );
        IntegrationMappingCache.clearMockMappings();
        Integration_Mapping__mdt mockMapping = new Integration_Mapping__mdt(
            DeveloperName = 'CustomClassMap_Test',
            Active__c = true,
            Endpoint__r = mockEndpoint,
            Endpoint__c = mockEndpoint.Id,
            Sync_Order__c = 1
        );
        IntegrationMappingCache.setMockMapping('CustomClassMap_Test', mockMapping);

        Test.startTest();
        PaginationStrategy result = PaginationStrategyFactory.createStrategy(mockEndpoint);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Custom strategy should be created from endpoint metadata.');
        System.assert(result instanceof TestPaginationStrategy, 'Expected test custom strategy instance.');
    }
}
