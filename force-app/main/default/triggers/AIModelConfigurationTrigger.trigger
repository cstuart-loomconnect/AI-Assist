/*
Class Name: AIModelConfigurationTrigger

=================================================================
=================================================================

Description: Trigger for handling AI Model Configuration events related to AI Assist

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/
trigger AIModelConfigurationTrigger on AIModelConfiguration__c (before insert, before update) {

    if (AIAssistSettingsService.getSettings() == null || !AIAssistSettingsService.getSettings().IsApplicationActive__c) {
        return;
    }

    // Before Context
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            AIModelConfigurationTriggerHandler.handleBeforeInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            AIModelConfigurationTriggerHandler.handleBeforeUpdate(Trigger.new);
        }
    }

}