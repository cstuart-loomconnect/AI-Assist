/*
Class Name: AiSoqlTemplateRunnerTest

=================================================================
=================================================================

Description: Testing utility for AiSoqlTemplateRunner.

=================================================================
=================================================================
Applicable Classes:

AiSoqlTemplateRunner: Coverage 100%

Version      Date               Author                   Description
1.0          2026-09-21         Chandler Stuart          Initial development
*/

@IsTest private class AiSoqlTemplateRunnerTest {

    // testScenario1: A blank SOQL template returns an empty list rather than running any query.
    // testScenario2: A valid template runs with its bind values substituted in, and returns the matching records.
    // testScenario3: A null bindValues Map is handled gracefully for a template with no bind variables.
    // testScenario4: A null AccessLevel defaults to USER_MODE - querying a field the running user has no FLS access to fails safe to an empty list, while explicit SYSTEM_MODE still returns the data.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = true;
        settings.DisableExceptionLogging__c = false;
        upsert settings;

        AIAssistTestDataFactory.createAccounts(1, true);
    }

    @IsTest static void testScenario1() {

        Test.startTest();
            List<SObject> blankResults = AiSoqlTemplateRunner.run('', new Map<String, Object>(), null);
            List<SObject> nullResults = AiSoqlTemplateRunner.run(null, new Map<String, Object>(), null);
        Test.stopTest();

        Assert.isTrue(blankResults.isEmpty(), 'A blank SOQL template should return an empty list.');
        Assert.isTrue(nullResults.isEmpty(), 'A null SOQL template should return an empty list.');
    }

    @IsTest static void testScenario2() {

        Account testAccount = [SELECT Id, Name FROM Account LIMIT 1];

        Test.startTest();
            List<SObject> results = AiSoqlTemplateRunner.run('SELECT Id, Name FROM Account WHERE Id = :recordId', new Map<String, Object>{ 'recordId' => testAccount.Id }, null);
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Should return the one Account matched by the bound recordId.');
        Assert.areEqual(testAccount.Name, ((Account) results[0]).Name, 'The returned record should carry the real field values.');
    }

    @IsTest static void testScenario3() {

        Test.startTest();
            List<SObject> results = AiSoqlTemplateRunner.run('SELECT Id FROM Account', null, null); // null bindValues, and the template has no bind variables to satisfy.
        Test.stopTest();

        Assert.isFalse(results.isEmpty(), 'A null bindValues Map should be handled gracefully rather than throwing, for a template with no binds.');
    }

    @IsTest static void testScenario4() {

        AIDataSource__c testDataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id FROM Account', false)[0];
        testDataSource.ApexClassName__c = 'AIAssistApplicationConstants'; // A field this test's bare user will have no FLS access to - the value itself is irrelevant.
        insert testDataSource;

        User bareUser = AIAssistTestDataFactory.createStandardUsers(null, 1, true)[0]; // No AIAssistUserType__c - no AI Assist Permission Set is auto-assigned, so this user has no access at all to AIDataSource__c.

        List<SObject> userModeResults;
        List<SObject> systemModeResults;

        Test.startTest();
            System.runAs(bareUser) {
                userModeResults = AiSoqlTemplateRunner.run('SELECT Id, ApexClassName__c FROM AIDataSource__c WHERE Id = :dataSourceId', new Map<String, Object>{ 'dataSourceId' => testDataSource.Id }, null);
                systemModeResults = AiSoqlTemplateRunner.run('SELECT Id, ApexClassName__c FROM AIDataSource__c WHERE Id = :dataSourceId', new Map<String, Object>{ 'dataSourceId' => testDataSource.Id }, AccessLevel.SYSTEM_MODE);
            }
        Test.stopTest();

        Assert.isTrue(userModeResults.isEmpty(), 'A null AccessLevel should default to USER_MODE, and querying a field with no FLS access should fail safe to an empty list rather than throwing.');
        Assert.areEqual(1, systemModeResults.size(), 'Explicit SYSTEM_MODE should bypass FLS and still return the record.');
    }
}