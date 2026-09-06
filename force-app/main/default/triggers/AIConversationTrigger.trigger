/*
Class Name: AIConversationTrigger

=================================================================
=================================================================

Description: Trigger for handling AI Conversation events related to AI Assist

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/
trigger AIConversationTrigger on AIConversation__c (before insert, before update) {

    if (AIAssistSettingsService.getSettings() == null || !AIAssistSettingsService.getSettings().IsApplicationActive__c) {
        return;
    }

    // Before Context
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            AIConversationTriggerHandler.handleBeforeInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            AIConversationTriggerHandler.handleBeforeUpdate(Trigger.oldMap, Trigger.newMap);
        }
    }

}