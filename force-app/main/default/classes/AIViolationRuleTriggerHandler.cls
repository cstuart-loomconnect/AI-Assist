/*
Class Name: AIViolationRuleTriggerHandler

=================================================================
=================================================================

Description: Handler for managing AI Violation Rule events related to AI Assist,
performing the business logic that runs on the AI Violation Rule trigger.

=================================================================
=================================================================

Version      Date               Author                   Description
1.0          2026-09-06         Chandler Stuart          Initial development
*/

public without sharing class AIViolationRuleTriggerHandler {

    private static Boolean isBeforeInsertHandlerRunning = false;
    private static Boolean isBeforeUpdateHandlerRunning = false;

    public static void handleBeforeInsert(List<AIViolationRule__c> newRules) {
        try {

            if (isBeforeInsertHandlerRunning) return;
            isBeforeInsertHandlerRunning = true;

            AIAssistGlobalUtility.generatePublicId(newRules);
            AIAssistGlobalUtility.generateDeveloperName(newRules);

            List<AIViolationRule__c> activeRulesToValidate = new List<AIViolationRule__c>(); // Only active rules need a unique Signal Tag.

            for (AIViolationRule__c rule : newRules) {
                if (rule.Active__c) { activeRulesToValidate.add(rule); }
            }

            if (!activeRulesToValidate.isEmpty()) { validateSignalTagUniqueness(activeRulesToValidate); }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIViolationRuleTriggerHandler', 'handleBeforeInsert');
        }
    }

    public static void handleBeforeUpdate(Map<Id, AIViolationRule__c> oldRulesById, Map<Id, AIViolationRule__c> newRulesById) {
        try {

            if (isBeforeUpdateHandlerRunning) return;
            isBeforeUpdateHandlerRunning = true;

            if (newRulesById == null || newRulesById.isEmpty() || oldRulesById == null) return;

            List<AIViolationRule__c> activeRulesToValidate = new List<AIViolationRule__c>(); // Active rules whose Signal Tag or Active status changed and need re-validating.

            for (AIViolationRule__c newRule : newRulesById.values()) {

                AIViolationRule__c oldRule = oldRulesById.get(newRule.Id);
                if (oldRule == null) continue;

                if (!newRule.Active__c) continue; // Only active rules need a unique Signal Tag.

                Boolean isSignalTagUnchanged = String.isBlank(oldRule.SignalTag__c) ? String.isBlank(newRule.SignalTag__c) : oldRule.SignalTag__c.equalsIgnoreCase(newRule.SignalTag__c);

                if (oldRule.Active__c == newRule.Active__c && isSignalTagUnchanged) continue; // Neither field changed, no need to re-validate.

                activeRulesToValidate.add(newRule);

            }

            if (!activeRulesToValidate.isEmpty()) { validateSignalTagUniqueness(activeRulesToValidate); }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIViolationRuleTriggerHandler', 'handleBeforeUpdate');
        }
    }

    // Adds a validation error to any record whose SignalTag__c duplicates another active rule's - either one already saved, or another record in this same save. Callers must only pass records where Active__c is true.
    private static void validateSignalTagUniqueness(List<AIViolationRule__c> rulesToValidate) {
        try {

            Set<String> signalTagsToCheck = new Set<String>();

            for (AIViolationRule__c rule : rulesToValidate) {
                if (String.isNotBlank(rule.SignalTag__c)) { 
                    signalTagsToCheck.add(rule.SignalTag__c); 
                }
            }

            if (signalTagsToCheck.isEmpty()) return;

            Map<String, Id> existingRuleIdBySignalTag = new Map<String, Id>(); // Already-saved active rules, keyed by lowercased Signal Tag since the field is case-insensitive.

            for (AIViolationRule__c existingRule : [SELECT Id, SignalTag__c FROM AIViolationRule__c WHERE SignalTag__c IN :signalTagsToCheck AND Active__c = true]) {
                existingRuleIdBySignalTag.put(existingRule.SignalTag__c.toLowerCase(), existingRule.Id);
            }

            Map<String, AIViolationRule__c> firstInBatchBySignalTag = new Map<String, AIViolationRule__c>(); // First record in this save to claim each Signal Tag, so duplicates within the same save are also caught.

            for (AIViolationRule__c rule : rulesToValidate) {

                if (String.isBlank(rule.SignalTag__c)) continue;

                String signalTagKey = rule.SignalTag__c.toLowerCase();

                Id existingRuleId = existingRuleIdBySignalTag.get(signalTagKey);
                if (existingRuleId != null && existingRuleId != rule.Id) {
                    rule.SignalTag__c.addError('Signal Tag "' + rule.SignalTag__c + '" is already used by another active AI Violation Rule.');
                    continue;
                }

                AIViolationRule__c firstInBatch = firstInBatchBySignalTag.get(signalTagKey);
                
                if (firstInBatch == null) {
                    firstInBatchBySignalTag.put(signalTagKey, rule);
                } else if (firstInBatch != rule) {
                    rule.SignalTag__c.addError('Signal Tag "' + rule.SignalTag__c + '" is used by more than one AI Violation Rule in this save.');
                }

            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIViolationRuleTriggerHandler', 'validateSignalTagUniqueness');
        }
    }
}