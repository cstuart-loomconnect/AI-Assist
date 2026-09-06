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
*/

public without sharing class AIAssistSettingsService {

    private static AIAssistSettings__c cachedSettings;

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
}