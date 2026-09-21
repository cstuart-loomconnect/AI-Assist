/*
Class Name: AIWorkflowActionTrigger

=================================================================
=================================================================

Description: Trigger for handling AI Workflow Action events related to AI Assist

=================================================================
=================================================================

Version      Date               Author                   Description
1.0          2026-09-06         Chandler Stuart          Initial development
*/
trigger AIWorkflowActionTrigger on AIWorkflowAction__c (before insert, before update) {

    if (AIAssistSettings__c.getInstance() == null || !AIAssistSettings__c.getInstance().IsApplicationActive__c) return;

    // Before Context
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            AIWorkflowActionTriggerHandler.handleBeforeInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            AIWorkflowActionTriggerHandler.handleBeforeUpdate(Trigger.oldMap, Trigger.newMap);
        }
    }

}