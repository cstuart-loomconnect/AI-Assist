/*
Class Name: AIViolationTrigger

=================================================================
=================================================================

Description: Trigger for handling AI Violation events related to AI Assist

=================================================================
=================================================================

Version      Date               Author                   Description
1.0          2026-09-06         Chandler Stuart          Initial development
*/
trigger AIViolationTrigger on AIViolation__c (after insert) {

    if (AIAssistSettings__c.getInstance() == null || !AIAssistSettings__c.getInstance().IsApplicationActive__c) return;

    // After Context
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            AIViolationTriggerHandler.handleAfterInsert(Trigger.new);
        }
    }

}