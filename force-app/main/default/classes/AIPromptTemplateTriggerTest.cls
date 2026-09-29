/*
Class Name: AIPromptTemplateTriggerTest

=================================================================
=================================================================

Description: Testing utility for the AI Prompt Template Trigger.

=================================================================
=================================================================
Applicable Classes:

AIPromptTemplateTrigger: Coverage 100%
AIPromptTemplateTriggerHandler: Coverage 100%

Version      Date               Author                   Description
1.0          2026-09-10         Chandler Stuart          Initial development
*/

@IsTest private class AIPromptTemplateTriggerTest {

    // testScenario1: Bulk inserting AIPromptTemplate__c records generates each record's PublicId__c.
    // testScenario2: When AIPromptTemplateTriggerHandler.isTestCustomExceptionThrown forces an exception, it's caught and logged rather than blocking the insert, and PublicId__c doesn't get generated.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        List<AIPromptTemplate__c> templates = AIAssistTestDataFactory.createAIPromptTemplates(2, false);

        Test.startTest();
            insert templates;
        Test.stopTest();

        List<AIPromptTemplate__c> inserted = [SELECT PublicId__c FROM AIPromptTemplate__c WHERE Id IN :templates];

        Assert.areEqual(2, inserted.size(), 'Both bulk-inserted Prompt Templates should be created.');

        for (AIPromptTemplate__c template : inserted) {
            Assert.isNotNull(template.PublicId__c, 'PublicId__c should be generated on insert.');
        }
    }

    @IsTest static void testScenario2() {

        AIPromptTemplateTriggerHandler.isTestCustomExceptionThrown = true;

        AIPromptTemplate__c template = AIAssistTestDataFactory.createAIPromptTemplates(1, false)[0];

        Test.startTest();
            insert template;
        Test.stopTest();

        AIPromptTemplate__c inserted = [SELECT PublicId__c FROM AIPromptTemplate__c WHERE Id = :template.Id];

        Assert.isNull(inserted.PublicId__c, 'PublicId__c should not be generated when the handler throws.');

        Integer platformLogCount = [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'AIPromptTemplateTriggerHandler' AND MethodName__c = 'handleBeforeInsert'];
        Assert.areEqual(1, platformLogCount, 'The forced exception should be logged to AIPlatformLog__c.');
    }
}