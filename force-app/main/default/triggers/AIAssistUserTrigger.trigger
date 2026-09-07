/*
Class Name: AIAssistUserTrigger

=================================================================
=================================================================

Description: Trigger for handling User events related to AI Assist

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-06     Chandler Stuart          Initial development
*/
trigger AIAssistUserTrigger on User (before insert, after insert, after update) {

    if (AIAssistSettings__c.getInstance() == null || !AIAssistSettings__c.getInstance().IsApplicationActive__c) return;
    
    // Before Context
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            AIAssistUserTriggerHandler.handleBeforeInsert(Trigger.new);
        }
    }

    // After Context
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            AIAssistUserTriggerHandler.handleAfterInsert(Trigger.newMap);
        } else if (Trigger.isUpdate) {
            AIAssistUserTriggerHandler.handleAfterUpdate(Trigger.oldMap, Trigger.newMap);
        }
    }

}