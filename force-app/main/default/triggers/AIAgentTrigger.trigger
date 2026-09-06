/*
Class Name: AIAgentTrigger

=================================================================
=================================================================

Description: Trigger for handling AI Agent events related to AI Assist

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/
trigger AIAgentTrigger on AIAgent__c (before insert) {

    if (AIAssistSettingsService.getSettings() == null || !AIAssistSettingsService.getSettings().IsApplicationActive__c) {
        return;
    }

    // Before Context
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            AIAgentTriggerHandler.handleBeforeInsert(Trigger.new);
        }
    }

}