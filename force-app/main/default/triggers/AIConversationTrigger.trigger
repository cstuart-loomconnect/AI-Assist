/*
Class Name: AIConversationTrigger

=================================================================
=================================================================

Description: Trigger for handling AI Conversation events related to AI Assist

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-07     Chandler Stuart          Initial development
*/
trigger AIConversationTrigger on AIConversation__c (before insert, before update) {

    if (AIAssistSettings__c.getInstance() == null || !AIAssistSettings__c.getInstance().IsApplicationActive__c) return;

    // Before Context
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            AIConversationTriggerHandler.handleBeforeInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            AIConversationTriggerHandler.handleBeforeUpdate(Trigger.oldMap, Trigger.newMap);
        }
    }

}