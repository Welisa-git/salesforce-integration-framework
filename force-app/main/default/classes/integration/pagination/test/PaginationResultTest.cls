@IsTest
private class PaginationResultTest {

    @IsTest
    static void testCreateSuccessWithRecords() {
        List<Object> records = new List<Object>{ 'record1', 'record2' };
        PaginationState nextState = new PaginationState(10, 5);
        Boolean hasMore = true;

        Test.startTest();
        PaginationResult result = PaginationResult.createSuccess(records, nextState, hasMore);
        Test.stopTest();

        System.assertEquals(true, result.isSuccess(), 'Should be success.');
        System.assertEquals(records, result.getRecords(), 'Records should match.');
        System.assertEquals(null, result.getSObjects(), 'SObjects should be null.');
        System.assertEquals(nextState, result.getNextState(), 'Next state should match.');
        System.assertEquals(hasMore, result.getHasMoreData(), 'HasMoreData should match.');
        System.assertEquals(null, result.getErrorMessage(), 'Error message should be null.');
        System.assertEquals(0, result.getAllCustomData().size(), 'Custom data should be empty.');
    }

    @IsTest
    static void testCreateSuccessWithSObjects() {
        List<SObject> sObjects = new List<Account>{ new Account(Name = 'Test1'), new Account(Name = 'Test2') };
        PaginationState nextState = new PaginationState(20, 10);
        Boolean hasMore = false;

        Test.startTest();
        PaginationResult result = PaginationResult.createSuccess(sObjects, nextState, hasMore);
        Test.stopTest();

        System.assertEquals(true, result.isSuccess(), 'Should be success.');
        System.assertEquals(null, result.getRecords(), 'Records should be null.');
        System.assertEquals(sObjects, result.getSObjects(), 'SObjects should match.');
        System.assertEquals(nextState, result.getNextState(), 'Next state should match.');
        System.assertEquals(hasMore, result.getHasMoreData(), 'HasMoreData should match.');
        System.assertEquals(null, result.getErrorMessage(), 'Error message should be null.');
    }

    @IsTest
    static void testCreateError() {
        String errorMsg = 'Something went wrong';

        Test.startTest();
        PaginationResult result = PaginationResult.createError(errorMsg);
        Test.stopTest();

        System.assertEquals(false, result.isSuccess(), 'Should be error.');
        System.assertEquals(errorMsg, result.getErrorMessage(), 'Error message should match.');
        System.assertNotEquals(null, result.getRecords(), 'Records list should not be null on error.');
        System.assertEquals(0, result.getRecords().size(), 'Records list should be empty on error.');
        System.assertNotEquals(null, result.getSObjects(), 'SObjects list should not be null on error.');
        System.assertEquals(0, result.getSObjects().size(), 'SObjects list should be empty on error.');
        System.assertEquals(null, result.getNextState(), 'Next state should be null on error.');
        System.assertEquals(false, result.getHasMoreData(), 'HasMoreData should be false on error.');
    }

    @IsTest
    static void testCustomData() {
        PaginationResult result = PaginationResult.createSuccess(new List<Object>(), null, false);
        String key1 = 'totalCount';
        Integer value1 = 150;
        String key2 = 'dataType';
        String value2 = 'JSON';

        Test.startTest();
        result.setCustomData(key1, value1);
        result.setCustomData(key2, value2);
        Test.stopTest();

        System.assertEquals(true, result.hasCustomData(key1), 'Should have custom data for key1.');
        System.assertEquals(value1, result.getCustomData(key1), 'Custom data value1 should match.');
        System.assertEquals(true, result.hasCustomData(key2), 'Should have custom data for key2.');
        System.assertEquals(value2, result.getCustomData(key2), 'Custom data value2 should match.');
        System.assertEquals(false, result.hasCustomData('nonExistentKey'), 'Should not have non-existent key.');
        System.assertEquals(null, result.getCustomData('nonExistentKey'), 'Getting non-existent key should return null.');

        Map<String, Object> allData = result.getAllCustomData();
        System.assertEquals(2, allData.size(), 'Should return all custom data.');
        System.assertEquals(value1, allData.get(key1));
        System.assertEquals(value2, allData.get(key2));

        // Test immutability of getAllCustomData
        allData.put('newValue', 1);
        System.assertEquals(2, result.getAllCustomData().size(), 'Internal custom data should not be modified.');
    }
}
