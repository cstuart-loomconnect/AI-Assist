/*
Class Name: AIModelConfigurationTrigger

=================================================================
=================================================================

Description: Trigger for handling AI Model Configuration events related to AI Assist

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-09     Chandler Stuart          Initial development
*/
trigger AIModelConfigurationTrigger on AIModelConfiguration__c (before insert) {

    if (AIAssistSettings__c.getInstance() == null || !AIAssistSettings__c.getInstance().IsApplicationActive__c) return;

    // Before Context
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            AIModelConfigurationTriggerHandler.handleBeforeInsert(Trigger.new);
        } 
    }

}