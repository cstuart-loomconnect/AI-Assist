/*
Class Name: AIAgentTrigger

=================================================================
=================================================================

Description: Trigger for handling AI Agent events related to AI Assist

=================================================================
=================================================================

Version      Date            Author                   Description
1.0          2026-09-05      Chandler Stuart          Initial development
*/
trigger AIAgentTrigger on AIAgent__c (before insert, before update) {

    if (AIAssistSettingsService.getSettings() == null || !AIAssistSettingsService.getSettings().IsApplicationActive__c) {
        return;
    }

    // Before Context
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            AIAgentTriggerHandler.handleBeforeInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            AIAgentTriggerHandler.handleBeforeUpdate(Trigger.oldMap, Trigger.newMap);
        }
    }

}