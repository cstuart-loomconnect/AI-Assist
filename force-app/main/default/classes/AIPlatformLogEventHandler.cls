/*
Class Name: AIPlatformLogEventHandler

=================================================================
=================================================================

Description: This class is responsible for handling the AIPlatformLogEvent__e platform events.
It processes the events and persists them as AIPlatformLog__c records for further analysis.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPlatformLogEventHandler {

    private static Boolean isAfterInsertHandlerRunning = false;

    public static void handleAfterInsert(List<AIPlatformLogEvent__e> events) {
        try {

            List<AIPlatformLog__c> logs = new List<AIPlatformLog__c>();

            if (events == null || events.isEmpty()) return;

            for (AIPlatformLogEvent__e event : events) {
                AIPlatformLog__c log = new AIPlatformLog__c();
                log.ClassName__c = event.ClassName__c;
                log.MethodName__c = event.MethodName__c;
                log.OccurredAt__c = event.OccurredAt__c;
                log.User__c = event.UserId__c;
                log.ExceptionType__c = event.ExceptionType__c;
                log.ExceptionMessage__c = event.ExceptionMessage__c;
                log.StackTrace__c = event.StackTrace__c;
                log.RelatedRecordId__c = event.RelatedRecordId__c;
                logs.add(log);
            }

            Database.DMLOptions dmlOptions = new Database.DMLOptions();
            dmlOptions.allowFieldTruncation = true;
 
            Database.insert(logs, dmlOptions);

        } catch (Exception e) {
            System.debug('Error handling AI Platform Log Events: ' + e.getMessage());
        }
    }
}