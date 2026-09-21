/*
Class Name: AiDataSourceResultProcessorTest

=================================================================
=================================================================

Description: Testing utility for AiDataSourceResultProcessor.

=================================================================
=================================================================
Applicable Classes:

AiDataSourceResultProcessor: Coverage 100%

Version      Date               Author                   Description
1.0          2026-09-21         Chandler Stuart          Initial development
*/

@IsTest private class AiDataSourceResultProcessorTest {

    // testScenario1: process() handles a null records list safely, and a non-PII field's value passes through a flattened record unmasked.
    // testScenario2: A PII field's value is pseudonymized before being flattened, and the masking is recorded against the given conversation.
    // testScenario3: Parent lookup fields and child subquery relationships are both flattened into nested Map/List structures.
    // testScenario4: USER_MODE omits a field the running user has no FLS access to, while SYSTEM_MODE still includes it.
    // testScenario5: A single batch containing multiple different SObjectTypes is flattened correctly for every record, proving the per-type bulk describe grouping handles a mixed batch.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = true;
        settings.DisableExceptionLogging__c = false;
        upsert settings;
    }

    private static Id createConversationId() {
        Id agentId = AIAssistTestDataFactory.createAIAgents(1, true)[0].Id;
        return AIAssistTestDataFactory.createAIConversations(agentId, 1, true)[0].Id;
    }

    @IsTest static void testScenario1() {

        Account testAccount = AIAssistTestDataFactory.createAccounts(1, true)[0];
        Account queriedAccount = [SELECT Id, Name FROM Account WHERE Id = :testAccount.Id];

        Test.startTest();
            List<Object> nullResults = AiDataSourceResultProcessor.process(null, null);
            List<Object> results = AiDataSourceResultProcessor.process(new List<SObject>{ queriedAccount }, null);
        Test.stopTest();

        Assert.isTrue(nullResults.isEmpty(), 'A null records list should return an empty list rather than throwing.');

        Map<String, Object> flattenedAccount = (Map<String, Object>) results[0];
        Assert.areEqual(testAccount.Name, flattenedAccount.get('Name'), 'A non-PII field\'s value should pass through the flattened record unmasked.');
    }

    @IsTest static void testScenario2() {

        AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(1, 'Account', true)[0];
        AIAssistTestDataFactory.createAIPIIFieldMetadata(registry.Id, 'Account', 'Name', 'Name', true, AIAssistApplicationConstants.PII_FIELD_TYPE_NAME, true);

        AIPiiPseudonymizationService.maskingRuleByFieldType = new Map<String, AIPiiDataMaskingRule__mdt>{
            AIAssistApplicationConstants.PII_FIELD_TYPE_NAME => new AIPiiDataMaskingRule__mdt(
                Strategy__c = AIAssistApplicationConstants.PII_MASKING_STRATEGY_SUBSTITUTE_FROM_LIST,
                SubstituteValues__c = 'Alex Rivera,Jordan Chen',
                Active__c = true
            )
        };

        Id conversationId = createConversationId();
        Account testAccount = AIAssistTestDataFactory.createAccounts(1, true)[0];
        Account queriedAccount = [SELECT Id, Name FROM Account WHERE Id = :testAccount.Id];

        Test.startTest();
            AiDataSourceResultProcessor.setCurrentConversationId(conversationId);
            List<Object> results = AiDataSourceResultProcessor.process(new List<SObject>{ queriedAccount }, null);
        Test.stopTest();

        Map<String, Object> flattenedAccount = (Map<String, Object>) results[0];
        String maskedName = (String) flattenedAccount.get('Name');

        Assert.areNotEqual(testAccount.Name, maskedName, 'A PII field\'s value should be masked rather than passed through as-is.');
        Assert.isTrue(new Set<String>{ 'Alex Rivera', 'Jordan Chen' }.contains(maskedName), 'The masked value should come from the Masking Rule\'s substitute list.');

        Integer mappingCount = [SELECT COUNT() FROM AIPIIMapping__c WHERE AIConversation__c = :conversationId];
        Assert.areEqual(1, mappingCount, 'The masking should be recorded against the given conversation\'s mapping.');
    }

    @IsTest static void testScenario3() {

        Account parentAccount = AIAssistTestDataFactory.createAccounts(1, true)[0];
        insert new Contact(LastName = 'Test Contact', AccountId = parentAccount.Id);

        Contact queriedContact = [SELECT Id, Name, Account.Name FROM Contact WHERE AccountId = :parentAccount.Id LIMIT 1];
        Account queriedAccountWithChildren = [SELECT Id, Name, (SELECT Id, Name FROM Contacts) FROM Account WHERE Id = :parentAccount.Id];

        Test.startTest();
            List<Object> parentResults = AiDataSourceResultProcessor.process(new List<SObject>{ queriedContact }, null);
            List<Object> childResults = AiDataSourceResultProcessor.process(new List<SObject>{ queriedAccountWithChildren }, null);
        Test.stopTest();

        Map<String, Object> flattenedContact = (Map<String, Object>) parentResults[0];
        Map<String, Object> flattenedParentAccount = (Map<String, Object>) flattenedContact.get('Account');
        Assert.areEqual(parentAccount.Name, flattenedParentAccount.get('Name'), 'A parent lookup field should be flattened into a nested Map carrying the parent\'s values.');

        Map<String, Object> flattenedAccountWithChildren = (Map<String, Object>) childResults[0];
        List<Object> flattenedContacts = (List<Object>) flattenedAccountWithChildren.get('Contacts');
        Assert.areEqual(1, flattenedContacts.size(), 'A child subquery relationship should be flattened into a nested List of the child records.');
        Assert.areEqual('Test Contact', ((Map<String, Object>) flattenedContacts[0]).get('LastName'), 'The flattened child record should carry the child\'s own field values.');
    }

    @IsTest static void testScenario4() {

        // SOQL Source Type, not Apex - AIDataSourceTriggerHandler only validates ApexClassName__c against IAIDataSourceExecutor for Apex-type records, and this field just needs some value populated to test FLS against.
        AIDataSource__c testDataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id FROM Account', false)[0];
        testDataSource.ApexClassName__c = 'AIAssistApplicationConstants';
        insert testDataSource;

        AIDataSource__c queriedDataSource = [SELECT Id, ApexClassName__c FROM AIDataSource__c WHERE Id = :testDataSource.Id];

        User bareUser = AIAssistTestDataFactory.createStandardUsers(null, 1, true)[0]; // No AIAssistUserType__c - no AI Assist Permission Set is auto-assigned, so this user has no access at all to AIDataSource__c.

        List<Object> userModeResults;
        List<Object> systemModeResults;

        Test.startTest();
            System.runAs(bareUser) {
                userModeResults = AiDataSourceResultProcessor.process(new List<SObject>{ queriedDataSource }, AccessLevel.USER_MODE);
                systemModeResults = AiDataSourceResultProcessor.process(new List<SObject>{ queriedDataSource }, AccessLevel.SYSTEM_MODE);
            }
        Test.stopTest();

        Map<String, Object> userModeFlattened = (Map<String, Object>) userModeResults[0];
        Map<String, Object> systemModeFlattened = (Map<String, Object>) systemModeResults[0];

        Assert.isFalse(userModeFlattened.containsKey('ApexClassName__c'), 'USER_MODE should omit a field the running user has no FLS access to.');
        Assert.isTrue(systemModeFlattened.containsKey('ApexClassName__c'), 'SYSTEM_MODE should include the field regardless of the running user\'s FLS.');
    }

    @IsTest static void testScenario5() {

        Account testAccount = AIAssistTestDataFactory.createAccounts(1, true)[0];
        insert new Contact(LastName = 'Mixed Batch Contact', AccountId = testAccount.Id);

        Account queriedAccount = [SELECT Id, Name FROM Account WHERE Id = :testAccount.Id];
        Contact queriedContact = [SELECT Id, LastName FROM Contact WHERE AccountId = :testAccount.Id LIMIT 1];

        Test.startTest();
            List<Object> results = AiDataSourceResultProcessor.process(new List<SObject>{ queriedAccount, queriedContact }, null);
        Test.stopTest();

        Assert.areEqual(2, results.size(), 'Every record in a mixed-type batch should be flattened.');
        Assert.areEqual(testAccount.Name, ((Map<String, Object>) results[0]).get('Name'), 'The Account in the mixed batch should be flattened correctly.');
        Assert.areEqual('Mixed Batch Contact', ((Map<String, Object>) results[1]).get('LastName'), 'The Contact in the mixed batch should be flattened correctly.');
    }
}