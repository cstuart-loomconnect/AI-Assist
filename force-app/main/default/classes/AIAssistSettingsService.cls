/*
Class Name: AIAssistSettingsService

=================================================================
=================================================================

Description: This class is responsible for managing the settings related to the AI Assist Platform. 
It provides methods to retrieve the current settings, including whether platform logging is disabled, etc.
The settings are cached to improve performance and reduce the number of queries to the AIAssistSettings__c custom object.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
1.1          Chandler Stuart          Added getSuccessStatusCodes - parses AIProviderSuccessStatusCodes__c.
1.2          Chandler Stuart          Added getRetryStatusCodes (blank = never retry) and getCalloutTimeoutMilliseconds (blank throws) - moved out of AIAgentManager's hard-coded constants and AIModelConfiguration__c.SystemTimeoutSeconds__c.
1.3          Chandler Stuart          Added getDefaultMaxToolCallingIterations and getMaxToolCallingIterationsCap - blank or below 1 falls back to the AIAssistApplicationConstants default.
1.4          Chandler Stuart          Added getMaxToolCallsPerIteration and getProcessingLockMinutes.
1.5          Chandler Stuart          DisableExceptionLogging__c / DisablePlatformLogs__c replaced by IsExceptionLoggingEnabled__c / IsPlatformLoggingEnabled__c - isExceptionLoggingDisabled is now isExceptionLoggingEnabled, added isPlatformLoggingEnabled. Added readAppSettings / readUiSettings - field defaults when no settings row applies.
*/

public without sharing class AIAssistSettingsService {

    public class AIAssistSettingsServiceException extends Exception {}

    private static AIAssistSettings__c cachedSettings;
    private static Set<Integer> cachedSuccessStatusCodes;
    private static Set<Integer> cachedRetryStatusCodes;
    @TestVisible private static Integer cachedDefaultMaxToolCallingIterations;
    @TestVisible private static Integer cachedMaxToolCallingIterationsCap;
    @TestVisible private static Integer cachedMaxToolCallsPerIteration;
    @TestVisible private static Integer cachedProcessingLockMinutes;

    public static AIAssistSettings__c getSettings() {
        if (cachedSettings == null) {
            cachedSettings = readAppSettings();
        }
        return cachedSettings;
    }

    // Uncached org defaults, for callers that must see a change made earlier in the same transaction (the chat window). With no org row yet, getOrgDefaults()
    // returns every checkbox as false - so the "Is ... Enabled" switches would all read as off - so the field defaults are loaded instead.
    public static AIAssistSettings__c readAppSettings() {
        AIAssistSettings__c orgDefaults = AIAssistSettings__c.getOrgDefaults();
        return orgDefaults != null && orgDefaults.Id != null ? orgDefaults : (AIAssistSettings__c) AIAssistSettings__c.SObjectType.newSObject(null, true);
    }

    // The running user's AIAssistUISettings__c (User, then Profile, then Org level), uncached. As readAppSettings: with no row at any of those levels, the field
    // defaults - otherwise IsUserInitiatedChatEnabled__c, IsFeedbackEnabled__c and the other default-on switches all read as off.
    public static AIAssistUISettings__c readUiSettings() {

        AIAssistUISettings__c merged = AIAssistUISettings__c.getInstance();
        if (merged != null && merged.Id != null) return merged;

        Set<Id> hierarchyOwnerIds = new Set<Id>{ UserInfo.getUserId(), UserInfo.getProfileId(), UserInfo.getOrganizationId() };
        Boolean hasAnyRow = [ SELECT COUNT() FROM AIAssistUISettings__c WHERE SetupOwnerId IN :hierarchyOwnerIds WITH SYSTEM_MODE ] > 0;

        return hasAnyRow ? merged : (AIAssistUISettings__c) AIAssistUISettings__c.SObjectType.newSObject(null, true);
    }

    // Blank counts as on - logging is only off when IsExceptionLoggingEnabled__c is explicitly unchecked.
    public static Boolean isExceptionLoggingEnabled() {
        return getSettings().IsExceptionLoggingEnabled__c != false;
    }

    // Blank counts as on - AIPlatformLog__c records are only skipped when IsPlatformLoggingEnabled__c is explicitly unchecked.
    public static Boolean isPlatformLoggingEnabled() {
        return getSettings().IsPlatformLoggingEnabled__c != false;
    }

    // Parses AIProviderSuccessStatusCodes__c (e.g. "200,201") - blank or non-numeric entries are skipped, and an empty result falls back to the code default so a bad setting never fails every response.
    public static Set<Integer> getSuccessStatusCodes() {

        if (cachedSuccessStatusCodes != null) return cachedSuccessStatusCodes;

        Set<Integer> successStatusCodes = new Set<Integer>();
        String configuredStatusCodes = getSettings().AIProviderSuccessStatusCodes__c;

        if (String.isNotBlank(configuredStatusCodes)) {
            for (String statusCodeEntry : configuredStatusCodes.split(',')) {
                try {
                    if (String.isNotBlank(statusCodeEntry)) successStatusCodes.add(Integer.valueOf(statusCodeEntry.trim()));
                } catch (TypeException invalidStatusCode) {
                    // Not a number - skip it rather than failing every AI provider response.
                }
            }
        }

        cachedSuccessStatusCodes = successStatusCodes.isEmpty() ? new Set<Integer>(AIAssistApplicationConstants.DEFAULT_AI_PROVIDER_SUCCESS_STATUS_CODES) : successStatusCodes;
        return cachedSuccessStatusCodes;
    }

    // Parses RetryableStatusCodes__c (e.g. "429,503") - blank or non-numeric entries are skipped, and an empty result means no status is ever retried.
    public static Set<Integer> getRetryStatusCodes() {

        if (cachedRetryStatusCodes != null) return cachedRetryStatusCodes;

        Set<Integer> retryStatusCodes = new Set<Integer>();
        String configuredStatusCodes = getSettings().RetryableStatusCodes__c;

        if (String.isNotBlank(configuredStatusCodes)) {
            for (String statusCodeEntry : configuredStatusCodes.split(',')) {
                try {
                    if (String.isNotBlank(statusCodeEntry)) retryStatusCodes.add(Integer.valueOf(statusCodeEntry.trim()));
                } catch (TypeException invalidStatusCode) {
                    // Not a number - skip it rather than failing every AI provider callout.
                }
            }
        }

        cachedRetryStatusCodes = retryStatusCodes;
        return cachedRetryStatusCodes;
    }

    // CalloutTimeoutMilliseconds__c is required configuration - blank or not positive throws rather than guessing a timeout.
    public static Integer getCalloutTimeoutMilliseconds() {

        Decimal configuredTimeoutMillis = getSettings().CalloutTimeoutMilliseconds__c;

        if (configuredTimeoutMillis == null || configuredTimeoutMillis < 1) throw new AIAssistSettingsServiceException('AI Assist Settings has no Callout Timeout Milliseconds configured.');

        return configuredTimeoutMillis.intValue();
    }

    // Used by AIAgentManager when an AI Agent has no MaxToolCallingIterations__c - blank or below 1 falls back to the code default.
    public static Integer getDefaultMaxToolCallingIterations() {

        if (cachedDefaultMaxToolCallingIterations != null) return cachedDefaultMaxToolCallingIterations;

        Decimal configuredIterations = getSettings().DefaultMaxToolCallingIterations__c;
        cachedDefaultMaxToolCallingIterations = (configuredIterations == null || configuredIterations < 1) ? AIAssistApplicationConstants.DEFAULT_MAX_TOOL_CALLING_ITERATIONS : configuredIterations.intValue();
        return cachedDefaultMaxToolCallingIterations;
    }

    // Upper bound on every AI Agent's tool-calling iterations - blank or below 1 falls back to the code default.
    public static Integer getMaxToolCallingIterationsCap() {

        if (cachedMaxToolCallingIterationsCap != null) return cachedMaxToolCallingIterationsCap;

        Decimal configuredCap = getSettings().MaxToolCallingIterationsCap__c;
        cachedMaxToolCallingIterationsCap = (configuredCap == null || configuredCap < 1) ? AIAssistApplicationConstants.DEFAULT_MAX_TOOL_CALLING_ITERATIONS_CAP : configuredCap.intValue();
        return cachedMaxToolCallingIterationsCap;
    }

    // How many tool calls AIAgentManager runs from one model reply - blank or below 1 falls back to the code default.
    public static Integer getMaxToolCallsPerIteration() {

        if (cachedMaxToolCallsPerIteration != null) return cachedMaxToolCallsPerIteration;

        Decimal configuredMaxToolCalls = getSettings().MaxToolCallsPerIteration__c;
        cachedMaxToolCallsPerIteration = (configuredMaxToolCalls == null || configuredMaxToolCalls < 1) ? AIAssistApplicationConstants.DEFAULT_MAX_TOOL_CALLS_PER_ITERATION : configuredMaxToolCalls.intValue();
        return cachedMaxToolCallsPerIteration;
    }

    // How long a conversation's processing lock lasts before it expires on its own - blank or below 1 falls back to the code default.
    public static Integer getProcessingLockMinutes() {

        if (cachedProcessingLockMinutes != null) return cachedProcessingLockMinutes;

        Decimal configuredLockMinutes = getSettings().ProcessingLockMinutes__c;
        cachedProcessingLockMinutes = (configuredLockMinutes == null || configuredLockMinutes < 1) ? AIAssistApplicationConstants.DEFAULT_PROCESSING_LOCK_MINUTES : configuredLockMinutes.intValue();
        return cachedProcessingLockMinutes;
    }
}