/*
Class Name: AIAssistUserTrigger

=================================================================
=================================================================

Description: Trigger for handling User events related to AI Assist

=================================================================
=================================================================

Version      Date            Author                   Description
1.0          2026-09-03      Chandler Stuart          Initial development
1.1          2022-09-05      Chandler Stuart          Enhancement. Added Before Insert Context
*/
trigger AIAssistUserTrigger on User (before insert, after insert, after update) {

    if (AIAssistSettingsService.getSettings() == null || !AIAssistSettingsService.getSettings().IsApplicationActive__c) {
        return;
    }

    // Before Context
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            AIAssistUserTriggerHandler.handleBeforeInsert(Trigger.new);
        }
    }

    // After Context
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            AIAssistUserTriggerHandler.handleAfterInsert(Trigger.newMap);
        } else if (Trigger.isUpdate) {
            AIAssistUserTriggerHandler.handleAfterUpdate(Trigger.oldMap, Trigger.newMap);
        }
    }

}