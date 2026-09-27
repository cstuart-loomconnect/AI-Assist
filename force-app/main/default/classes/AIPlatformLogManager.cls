/*
Class Name: AIPlatformLogManager

=================================================================
=================================================================

Description: This class is responsible for logging exceptions and events related to the AI Assist Platform.
It provides methods to log exceptions with relevant details such as class name, method name, exception type, message, stack trace, and related record ID.
The logs are published as platform events and can be handled by triggers to store them in a custom object for further analysis.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-09     Chandler Stuart          Initial development
1.1          2026-09-27     Chandler Stuart          Text fields truncated before publishing - a message over 255 characters made the publish fail and the log was silently lost. A failed publish is now written to the debug log.
*/

public without sharing class AIPlatformLogManager {

    // AIPlatformLogEvent__e / AIPlatformLog__c field lengths - Text(255) and Long Text Area(32768).
    private static final Integer SHORT_TEXT_LENGTH = 255;
    private static final Integer LONG_TEXT_LENGTH = 32768;

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

        if (e instanceof DmlException) {
            DmlException dmlEx = (DmlException) e;
            if (dmlEx.getNumDml() > 0 && dmlEx.getDmlId(0) != null) {
                entry.RelatedRecordId__c = dmlEx.getDmlId(0);
            }
        }

        if (entry == null) return;

        publish(entry);
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

        for (Integer i = 0; i < saveResults.size(); i++) {

            Database.SaveResult sr = saveResults[i];

            if (sr == null) continue;
            if (sr.isSuccess()) { succeededCount++; continue; }

            failedCount++;

            if (sr.getId() != null) { failedRecordIds.add(sr.getId()); }

            for (Database.Error err : sr.getErrors()) {
                errorLines.add( 'record ' + (i + 1) + ' of ' + saveResults.size() + ' failed: '
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
                                    + ' record(s) failed to save (' + succeededCount + ' succeeded)';
        entry.ExceptionLogDetail__c = String.join(errorLines, '\n');
        entry.RelatedRecordId__c = failedRecordIds.isEmpty() ? null : failedRecordIds[0];

        publish(entry);
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

        for (Integer i = 0; i < deleteResults.size(); i++) {

            Database.DeleteResult dr = deleteResults[i];

            if (dr == null) continue;
            if (dr.isSuccess()) { succeededCount++; continue; }

            failedCount++;

            if (dr.getId() != null) { failedRecordIds.add(dr.getId()); }

            for (Database.Error err : dr.getErrors()) {
                errorLines.add( 'record ' + (i + 1) + ' of ' + deleteResults.size() + ' failed: '
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
                                    + ' record(s) failed to delete (' + succeededCount + ' succeeded)';
        entry.ExceptionLogDetail__c = String.join(errorLines, '\n');
        entry.RelatedRecordId__c = failedRecordIds.isEmpty() ? null : failedRecordIds[0];

        publish(entry);
    }

    public static void logExceptions(List<Database.UpsertResult> upsertResults, String className, String methodName) {

        // Validate Input Parameters
        if (String.isBlank(className) || String.isBlank(methodName) || upsertResults == null || upsertResults.isEmpty()) {
            System.debug('Invalid parameters provided for logging upsert results. Check className, methodName, and upsert result list.');
            return;
        }

        // Check AIAssistSettings__c.DisableExceptionLogging__c is true, if so, skip logging
        if (AIAssistSettingsService.isExceptionLoggingDisabled()) {
            System.debug('Exception logging is disabled. Skipping log entry for upsert results.');
            return;
        }

        // Check if we can publish events without hitting limits
        if (!isPublishable()) {
            System.debug('Cannot publish events due to DML limits. Skipping log entry for upsert results.');
            return;
        }

        Integer failedCount = 0;
        Integer succeededCount = 0;
        List<Id> failedRecordIds = new List<Id>();
        List<String> errorLines = new List<String>();

        for (Integer i = 0; i < upsertResults.size(); i++) {

            Database.UpsertResult ur = upsertResults[i];

            if (ur == null) continue;
            if (ur.isSuccess()) { succeededCount++; continue; }

            failedCount++;

            if (ur.getId() != null) { failedRecordIds.add(ur.getId()); }

            for (Database.Error err : ur.getErrors()) {
                errorLines.add( 'record ' + (i + 1) + ' of ' + upsertResults.size() + ' failed: '
                                + err.getStatusCode() + ': ' + err.getMessage()
                                + (err.getFields() != null && !err.getFields().isEmpty()
                                ? ' [fields: ' + String.join(err.getFields(), ', ') + ']' : '')
                );
            }
        }

        // Nothing failed - nothing to log
        if (failedCount == 0) {
            System.debug('All ' + succeededCount + ' upsert results succeeded. Skipping log entry.');
            return;
        }

        AIPlatformLogEvent__e entry = new AIPlatformLogEvent__e();
        entry.ClassName__c = className;
        entry.MethodName__c = methodName;
        entry.OccurredAt__c = System.now();
        entry.UserId__c = UserInfo.getUserId();
        entry.ExceptionType__c = 'DML Upsert Failure';
        entry.ExceptionMessage__c = failedCount + ' of ' + (succeededCount + failedCount)
                                    + ' record(s) failed to upsert (' + succeededCount + ' succeeded)';
        entry.ExceptionLogDetail__c = String.join(errorLines, '\n');
        entry.RelatedRecordId__c = failedRecordIds.isEmpty() ? null : failedRecordIds[0];

        publish(entry);
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

        publish(entry);
    }

    // Trims every text field to its length before publishing - an over-length value (e.g. a long AI provider error) makes the publish fail, and the entry would otherwise be lost silently. The full message is kept in ExceptionLogDetail__c.
    private static void publish(AIPlatformLogEvent__e entry) {

        entry.ClassName__c = truncate(entry.ClassName__c, SHORT_TEXT_LENGTH);
        entry.MethodName__c = truncate(entry.MethodName__c, SHORT_TEXT_LENGTH);
        entry.ExceptionType__c = truncate(entry.ExceptionType__c, SHORT_TEXT_LENGTH);
        entry.ExceptionMessage__c = truncate(entry.ExceptionMessage__c, SHORT_TEXT_LENGTH);
        entry.StackTrace__c = truncate(entry.StackTrace__c, LONG_TEXT_LENGTH);
        entry.ExceptionLogDetail__c = truncate(entry.ExceptionLogDetail__c, LONG_TEXT_LENGTH);

        Database.SaveResult publishResult = EventBus.publish(entry);

        // Nowhere left to log it - the debug log is the only trace of a failed publish.
        if (!publishResult.isSuccess()) {
            System.debug(LoggingLevel.ERROR, 'Failed to publish AI Platform Log Event: ' + publishResult.getErrors()[0].getMessage() + ' - ' + entry.ClassName__c + '.' + entry.MethodName__c + ': ' + entry.ExceptionMessage__c);
        }
    }

    private static String truncate(String value, Integer maxLength) {
        return (value == null || value.length() <= maxLength) ? value : value.left(maxLength);
    }

    private static Boolean isPublishable() {
        return Limits.getDMLStatements() < Limits.getLimitDMLStatements();
    }

}