/**
 * @description Test class for AbstractIntegrationService
 */
@IsTest
private class AbstractIntegrationServiceTest {

    private static String testEndpointName = 'TestAIS_Endpoint';
    private static String testMappingName = 'TestAIS_Mapping';
    private static String testNamedCredential = 'TestAIS_Named_Cred';
    private static String mockBasePath = 'https://mock.api.example.com';

    // --- Concrete subclass for testing ---
    private class ConcreteIntegrationService extends AbstractIntegrationService {
        public ConcreteIntegrationService(String endpointName, String mappingName) {
            super(endpointName, mappingName);
        }
    }

    // --- Mock for HTTP Callouts ---
    private class MockHttpResponseGenerator implements HttpCalloutMock {
        Map<String, HttpResponse> responses = new Map<String, HttpResponse>();
        Boolean shouldThrowException = false;
        String lastRequestBody;
        String lastRequestMethod;
        String lastEndpoint;

        public void addResponse(String url, Integer statusCode, String status, String body) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setStatus(status);
            res.setBody(body);
            this.responses.put(url, res);
        }

        public HttpResponse respond(HttpRequest req) {
            if (shouldThrowException) {
                throw new System.CalloutException('Mock connection failed');
            }

            lastRequestBody = req.getBody();
            lastRequestMethod = req.getMethod();
            lastEndpoint = req.getEndpoint();

            String endpointUrl = req.getEndpoint();
            if (responses.containsKey(endpointUrl)) {
                return responses.get(endpointUrl);
            } else {
                HttpResponse res = new HttpResponse();
                res.setStatusCode(404);
                res.setStatus('Not Found in Mock');
                res.setBody('{"error": "Mock response not configured for this URL: ' + endpointUrl + '"}');
                return res;
            }
        }
    }

    // --- Helper to prime the mock cache ---
    private static void setupTestData() {
        IntegrationMappingCache.clearCache();
        IntegrationMappingCache.clearMockMappings();

        Integration_Endpoint__mdt mockEndpoint = new Integration_Endpoint__mdt(
            DeveloperName = testEndpointName,
            Active__c = true,
            Base_Path__c = mockBasePath,
            Named_Credential__c = testNamedCredential,
            External_ID_Field__c = 'ExtId__c',
            Timeout__c = 60000
        );

        Integration_Mapping__mdt mockMapping = new Integration_Mapping__mdt(
            DeveloperName = testMappingName,
            Active__c = true,
            Operation_Type__c = 'Pull',
            Target_Object__c = 'Account',
            Dataweave_Map_Name__c = 'TestDWMap',
            Endpoint__c = mockEndpoint.Id,
            Endpoint__r = mockEndpoint
        );

        IntegrationMappingCache.setMockMapping(testMappingName, mockMapping);
    }

    // --- Test Methods ---

    @IsTest
    static void testConstructor_Success() {
        setupTestData();

        Test.startTest();
        ConcreteIntegrationService service = null;
        Exception caughtEx = null;
        try {
            service = new ConcreteIntegrationService(testEndpointName, testMappingName);
        } catch (Exception e) {
            caughtEx = e;
        }
        Test.stopTest();

        System.assertEquals(null, caughtEx, 'Constructor should not throw an exception on success.');
        System.assertNotEquals(null, service, 'Service instance should be created.');
        System.assertNotEquals(null, service.mapping, 'Mapping should be loaded.');
        System.assertNotEquals(null, service.endpoint, 'Endpoint should be loaded.');
        System.assertEquals(testMappingName, service.mapping.DeveloperName, 'Correct mapping should be loaded.');
        System.assertEquals(testEndpointName, service.endpoint.DeveloperName, 'Correct endpoint should be loaded.');
    }

    @IsTest
    static void testConstructor_MappingNotFound() {
        IntegrationMappingCache.clearCache();
        IntegrationMappingCache.clearMockMappings();

        Test.startTest();
        ConcreteIntegrationService service = null;
        Exception caughtEx = null;
        try {
            service = new ConcreteIntegrationService('AnyEndpoint', 'NonExistentMapping');
        } catch (Exception e) {
            caughtEx = e;
        }
        Test.stopTest();

        System.assertNotEquals(null, caughtEx, 'Expected an exception when mapping is not found.');
        System.assert(caughtEx instanceof AbstractIntegrationService.IntegrationException, 'Expected IntegrationException.');
        System.assert(caughtEx.getMessage().contains('Mapping not found'), 'Correct error message expected.');
    }

    @IsTest
    static void testConstructor_InactiveMapping() {
        setupTestData();

        Integration_Mapping__mdt mapping = IntegrationMappingCache.getMappingByName(testMappingName).clone();
        mapping.Active__c = false;
        IntegrationMappingCache.setMockMapping(testMappingName, mapping);

        Test.startTest();
        ConcreteIntegrationService service = null;
        Exception caughtEx = null;
        try {
            service = new ConcreteIntegrationService(testEndpointName, testMappingName);
        } catch (Exception e) {
            caughtEx = e;
        }
        Test.stopTest();

        System.assertNotEquals(null, caughtEx, 'Expected an exception for inactive mapping.');
        System.assert(caughtEx instanceof AbstractIntegrationService.IntegrationException, 'Expected IntegrationException.');
        System.assert(caughtEx.getMessage().contains('Mapping configuration is inactive'), 'Correct error message expected.');
    }

    @IsTest
    static void testConstructor_InactiveEndpoint() {
        setupTestData();

        Integration_Mapping__mdt mapping = IntegrationMappingCache.getMappingByName(testMappingName).clone();
        mapping.Endpoint__r.Active__c = false;
        IntegrationMappingCache.setMockMapping(testMappingName, mapping);

        Test.startTest();
        ConcreteIntegrationService service = null;
        Exception caughtEx = null;
        try {
            service = new ConcreteIntegrationService(testEndpointName, testMappingName);
        } catch (Exception e) {
            caughtEx = e;
        }
        Test.stopTest();

        System.assertNotEquals(null, caughtEx, 'Expected an exception for inactive endpoint.');
        System.assert(caughtEx instanceof AbstractIntegrationService.IntegrationException, 'Expected IntegrationException.');
        System.assert(caughtEx.getMessage().contains('Endpoint configuration is inactive'), 'Correct error message expected.');
    }

    @IsTest
    static void testConstructor_MissingNamedCredential() {
        setupTestData();

        Integration_Mapping__mdt mapping = IntegrationMappingCache.getMappingByName(testMappingName).clone();
        mapping.Endpoint__r.Named_Credential__c = null;
        IntegrationMappingCache.setMockMapping(testMappingName, mapping);

        Test.startTest();
        ConcreteIntegrationService service = null;
        Exception caughtEx = null;
        try {
            service = new ConcreteIntegrationService(testEndpointName, testMappingName);
        } catch (Exception e) {
            caughtEx = e;
        }
        Test.stopTest();

        System.assertNotEquals(null, caughtEx, 'Expected an exception for missing named credential.');
        System.assert(caughtEx instanceof AbstractIntegrationService.IntegrationException, 'Expected IntegrationException.');
        System.assert(caughtEx.getMessage().contains('Named Credential is required'), 'Correct error message expected.');
    }

    @IsTest
    static void testMakeCallout_Success() {
        setupTestData();

        ConcreteIntegrationService service = new ConcreteIntegrationService(testEndpointName, testMappingName);
        String resourcePath = '/test/resource';
        String expectedUrl = 'callout:' + testNamedCredential + resourcePath;
        String mockResponseBody = '{"success": true}';

        MockHttpResponseGenerator mockHttp = new MockHttpResponseGenerator();
        mockHttp.addResponse(expectedUrl, 200, 'OK', mockResponseBody);
        Test.setMock(HttpCalloutMock.class, mockHttp);

        Test.startTest();
        HttpResponse response = null;
        Exception caughtEx = null;
        try {
            response = service.makeCallout('GET', resourcePath);
        } catch (Exception e) {
            caughtEx = e;
        }
        Test.stopTest();

        System.assertEquals(null, caughtEx, 'No exception expected on successful callout.');
        System.assertNotEquals(null, response, 'Response should not be null.');
        System.assertEquals(200, response.getStatusCode(), 'Expected status code 200.');
        System.assertEquals(mockResponseBody, response.getBody(), 'Expected mock response body.');
        System.assertEquals('GET', mockHttp.lastRequestMethod, 'Expected GET request.');
        System.assertEquals(expectedUrl, mockHttp.lastEndpoint, 'Expected GET endpoint.');
        System.assert(String.isBlank(mockHttp.lastRequestBody), 'GET callouts should not send a request body.');
    }

    @IsTest
    static void testMakeCallout_HttpError() {
        setupTestData();

        ConcreteIntegrationService service = new ConcreteIntegrationService(testEndpointName, testMappingName);
        String resourcePath = '/test/error';
        String expectedUrl = 'callout:' + testNamedCredential + resourcePath;
        String mockErrorBody = '{"error": "Server unavailable"}';

        MockHttpResponseGenerator mockHttp = new MockHttpResponseGenerator();
        mockHttp.addResponse(expectedUrl, 503, 'Service Unavailable', mockErrorBody);
        Test.setMock(HttpCalloutMock.class, mockHttp);

        Test.startTest();
        HttpResponse response = null;
        Exception caughtEx = null;
        try {
            response = service.makeCallout('GET', resourcePath);
        } catch (Exception e) {
            caughtEx = e;
        }
        Test.stopTest();

        System.assertEquals(null, caughtEx, 'makeCallout should not throw based on HTTP status code.');
        System.assertNotEquals(null, response, 'Response should still be returned on HTTP error.');
        System.assertEquals(503, response.getStatusCode(), 'Expected status code 503.');
        System.assertEquals(mockErrorBody, response.getBody(), 'Expected mock error body.');
    }

    @IsTest
    static void testMakeCallout_CalloutException() {
        setupTestData();

        ConcreteIntegrationService service = new ConcreteIntegrationService(testEndpointName, testMappingName);
        String resourcePath = '/test/exception';

        MockHttpResponseGenerator mockHttp = new MockHttpResponseGenerator();
        mockHttp.shouldThrowException = true;
        Test.setMock(HttpCalloutMock.class, mockHttp);

        Test.startTest();
        HttpResponse response = null;
        Exception caughtEx = null;
        try {
            response = service.makeCallout('GET', resourcePath);
        } catch (Exception e) {
            caughtEx = e;
        }
        Test.stopTest();

        System.assertEquals(null, response, 'Response should be null when an exception occurs.');
        System.assertNotEquals(null, caughtEx, 'Expected an exception to be caught.');
        System.assert(caughtEx instanceof AbstractIntegrationService.IntegrationException,
            'Expected IntegrationException, but got: ' + caughtEx.getTypeName());
        System.assert(caughtEx.getMessage().contains('HTTP callout failed'),
            'Expected IntegrationException message to indicate callout failure.');
    }

    @IsTest
    static void testSummarizeTextForLog_ReturnsOnlyLength() {
        Test.startTest();
        String summary = AbstractIntegrationService.summarizeTextForLog('{"Products":[{"Code":"10010"}]}');
        String nullSummary = AbstractIntegrationService.summarizeTextForLog(null);
        Test.stopTest();

        System.assertEquals('len=31', summary, 'Expected summary to contain only the payload length.');
        System.assertEquals('null', nullSummary, 'Expected null summary for null values.');
    }
}
