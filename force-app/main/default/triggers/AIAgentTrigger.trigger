/*
Class Name: AIAgentTrigger

=================================================================
=================================================================

Description: Trigger for handling AI Agent events related to AI Assist

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-07     Chandler Stuart          Initial development
*/
trigger AIAgentTrigger on AIAgent__c (before insert) {

    if (AIAssistSettings__c.getInstance() == null || !AIAssistSettings__c.getInstance().IsApplicationActive__c) return;

    // Before Context
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            AIAgentTriggerHandler.handleBeforeInsert(Trigger.new);
        }
    }

}