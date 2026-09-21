/*
Class Name: AIViolationTriggerHandler

=================================================================
=================================================================

Description: Handler for managing AI Violation events related to AI Assist, performing
the business logic that runs on the AI Violation trigger.

=================================================================
=================================================================

Version      Date               Author                   Description
1.0          2026-09-06         Chandler Stuart          Initial development
*/

public without sharing class AIViolationTriggerHandler {

    private static Boolean isAfterInsertHandlerRunning = false;

    public static void handleAfterInsert(List<AIViolation__c> newViolations) {
        try {

            if (isAfterInsertHandlerRunning) return;
            isAfterInsertHandlerRunning = true;

            updateViolationRuleTriggerStats(newViolations);

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIViolationTriggerHandler', 'handleAfterInsert');
        }
    }

    // Increments TriggerCount__c and sets LastTriggeredDate__c to today on each related AIViolationRule__c.
    private static void updateViolationRuleTriggerStats(List<AIViolation__c> violations) {
        try {

            Map<Id, Integer> newViolationCountByRuleId = new Map<Id, Integer>();

            for (AIViolation__c violation : violations) {

                if (violation.AIViolationRule__c == null) continue;

                Integer newViolationCount = newViolationCountByRuleId.get(violation.AIViolationRule__c);
                newViolationCountByRuleId.put(violation.AIViolationRule__c, (newViolationCount == null ? 0 : newViolationCount) + 1);

            }

            if (newViolationCountByRuleId.isEmpty()) return;

            List<AIViolationRule__c> rulesToUpdate = new List<AIViolationRule__c>();

            for (AIViolationRule__c rule : [SELECT Id, TriggerCount__c FROM AIViolationRule__c WHERE Id IN :newViolationCountByRuleId.keySet()]) {
                rule.TriggerCount__c = (rule.TriggerCount__c == null ? 0 : rule.TriggerCount__c) + newViolationCountByRuleId.get(rule.Id);
                rule.LastTriggeredDate__c = Date.today();
                rulesToUpdate.add(rule);
            }

            if (!rulesToUpdate.isEmpty()) {
                Database.SaveResult[] updateResults = Database.update(rulesToUpdate, false);
                AIPlatformLogManager.logExceptions(updateResults, 'AIViolationTriggerHandler', 'updateViolationRuleTriggerStats');
            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIViolationTriggerHandler', 'updateViolationRuleTriggerStats');
        }
    }
}