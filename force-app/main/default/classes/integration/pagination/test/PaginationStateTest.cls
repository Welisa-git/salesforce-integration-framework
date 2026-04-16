@IsTest
private class PaginationStateTest {

    @IsTest
    static void testConstructorBasic() {
        Integer offset = 0;
        Integer pageSize = 100;

        Test.startTest();
        PaginationState state = new PaginationState(offset, pageSize);
        Test.stopTest();

        System.assertEquals(offset, state.getOffset(), 'Offset should match.');
        System.assertEquals(pageSize, state.getPageSize(), 'Page size should match.');
        System.assertEquals(0, state.getAllCustomData().size(), 'Custom data should be empty.');
    }

    @IsTest
    static void testConstructorWithCustomData() {
        Integer offset = 50;
        Integer pageSize = 25;
        Map<String, Object> custom = new Map<String, Object>{
            'lastId' => 'xyz123',
            'filterDate' => Date.today()
        };

        Test.startTest();
        PaginationState state = new PaginationState(offset, pageSize, custom);
        Test.stopTest();

        System.assertEquals(offset, state.getOffset());
        System.assertEquals(pageSize, state.getPageSize());
        System.assertEquals(2, state.getAllCustomData().size(), 'Should have 2 custom entries.');
        System.assertEquals('xyz123', state.getCustomData('lastId'));
        System.assertEquals(Date.today(), state.getCustomData('filterDate'));
    }

    @IsTest
    static void testConstructorWithNullCustomData() {
        Integer offset = 10;
        Integer pageSize = 5;

        Test.startTest();
        PaginationState state = new PaginationState(offset, pageSize, null);
        Test.stopTest();

        System.assertEquals(offset, state.getOffset());
        System.assertEquals(pageSize, state.getPageSize());
        System.assertNotEquals(null, state.getAllCustomData(), 'Custom data map should be initialized.');
        System.assertEquals(0, state.getAllCustomData().size(), 'Custom data should be empty when passed null.');
    }

    @IsTest
    static void testSetAndGetCustomData() {
        PaginationState state = new PaginationState(0, 10);
        String key = 'cursor';
        String value = 'aBcDeFgH';

        Test.startTest();
        state.setCustomData(key, value);
        Test.stopTest();

        System.assertEquals(true, state.hasCustomData(key), 'Should have custom data for key.');
        System.assertEquals(value, state.getCustomData(key), 'Custom data value should match.');
        System.assertEquals(false, state.hasCustomData('nonExistent'), 'Should not have non-existent key.');
        System.assertEquals(null, state.getCustomData('nonExistent'), 'Getting non-existent key should return null.');

        Map<String, Object> allData = state.getAllCustomData();
        System.assertEquals(1, allData.size());
        System.assertEquals(value, allData.get(key));

        // Test immutability of getAllCustomData
        allData.put('newKey', 'newValue');
        System.assertEquals(1, state.getAllCustomData().size(), 'Internal data should not be modified.');
    }

    @IsTest
    static void testJsonSerializationDeserialization() {
        Map<String, Object> custom = new Map<String, Object>{
            'token' => '12345-abcde',
            'pageNumber' => 3
        };
        PaginationState originalState = new PaginationState(200, 50, custom);

        Test.startTest();
        String jsonStr = originalState.toJson();
        PaginationState deserializedState = PaginationState.fromJson(jsonStr);
        Test.stopTest();

        System.assertNotEquals(null, jsonStr, 'JSON string should not be null.');
        System.assertNotEquals(null, deserializedState, 'Deserialized state should not be null.');
        System.assertEquals(originalState.getOffset(), deserializedState.getOffset(), 'Offset should match after deserialization.');
        System.assertEquals(originalState.getPageSize(), deserializedState.getPageSize(), 'Page size should match after deserialization.');
        System.assertEquals(originalState.getAllCustomData(), deserializedState.getAllCustomData(), 'Custom data should match after deserialization.');
        System.assertEquals('12345-abcde', deserializedState.getCustomData('token'));
        System.assertEquals(3, ((Decimal)deserializedState.getCustomData('pageNumber')).intValue());
    }

    @IsTest
    static void testJsonWithoutCustomData() {
        PaginationState originalState = new PaginationState(10, 10);

        Test.startTest();
        String jsonStr = originalState.toJson();
        PaginationState deserializedState = PaginationState.fromJson(jsonStr);
        Test.stopTest();

        System.assertNotEquals(null, deserializedState);
        System.assertEquals(10, deserializedState.getOffset());
        System.assertEquals(10, deserializedState.getPageSize());
        System.assertEquals(0, deserializedState.getAllCustomData().size(), 'Custom data should be empty.');
    }

    @IsTest
    static void testCopy() {
        Map<String, Object> custom = new Map<String, Object>{'status' => 'active'};
        PaginationState originalState = new PaginationState(10, 5, custom);

        Test.startTest();
        PaginationState copiedState = originalState.copy();
        Test.stopTest();

        System.assertNotEquals(originalState, copiedState, 'Copied state should be a different instance.');
        System.assertEquals(originalState.getOffset(), copiedState.getOffset(), 'Offset should match in copy.');
        System.assertEquals(originalState.getPageSize(), copiedState.getPageSize(), 'Page size should match in copy.');
        System.assertEquals(originalState.getAllCustomData(), copiedState.getAllCustomData(), 'Custom data should match in copy.');

        // Modify original state's custom data to test deep copy
        originalState.setCustomData('newKey', 'newValue');
        System.assertEquals(1, copiedState.getAllCustomData().size(), 'Copied custom data should not be affected by changes to original.');
        System.assertEquals('active', copiedState.getCustomData('status'));

        // Modify copied state's custom data
        copiedState.setCustomData('copiedKey', 'copiedValue');
        System.assertEquals(2, originalState.getAllCustomData().size(), 'Original custom data should not be affected by changes to copy.');
        System.assertEquals(true, originalState.hasCustomData('newKey'));
        System.assertEquals(false, originalState.hasCustomData('copiedKey'));
    }
}
