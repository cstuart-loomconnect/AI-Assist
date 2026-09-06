/*
Class Name: AIPromptTemplateTrigger

=================================================================
=================================================================

Description: Trigger for handling AI Prompt Template events related to AI Assist

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/
trigger AIPromptTemplateTrigger on AIPromptTemplate__c (before insert) {

    if (AIAssistSettingsService.getSettings() == null || !AIAssistSettingsService.getSettings().IsApplicationActive__c) {
        return;
    }

    // Before Context
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            AIPromptTemplateTriggerHandler.handleBeforeInsert(Trigger.new);
        } 
    }

}