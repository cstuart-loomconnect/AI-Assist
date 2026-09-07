/*
Class Name: AIConversationMessageTrigger

=================================================================
=================================================================

Description: Trigger for handling AI Conversation Message events related to AI Assist

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-07     Chandler Stuart          Initial development
*/
trigger AIConversationMessageTrigger on AIConversationMessage__c (after insert) {

    if (AIAssistSettings__c.getInstance() == null || !AIAssistSettings__c.getInstance().IsApplicationActive__c) return;

    // After Context
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            AIConversationMessageTriggerHandler.handleAfterInsert(Trigger.new);
        }
    }

}