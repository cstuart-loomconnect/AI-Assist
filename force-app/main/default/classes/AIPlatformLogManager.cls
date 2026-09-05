/*
Class Name: AIPlatformLogManager

=================================================================
=================================================================

Description: This class is responsible for logging exceptions and events related to the AI Assist Platform.
It provides methods to log exceptions with relevant details such as class name, method name, exception type, message, stack trace, and related record ID.
The logs are published as platform events and can be handled by triggers to store them in a custom object for further analysis.

=================================================================
=================================================================

Version      Date            Author                   Description
1.0          2026-09-03      Chandler Stuart          Initial development
*/

public without sharing class AIPlatformLogManager {

    public static void logException(Exception e, String className, String methodName) {

        // Validate Input Parameters
        if (String.isBlank(className) || String.isBlank(methodName) || e == null) {
            System.debug('Invalid parameters provided for logging exception. Check className, methodName, and exception object.');
            return;
        }

        // Check AIAssistSettings__c.DisableExceptionLogging__c is true, if so, skip logging
        if (AIAssistSettingsService.isExceptionLoggingDisabled()) {
            System.debug('Exception logging is disabled. Skipping log entry for exception.');
            return;
        }

        // Check if we can publish events without hitting limits
        if (!isPublishable()) {
            System.debug('Cannot publish events due to DML limits. Skipping log entry for exception.');
            return;
        }

        AIPlatformLogEvent__e entry = new AIPlatformLogEvent__e();

        entry.ClassName__c = className;
        entry.MethodName__c = methodName;
        entry.OccurredAt__c = System.now();
        entry.UserId__c = UserInfo.getUserId();
        entry.ExceptionType__c = e.getTypeName();
        entry.ExceptionMessage__c = e.getMessage();
        entry.StackTrace__c = e.getStackTraceString();
        entry.ExceptionLogDetail__c = className + '.' + methodName + ' threw ' + e.getTypeName()
                                        + ': ' + e.getMessage()
                                        + (e.getCause() != null ? '\n\nCaused by: ' + e.getCause() : '');

        if (entry == null) return;

        Database.DMLOptions dmlOptions = new Database.DMLOptions();
        dmlOptions.allowFieldTruncation = true;

        EventBus.publish(entry);
    }

    public static void logExceptions(List<Database.SaveResult> saveResults, String className, String methodName) {

        // Validate Input Parameters
        if (String.isBlank(className) || String.isBlank(methodName) || saveResults == null || saveResults.isEmpty()) {
            System.debug('Invalid parameters provided for logging save results. Check className, methodName, and save result list.');
            return;
        }

        // Check AIAssistSettings__c.DisableExceptionLogging__c is true, if so, skip logging
        if (AIAssistSettingsService.isExceptionLoggingDisabled()) {
            System.debug('Exception logging is disabled. Skipping log entry for save results.');
            return;
        }

        // Check if we can publish events without hitting limits
        if (!isPublishable()) {
            System.debug('Cannot publish events due to DML limits. Skipping log entry for save results.');
            return;
        }

        Integer failedCount = 0;
        Integer succeededCount = 0;
        List<Id> failedRecordIds = new List<Id>();
        List<String> errorLines = new List<String>();

        for (Database.SaveResult sr : saveResults) {

            if (sr == null) continue;
            if (sr.isSuccess()) { succeededCount++; continue; }

            failedCount++;

            if (sr.getId() != null) { failedRecordIds.add(sr.getId()); }

            for (Database.Error err : sr.getErrors()) {
                errorLines.add( (sr.getId() != null ? sr.getId() + ' - ' : '')
                                + err.getStatusCode() + ': ' + err.getMessage()
                                + (err.getFields() != null && !err.getFields().isEmpty()
                                ? ' [fields: ' + String.join(err.getFields(), ', ') + ']' : '')
                );
            }
        }

        // Nothing failed - nothing to log
        if (failedCount == 0) {
            System.debug('All ' + succeededCount + ' save results succeeded. Skipping log entry.');
            return;
        }

        AIPlatformLogEvent__e entry = new AIPlatformLogEvent__e();
        entry.ClassName__c = className;
        entry.MethodName__c = methodName;
        entry.OccurredAt__c = System.now();
        entry.UserId__c = UserInfo.getUserId();
        entry.ExceptionType__c = 'DML Save Failure';
        entry.ExceptionMessage__c = failedCount + ' of ' + (succeededCount + failedCount)
                                    + ' record(s) failed to save (' + succeededCount + ' succeeded): '
                                    + errorLines[0];
        entry.ExceptionLogDetail__c = 'Failed record Ids: ' + (failedRecordIds.isEmpty() ? 'n/a' : String.join(failedRecordIds, ', '))
                                + '\n\n' + String.join(errorLines, '\n');
        entry.RelatedRecordId__c = failedRecordIds.isEmpty() ? null : failedRecordIds[0];

        EventBus.publish(entry);
    }

    public static void logExceptions(List<Database.DeleteResult> deleteResults, String className, String methodName) {

        // Validate Input Parameters
        if (String.isBlank(className) || String.isBlank(methodName) || deleteResults == null || deleteResults.isEmpty()) {
            System.debug('Invalid parameters provided for logging delete results. Check className, methodName, and delete result list.');
            return;
        }

        // Check AIAssistSettings__c.DisableExceptionLogging__c is true, if so, skip logging
        if (AIAssistSettingsService.isExceptionLoggingDisabled()) {
            System.debug('Exception logging is disabled. Skipping log entry for delete results.');
            return;
        }

        // Check if we can publish events without hitting limits
        if (!isPublishable()) {
            System.debug('Cannot publish events due to DML limits. Skipping log entry for delete results.');
            return;
        }

        Integer failedCount = 0;
        Integer succeededCount = 0;
        List<Id> failedRecordIds = new List<Id>();
        List<String> errorLines = new List<String>();

        for (Database.DeleteResult dr : deleteResults) {

            if (dr == null) continue;
            if (dr.isSuccess()) { succeededCount++; continue; }

            failedCount++;

            if (dr.getId() != null) { failedRecordIds.add(dr.getId()); }

            for (Database.Error err : dr.getErrors()) {
                errorLines.add( (dr.getId() != null ? dr.getId() + ' - ' : '')
                                + err.getStatusCode() + ': ' + err.getMessage()
                                + (err.getFields() != null && !err.getFields().isEmpty()
                                ? ' [fields: ' + String.join(err.getFields(), ', ') + ']' : '')
                );
            }
        }

        // Nothing failed - nothing to log
        if (failedCount == 0) {
            System.debug('All ' + succeededCount + ' delete results succeeded. Skipping log entry.');
            return;
        }

        AIPlatformLogEvent__e entry = new AIPlatformLogEvent__e();
        entry.ClassName__c = className;
        entry.MethodName__c = methodName;
        entry.OccurredAt__c = System.now();
        entry.UserId__c = UserInfo.getUserId();
        entry.ExceptionType__c = 'DML Delete Failure';
        entry.ExceptionMessage__c = failedCount + ' of ' + (succeededCount + failedCount)
                                    + ' record(s) failed to delete (' + succeededCount + ' succeeded): '
                                    + errorLines[0];
        entry.ExceptionLogDetail__c = 'Failed record Ids: ' + (failedRecordIds.isEmpty() ? 'n/a' : String.join(failedRecordIds, ', '))
                                + '\n\n' + String.join(errorLines, '\n');
        entry.RelatedRecordId__c = failedRecordIds.isEmpty() ? null : failedRecordIds[0];

        EventBus.publish(entry);
    }

    public static void logCustomMessage(String message, String logDetail, String className, String methodName, Id recordId) {

        // Validate Input Parameters
        if ((String.isBlank(message) && String.isBlank(logDetail))) {
            System.debug('Invalid parameters provided for logging custom message. Check message and logDetail.');
            return;
        }

        // Check AIAssistSettings__c.DisableExceptionLogging__c is true, if so, skip logging
        if (AIAssistSettingsService.isExceptionLoggingDisabled()) {
            System.debug('Exception logging is disabled. Skipping log entries for custom messages.');
            return;
        }

        // Check if we can publish events without hitting limits
        if (!isPublishable()) {
            System.debug('Cannot publish events due to DML limits. Skipping log entries for custom messages.');
            return;
        }

        AIPlatformLogEvent__e entry = new AIPlatformLogEvent__e();
        entry.ClassName__c = className;
        entry.MethodName__c = methodName;
        entry.OccurredAt__c = System.now();
        entry.UserId__c = UserInfo.getUserId();
        entry.ExceptionType__c = 'Custom Message';
        entry.ExceptionMessage__c = message;
        entry.ExceptionLogDetail__c = logDetail;
        entry.RelatedRecordId__c = recordId;

        if (entry == null) return;

        Database.DMLOptions dmlOptions = new Database.DMLOptions();
        dmlOptions.allowFieldTruncation = true;

        EventBus.publish(entry);
    }

    private static Boolean isPublishable() {
        return Limits.getDMLStatements() < Limits.getLimitDMLStatements();
    }

}