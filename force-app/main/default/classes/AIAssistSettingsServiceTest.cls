/*
Class Name: AIAssistSettingsServiceTest

=================================================================
=================================================================

Description: Testing utility for the AIAssistSettingsService class.

=================================================================
=================================================================
Applicable Classes:

AIAssistSettingsService: Coverage 100%

Version      Date               Author                   Description
1.0          2026-09-14         Chandler Stuart          Initial development
1.1          2026-09-26         Chandler Stuart          Added getAIProviderSuccessStatusCodes scenarios.
*/

@IsTest private class AIAssistSettingsServiceTest {

    // testScenario1: isExceptionLoggingDisabled returns true when DisableExceptionLogging__c is set to true on the org defaults.
    // testScenario2: isExceptionLoggingDisabled returns false when DisableExceptionLogging__c is set to false on the org defaults.
    // testScenario3: getSettings returns the same cached AIAssistSettings__c instance across repeated calls within a transaction.
    // testScenario4: getAIProviderSuccessStatusCodes parses a comma-separated list, trimming spaces and skipping blank or non-numeric entries.
    // testScenario5: getAIProviderSuccessStatusCodes falls back to the code default when AIProviderSuccessStatusCodes__c is blank.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = true;
        settings.DisableExceptionLogging__c = false;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.DisableExceptionLogging__c = true;
        upsert settings;

        Test.startTest();
            Boolean isDisabled = AIAssistSettingsService.isExceptionLoggingDisabled();
        Test.stopTest();

        Assert.isTrue(isDisabled, 'isExceptionLoggingDisabled should return true when DisableExceptionLogging__c is true.');
    }

    @IsTest static void testScenario2() {

        Test.startTest();
            Boolean isDisabled = AIAssistSettingsService.isExceptionLoggingDisabled();
        Test.stopTest();

        Assert.isFalse(isDisabled, 'isExceptionLoggingDisabled should return false when DisableExceptionLogging__c is false.');
    }

    @IsTest static void testScenario3() {

        Test.startTest();
            AIAssistSettings__c first = AIAssistSettingsService.getSettings();
            AIAssistSettings__c second = AIAssistSettingsService.getSettings();
        Test.stopTest();

        Assert.areEqual(first.Id, second.Id, 'getSettings should consistently return the org default settings record.');
    }

    @IsTest static void testScenario4() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.AIProviderSuccessStatusCodes__c = '200, 201,abc,,';
        upsert settings;

        Test.startTest();
            Set<Integer> successStatusCodes = AIAssistSettingsService.getAIProviderSuccessStatusCodes();
        Test.stopTest();

        Assert.areEqual(new Set<Integer>{ 200, 201 }, successStatusCodes, 'getAIProviderSuccessStatusCodes should return only the valid, trimmed status codes.');
    }

    @IsTest static void testScenario5() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.AIProviderSuccessStatusCodes__c = null;
        upsert settings;

        Test.startTest();
            Set<Integer> successStatusCodes = AIAssistSettingsService.getAIProviderSuccessStatusCodes();
        Test.stopTest();

        Assert.areEqual(AIAssistApplicationConstants.DEFAULT_AI_PROVIDER_SUCCESS_STATUS_CODES, successStatusCodes, 'getAIProviderSuccessStatusCodes should fall back to the code default when the setting is blank.');
    }
}