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
1.1          Chandler Stuart          Added getAIProviderSuccessStatusCodes - parses AIProviderSuccessStatusCodes__c.
*/

public without sharing class AIAssistSettingsService {

    private static AIAssistSettings__c cachedSettings;
    private static Set<Integer> cachedSuccessStatusCodes;

    public static AIAssistSettings__c getSettings() {
        if (cachedSettings == null) {
            cachedSettings = AIAssistSettings__c.getOrgDefaults();
        }
        return cachedSettings;
    }

    public static Boolean isExceptionLoggingDisabled() {
        Boolean disabled = getSettings().DisableExceptionLogging__c;
        return disabled == true;
    }

    // Parses AIProviderSuccessStatusCodes__c (e.g. "200,201") - blank or non-numeric entries are skipped, and an empty result falls back to the code default so a bad setting never fails every response.
    public static Set<Integer> getAIProviderSuccessStatusCodes() {

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
}