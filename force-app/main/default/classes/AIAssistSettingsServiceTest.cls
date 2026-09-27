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
1.1          2026-09-26         Chandler Stuart          Added getSuccessStatusCodes scenarios.
1.2          2026-09-27         Chandler Stuart          Added getRetryStatusCodes and getCalloutTimeoutMilliseconds scenarios.
1.3          2026-09-27         Chandler Stuart          Added getDefaultMaxToolCallingIterations and getMaxToolCallingIterationsCap scenarios.
1.4          2026-09-27         Chandler Stuart          Added getMaxToolCallsPerIteration and getProcessingLockMinutes scenarios.
*/

@IsTest private class AIAssistSettingsServiceTest {

    // testScenario1: isExceptionLoggingDisabled returns true when DisableExceptionLogging__c is set to true on the org defaults.
    // testScenario2: isExceptionLoggingDisabled returns false when DisableExceptionLogging__c is set to false on the org defaults.
    // testScenario3: getSettings returns the same cached AIAssistSettings__c instance across repeated calls within a transaction.
    // testScenario4: getSuccessStatusCodes parses a comma-separated list, trimming spaces and skipping blank or non-numeric entries.
    // testScenario5: getSuccessStatusCodes falls back to the code default when AIProviderSuccessStatusCodes__c is blank.
    // testScenario6: getRetryStatusCodes parses a comma-separated list, trimming spaces and skipping blank or non-numeric entries, and caches the result.
    // testScenario7: getCalloutTimeoutMilliseconds returns CalloutTimeoutMilliseconds__c when set, and throws AIAssistSettingsServiceException when it is blank or zero.
    // testScenario8: getDefaultMaxToolCallingIterations/getMaxToolCallingIterationsCap return the configured values when set, and the AIAssistApplicationConstants defaults when blank or below 1.
    // testScenario9: getMaxToolCallsPerIteration/getProcessingLockMinutes return the configured values when set, and the AIAssistApplicationConstants defaults when blank or below 1.

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
            Set<Integer> successStatusCodes = AIAssistSettingsService.getSuccessStatusCodes();
        Test.stopTest();

        Assert.areEqual(new Set<Integer>{ 200, 201 }, successStatusCodes, 'getSuccessStatusCodes should return only the valid, trimmed status codes.');
    }

    @IsTest static void testScenario5() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.AIProviderSuccessStatusCodes__c = null;
        upsert settings;

        Test.startTest();
            Set<Integer> successStatusCodes = AIAssistSettingsService.getSuccessStatusCodes();
        Test.stopTest();

        Assert.areEqual(AIAssistApplicationConstants.DEFAULT_AI_PROVIDER_SUCCESS_STATUS_CODES, successStatusCodes, 'getSuccessStatusCodes should fall back to the code default when the setting is blank.');
    }

    @IsTest static void testScenario6() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.RetryableStatusCodes__c = '429, 503,abc,,';
        upsert settings;

        Test.startTest();
            Set<Integer> retryableStatusCodes = AIAssistSettingsService.getRetryStatusCodes();
            Set<Integer> cachedRetryableStatusCodes = AIAssistSettingsService.getRetryStatusCodes();
        Test.stopTest();

        Assert.areEqual(new Set<Integer>{ 429, 503 }, retryableStatusCodes, 'getRetryStatusCodes should return only the valid, trimmed status codes.');
        Assert.isTrue(retryableStatusCodes === cachedRetryableStatusCodes, 'getRetryStatusCodes should return the cached set on later calls.');
    }

    @IsTest static void testScenario7() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.CalloutTimeoutMilliseconds__c = 60000;
        upsert settings;

        Test.startTest();
            Integer configuredTimeoutMillis = AIAssistSettingsService.getCalloutTimeoutMilliseconds();

            for (Decimal invalidValue : new List<Decimal>{ null, 0 }) {
                AIAssistSettingsService.getSettings().CalloutTimeoutMilliseconds__c = invalidValue;
                try {
                    AIAssistSettingsService.getCalloutTimeoutMilliseconds();
                    Assert.fail('A ' + invalidValue + ' Callout Timeout Milliseconds should have thrown.');
                } catch (AIAssistSettingsService.AIAssistSettingsServiceException ex) {
                    Assert.areEqual('AI Assist Settings has no Callout Timeout Milliseconds configured.', ex.getMessage(), 'Error should explain the timeout is not configured.');
                }
            }
        Test.stopTest();

        Assert.areEqual(60000, configuredTimeoutMillis, 'getCalloutTimeoutMilliseconds should return the configured value.');
    }

    @IsTest static void testScenario8() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.DefaultMaxToolCallingIterations__c = 3;
        settings.MaxToolCallingIterationsCap__c = 10;
        upsert settings;

        Test.startTest();
            Integer configuredDefault = AIAssistSettingsService.getDefaultMaxToolCallingIterations();
            Integer configuredCap = AIAssistSettingsService.getMaxToolCallingIterationsCap();

            // Clear the cached values so the blank/zero settings below are re-read.
            AIAssistSettings__c cachedSettings = AIAssistSettingsService.getSettings();
            cachedSettings.DefaultMaxToolCallingIterations__c = null;
            cachedSettings.MaxToolCallingIterationsCap__c = 0;
            AIAssistSettingsService.cachedDefaultMaxToolCallingIterations = null;
            AIAssistSettingsService.cachedMaxToolCallingIterationsCap = null;

            Integer fallbackDefault = AIAssistSettingsService.getDefaultMaxToolCallingIterations();
            Integer fallbackCap = AIAssistSettingsService.getMaxToolCallingIterationsCap();
        Test.stopTest();

        Assert.areEqual(3, configuredDefault, 'getDefaultMaxToolCallingIterations should return the configured value.');
        Assert.areEqual(10, configuredCap, 'getMaxToolCallingIterationsCap should return the configured value.');
        Assert.areEqual(AIAssistApplicationConstants.DEFAULT_MAX_TOOL_CALLING_ITERATIONS, fallbackDefault, 'A blank default should fall back to the code default.');
        Assert.areEqual(AIAssistApplicationConstants.DEFAULT_MAX_TOOL_CALLING_ITERATIONS_CAP, fallbackCap, 'A cap below 1 should fall back to the code default.');
    }

    @IsTest static void testScenario9() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.MaxToolCallsPerIteration__c = 3;
        settings.ProcessingLockMinutes__c = 15;
        upsert settings;

        Test.startTest();
            Integer configuredMaxToolCalls = AIAssistSettingsService.getMaxToolCallsPerIteration();
            Integer configuredLockMinutes = AIAssistSettingsService.getProcessingLockMinutes();

            // Clear the cached values so the blank/zero settings below are re-read.
            AIAssistSettings__c cachedSettings = AIAssistSettingsService.getSettings();
            cachedSettings.MaxToolCallsPerIteration__c = null;
            cachedSettings.ProcessingLockMinutes__c = 0;
            AIAssistSettingsService.cachedMaxToolCallsPerIteration = null;
            AIAssistSettingsService.cachedProcessingLockMinutes = null;

            Integer fallbackMaxToolCalls = AIAssistSettingsService.getMaxToolCallsPerIteration();
            Integer fallbackLockMinutes = AIAssistSettingsService.getProcessingLockMinutes();
        Test.stopTest();

        Assert.areEqual(3, configuredMaxToolCalls, 'getMaxToolCallsPerIteration should return the configured value.');
        Assert.areEqual(15, configuredLockMinutes, 'getProcessingLockMinutes should return the configured value.');
        Assert.areEqual(AIAssistApplicationConstants.DEFAULT_MAX_TOOL_CALLS_PER_ITERATION, fallbackMaxToolCalls, 'A blank value should fall back to the code default.');
        Assert.areEqual(AIAssistApplicationConstants.DEFAULT_PROCESSING_LOCK_MINUTES, fallbackLockMinutes, 'A value below 1 should fall back to the code default.');
    }
}