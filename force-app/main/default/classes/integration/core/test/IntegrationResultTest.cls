@IsTest
private class IntegrationResultTest {

    @IsTest
    static void testCreateSuccess() {
        String successMsg = 'Operation successful';

        Test.startTest();
        IntegrationResult result = IntegrationResult.createSuccess(successMsg);
        Test.stopTest();

        System.assertEquals(true, result.isSuccess, 'Result should be success.');
        System.assertEquals(successMsg, result.message, 'Success message should match.');
        System.assertEquals(null, result.errorDetails, 'Error details should be null for success.');
        System.assertEquals(0, result.processedRecords.size(), 'Processed records should be empty initially.');
        System.assertEquals(0, result.additionalDetails.size(), 'Additional details should be empty initially.');
    }

    @IsTest
    static void testCreateError() {
        String errorMsg = 'Operation failed';
        String details = 'Resource not found';

        Test.startTest();
        IntegrationResult result = IntegrationResult.createError(errorMsg, details);
        Test.stopTest();

        System.assertEquals(false, result.isSuccess, 'Result should be error.');
        System.assertEquals(errorMsg, result.message, 'Error message should match.');
        System.assertEquals(details, result.errorDetails, 'Error details should match.');
        System.assertEquals(0, result.processedRecords.size(), 'Processed records should be empty initially.');
        System.assertEquals(0, result.additionalDetails.size(), 'Additional details should be empty initially.');
    }

    @IsTest
    static void testWithProcessedRecords() {
        List<Account> dummyAccounts = new List<Account>();
        dummyAccounts.add(new Account(Name='Dummy1'));
        dummyAccounts.add(new Account(Name='Dummy2'));
        dummyAccounts.add(new Account(Name='Dummy3'));

        String jsonAccounts = JSON.serialize(dummyAccounts);
        List<Account> accountsWithIds = (List<Account>)JSON.deserialize(jsonAccounts, List<Account>.class);

        List<Id> recordIds = new List<Id>();
        for(Account acc : accountsWithIds) {
            recordIds.add(acc.Id);
        }
        System.assertEquals(3, recordIds.size(), 'Should have 3 generated IDs.');

        IntegrationResult result = IntegrationResult.createSuccess('Success');

        Test.startTest();
        result.withProcessedRecords(recordIds);
        Test.stopTest();

        System.assertEquals(3, result.processedRecords.size(), 'Should contain 3 processed records.');
        System.assertEquals(recordIds, result.processedRecords, 'Processed record IDs should match.');
    }

    @IsTest
    static void testWithAdditionalDetail() {
        String key = 'customData';
        Integer value = 123;

        IntegrationResult result = IntegrationResult.createSuccess('Success');

        Test.startTest();
        result.withAdditionalDetail(key, value);
        Test.stopTest();

        System.assertEquals(1, result.additionalDetails.size(), 'Should contain 1 additional detail.');
        System.assertEquals(true, result.additionalDetails.containsKey(key), 'Should contain the specified key.');
        System.assertEquals(value, result.additionalDetails.get(key), 'Detail value should match.');
    }

    @IsTest
    static void testChainingMethods() {
        String key1 = 'info';
        String value1 = 'More data';
        String key2 = 'count';
        Integer value2 = 5;

        List<Contact> dummyContacts = new List<Contact>();
        dummyContacts.add(new Contact(LastName='DummyA'));
        dummyContacts.add(new Contact(LastName='DummyB'));
        String jsonContacts = JSON.serialize(dummyContacts);
        List<Contact> contactsWithIds = (List<Contact>)JSON.deserialize(jsonContacts, List<Contact>.class);

        List<Id> recordIds = new List<Id>();
        for(Contact con : contactsWithIds) {
            recordIds.add(con.Id);
        }
        System.assertEquals(2, recordIds.size(), 'Should have 2 generated IDs.');

        Test.startTest();
        IntegrationResult result = IntegrationResult.createSuccess('Chained Success')
                                        .withProcessedRecords(recordIds)
                                        .withAdditionalDetail(key1, value1)
                                        .withAdditionalDetail(key2, value2);
        Test.stopTest();

        System.assertEquals(true, result.isSuccess);
        System.assertEquals('Chained Success', result.message);
        System.assertEquals(recordIds, result.processedRecords);
        System.assertEquals(2, result.additionalDetails.size());
        System.assertEquals(value1, result.additionalDetails.get(key1));
        System.assertEquals(value2, result.additionalDetails.get(key2));
    }
}
