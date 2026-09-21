/*
Class Name: AIDataSourceTrigger

=================================================================
=================================================================

Description: Trigger for handling AI Data Source events related to AI Assist

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-09     Chandler Stuart          Initial development
*/
trigger AIDataSourceTrigger on AIDataSource__c (before insert, before update) {

    if (AIAssistSettings__c.getInstance() == null || !AIAssistSettings__c.getInstance().IsApplicationActive__c) return;

    // Before Context
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            AIDataSourceTriggerHandler.handleBeforeInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            AIDataSourceTriggerHandler.handleBeforeUpdate(Trigger.oldMap, Trigger.newMap);
        }
    }

}