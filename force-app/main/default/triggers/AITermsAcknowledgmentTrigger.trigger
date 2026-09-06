/*
Class Name: AITermsAcknowledgmentTrigger

=================================================================
=================================================================

Description: Trigger for handling AI Terms Acknowledgment events related to AI Assist

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/
trigger AITermsAcknowledgmentTrigger on AITermsAcknowledgment__c (after insert) {

    if (AIAssistSettingsService.getSettings() == null || !AIAssistSettingsService.getSettings().IsApplicationActive__c) {
        return;
    }

    // After Context
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            AITermsAcknowledgmentTriggerHandler.handleAfterInsert(Trigger.new);
        }
    }

}