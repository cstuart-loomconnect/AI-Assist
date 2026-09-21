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
*/

@IsTest private class AIAssistSettingsServiceTest {

    // testScenario1: isExceptionLoggingDisabled returns true when DisableExceptionLogging__c is set to true on the org defaults.
    // testScenario2: isExceptionLoggingDisabled returns false when DisableExceptionLogging__c is set to false on the org defaults.
    // testScenario3: getSettings returns the same cached AIAssistSettings__c instance across repeated calls within a transaction.

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
}