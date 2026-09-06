/*
Class Name: AIConversationMessageTrigger

=================================================================
=================================================================

Description: Trigger for handling AI Conversation Message events related to AI Assist

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/
trigger AIConversationMessageTrigger on AIConversationMessage__c (after insert) {

    if (AIAssistSettingsService.getSettings() == null || !AIAssistSettingsService.getSettings().IsApplicationActive__c) {
        return;
    }

    // After Context
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            AIConversationMessageTriggerHandler.handleAfterInsert(Trigger.new);
        }
    }

}