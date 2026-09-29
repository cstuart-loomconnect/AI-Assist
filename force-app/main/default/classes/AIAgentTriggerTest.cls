/*
Class Name: AIAgentTriggerTest

=================================================================
=================================================================

Description: Testing utility for the AI Agent Trigger.

=================================================================
=================================================================
Applicable Classes:

AIAgentTrigger: Coverage 100%
AIAgentTriggerHandler: Coverage 100%

Version      Date           Author                   Description
1.0          2026-09-07     Chandler Stuart          Initial development
*/

@IsTest private class AIAgentTriggerTest {

    // testScenario1: Inserting an AIAgent__c generates its PublicId__c and DeveloperName__c from Name.
    // testScenario2: When AIAgentTriggerHandler.isTestCustomExceptionThrown forces an exception, it's caught and logged rather than blocking the insert, and no fields get generated.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        AIAgent__c agent = new AIAgent__c(Name = 'Mortgage Error Diagnostician');

        Test.startTest();
            insert agent;
        Test.stopTest();

        AIAgent__c inserted = [SELECT PublicId__c, DeveloperName__c FROM AIAgent__c WHERE Id = :agent.Id];

        Assert.isNotNull(inserted.PublicId__c, 'PublicId__c should be generated on insert.');
        Assert.areEqual('Mortgage_Error_Diagnostician', inserted.DeveloperName__c, 'DeveloperName__c should be derived from Name.');
    }

    @IsTest static void testScenario2() {

        AIAgentTriggerHandler.isTestCustomExceptionThrown = true;

        AIAgent__c agent = new AIAgent__c(Name = 'Mortgage Error Diagnostician');

        Test.startTest();
            insert agent;
        Test.stopTest();

        AIAgent__c inserted = [SELECT PublicId__c, DeveloperName__c FROM AIAgent__c WHERE Id = :agent.Id];

        Assert.isNull(inserted.PublicId__c, 'PublicId__c should not be generated when the handler throws.');
        Assert.isNull(inserted.DeveloperName__c, 'DeveloperName__c should not be generated when the handler throws.');

        Integer platformLogCount = [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'AIAgentTriggerHandler' AND MethodName__c = 'handleBeforeInsert'];
        Assert.areEqual(1, platformLogCount, 'The forced exception should be logged to AIPlatformLog__c.');
    }
}