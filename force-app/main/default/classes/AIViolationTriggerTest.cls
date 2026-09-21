/*
Class Name: AIViolationTriggerTest

=================================================================
=================================================================

Description: Testing utility for the AI Violation Trigger.

=================================================================
=================================================================
Applicable Classes:

AIViolationTrigger: Coverage 100%
AIViolationTriggerHandler: Coverage 85%

Version      Date               Author                   Description
1.0          2026-09-10         Chandler Stuart          Initial development
*/

@IsTest private class AIViolationTriggerTest {

    // testScenario1: Bulk inserting AIViolation__c records against the same AIViolationRule__c increments TriggerCount__c by the batch size and sets LastTriggeredDate__c to today.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = true;
        settings.DisableExceptionLogging__c = false;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, true)[0];
        AIViolationRule__c rule = AIAssistTestDataFactory.createAIViolationRules(agent.Id, 1, 'AIViolationTriggerTest_', true)[0];

        Test.startTest();
            AIAssistTestDataFactory.createAIViolations(rule.Id, 3, true);
        Test.stopTest();

        AIViolationRule__c updatedRule = [SELECT TriggerCount__c, LastTriggeredDate__c FROM AIViolationRule__c WHERE Id = :rule.Id];

        Assert.areEqual(3, updatedRule.TriggerCount__c, 'TriggerCount__c should increment by the number of violations inserted.');
        Assert.areEqual(Date.today(), updatedRule.LastTriggeredDate__c, 'LastTriggeredDate__c should be set to today.');
    }
}