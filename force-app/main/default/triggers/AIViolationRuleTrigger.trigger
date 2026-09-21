/*
Class Name: AIViolationRuleTrigger

=================================================================
=================================================================

Description: Trigger for handling AI Violation Rule events related to AI Assist

=================================================================
=================================================================

Version      Date               Author                   Description
1.0          2026-09-06         Chandler Stuart          Initial development
*/
trigger AIViolationRuleTrigger on AIViolationRule__c (before insert, before update) {

    if (AIAssistSettings__c.getInstance() == null || !AIAssistSettings__c.getInstance().IsApplicationActive__c) return;

    // Before Context
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            AIViolationRuleTriggerHandler.handleBeforeInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            AIViolationRuleTriggerHandler.handleBeforeUpdate(Trigger.oldMap, Trigger.newMap);
        }
    }

}