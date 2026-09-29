/*
Class Name: AIModelConfigurationTriggerTest

=================================================================
=================================================================

Description: Testing utility for the AI Model Configuration Trigger.

=================================================================
=================================================================
Applicable Classes:

AIModelConfigurationTrigger: Coverage 100%
AIModelConfigurationTriggerHandler: Coverage 100%

Version      Date               Author                   Description
1.0          2026-09-09         Chandler Stuart          Initial development
*/

@IsTest private class AIModelConfigurationTriggerTest {

    // testScenario1: Bulk inserting AIModelConfiguration__c records generates each record's PublicId__c.
    // testScenario2: When AIModelConfigurationTriggerHandler.isTestCustomExceptionThrown forces an exception, it's caught and logged rather than blocking the insert, and PublicId__c doesn't get generated.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        List<AIModelConfiguration__c> configurations = AIAssistTestDataFactory.createAIModelConfigurations(2, false);

        Test.startTest();
            insert configurations;
        Test.stopTest();

        List<AIModelConfiguration__c> inserted = [SELECT PublicId__c FROM AIModelConfiguration__c WHERE Id IN :configurations];

        Assert.areEqual(2, inserted.size(), 'Both bulk-inserted Model Configurations should be created.');

        for (AIModelConfiguration__c configuration : inserted) {
            Assert.isNotNull(configuration.PublicId__c, 'PublicId__c should be generated on insert.');
        }
    }

    @IsTest static void testScenario2() {

        AIModelConfigurationTriggerHandler.isTestCustomExceptionThrown = true;

        AIModelConfiguration__c configuration = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];

        Test.startTest();
            insert configuration;
        Test.stopTest();

        AIModelConfiguration__c inserted = [SELECT PublicId__c FROM AIModelConfiguration__c WHERE Id = :configuration.Id];

        Assert.isNull(inserted.PublicId__c, 'PublicId__c should not be generated when the handler throws.');

        Integer platformLogCount = [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'AIModelConfigurationTriggerHandler' AND MethodName__c = 'handleBeforeInsert'];
        Assert.areEqual(1, platformLogCount, 'The forced exception should be logged to AIPlatformLog__c.');
    }
}