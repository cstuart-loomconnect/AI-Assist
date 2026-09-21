/*
Class Name: AITermsAcknowledgmentTrigger

=================================================================
=================================================================

Description: Trigger for handling AI Terms Acknowledgment events related to AI Assist

=================================================================
=================================================================

Version      Date               Author                   Description
1.0          2026-09-06         Chandler Stuart          Initial development
*/
trigger AITermsAcknowledgmentTrigger on AITermsAcknowledgment__c (after insert) {

    if (AIAssistSettings__c.getInstance() == null || !AIAssistSettings__c.getInstance().IsApplicationActive__c) return;

    // After Context
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            AITermsAcknowledgmentTriggerHandler.handleAfterInsert(Trigger.new);
        }
    }

}