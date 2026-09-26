/*
Trigger Name: AIMessageCalloutEventTrigger

=================================================================
=================================================================

Description: Trigger for AI Message Callout Events - published by AIConversationMessageService
when a callout needs a retry with a fresh set of governor limits.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-26     Chandler Stuart          Initial development
*/

trigger AIMessageCalloutEventTrigger on AIMessageCalloutEvent__e (after insert) {

    if (AIAssistSettings__c.getInstance() == null || !AIAssistSettings__c.getInstance().IsApplicationActive__c) return;

    if (Trigger.isInsert && Trigger.isAfter) {
        AIMessageCalloutEventHandler.handleAfterInsert(Trigger.new);
    }

}