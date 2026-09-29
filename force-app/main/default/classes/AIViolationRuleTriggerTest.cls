/*
Class Name: AIViolationRuleTriggerTest

=================================================================
=================================================================

Description: Testing utility for the AI Violation Rule Trigger.

=================================================================
=================================================================
Applicable Classes:

AIViolationRuleTrigger: Coverage 100%
AIViolationRuleTriggerHandler: Coverage 82%

Version      Date               Author                   Description
1.0          2026-09-10         Chandler Stuart          Initial development
*/

@IsTest private class AIViolationRuleTriggerTest {

    // testScenario1: Bulk inserting active AIViolationRule__c records with unique Signal Tags generates each record's PublicId__c and DeveloperName__c and inserts cleanly.
    // testScenario2: Inserting two active AIViolationRule__c records with the same Signal Tag in one save raises a validation error on SignalTag__c and rolls back the insert.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, true)[0];
        List<AIViolationRule__c> rules = AIAssistTestDataFactory.createAIViolationRules(agent.Id, 2, 'AIViolationRuleTriggerTest_Unique_', false);

        Test.startTest();
            insert rules;
        Test.stopTest();

        List<AIViolationRule__c> inserted = [SELECT PublicId__c, DeveloperName__c FROM AIViolationRule__c WHERE Id IN :rules];

        Assert.areEqual(2, inserted.size(), 'Both bulk-inserted rules should be created.');

        for (AIViolationRule__c rule : inserted) {
            Assert.isNotNull(rule.PublicId__c, 'PublicId__c should be generated on insert.');
            Assert.isNotNull(rule.DeveloperName__c, 'DeveloperName__c should be generated on insert.');
        }
    }

    @IsTest static void testScenario2() {

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, true)[0];
        List<AIViolationRule__c> duplicateRules = AIAssistTestDataFactory.createAIViolationRules(agent.Id, 2, 'AIViolationRuleTriggerTest_Duplicate_', false);
        duplicateRules[1].SignalTag__c = duplicateRules[0].SignalTag__c; // Force a duplicate Signal Tag within the same save.

        Test.startTest();
            try {
                insert duplicateRules;
                Assert.fail('Inserting two active rules with the same Signal Tag should have thrown.');
            } catch (DmlException e) {
                Assert.isTrue(e.getMessage().contains('is used by more than one AI Violation Rule in this save'), 'Error should explain the duplicate Signal Tag within this save.');
            }
        Test.stopTest();
    }
}