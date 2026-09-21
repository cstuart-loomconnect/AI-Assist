/*
Class Name: AIPromptTemplateTrigger

=================================================================
=================================================================

Description: Trigger for handling AI Prompt Template events related to AI Assist

=================================================================
=================================================================

Version      Date               Author                   Description
1.0          2026-09-05         Chandler Stuart          Initial development
*/
trigger AIPromptTemplateTrigger on AIPromptTemplate__c (before insert) {

    if (AIAssistSettings__c.getInstance() == null || !AIAssistSettings__c.getInstance().IsApplicationActive__c) return;

    // Before Context
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            AIPromptTemplateTriggerHandler.handleBeforeInsert(Trigger.new);
        } 
    }

}