/*
Class Name: AIPlatformLogEventTrigger

=================================================================
=================================================================

Description: Trigger for handling AI Platform Log Events

=================================================================
=================================================================

Version      Date            Author                   Description
1.0          2026-09-03      Chandler Stuart          Initial development
*/

trigger AIPlatformLogEventTrigger on AIPlatformLogEvent__e (after insert) {

    if (AIAssistSettingsService.getSettings() == null || !AIAssistSettingsService.getSettings().IsApplicationActive__c) {
        return;
    }

    if (Trigger.isInsert && Trigger.isAfter) {
        AIPlatformLogEventHandler.handleAfterInsert(Trigger.new);
    }


}