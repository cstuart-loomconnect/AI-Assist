/*
Class Name: AIAssistApplicationConstants

=================================================================
=================================================================

Description: Central store of literal values used across the AI Assist application -
picklist API names, multi-select channel values, platform log event types, and similar.
Reference these constants instead of hard-coding strings so a value only ever needs to
change in one place.

=================================================================
=================================================================

Version      Date            Author                   Description
1.0          2026-09-03      Chandler Stuart          Initial development
*/
public without sharing class AIAssistApplicationConstants {

    // AIUserSettings__c.ConversationVisibilityScope__c
    public static final String VISIBILITY_ALL_CONVERSATIONS = 'All Conversations';
    public static final String VISIBILITY_MY_CONVERSATIONS_ONLY = 'My Conversations Only';
    public static final String VISIBILITY_MY_SUBORDINATES = 'My Subordinates\' Conversations';

    // AIUserSettings__c.AllowedChannels__c (multi-select) 
    public static final String CHANNEL_MOBILE = 'Mobile';
    public static final String CHANNEL_UTILITY_BAR = 'Utility Bar';
    public static final String DELIMITER_MULTI_SELECT_SEPARATOR = ';';
    public static final String CHANNEL_RECORD_PAGE_CHAT = 'Record Page Chat';
    
    // AIUserSettings__c.UsageLimitReachedBehavior__c
    public static final String USAGE_LIMIT_NOTIFY_ONLY = 'Notify Only';
    public static final String USAGE_LIMIT_BLOCK_NEW_MESSAGES = 'Block New Messages';
    public static final String USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY = 'Block New Conversations Only';
    
    // User.AIAssistUserType__c 
    public static final String USER_TYPE_ADMIN = 'Admin';
    public static final String USER_TYPE_SUPER_USER = 'Super User';
    public static final String USER_TYPE_STANDARD = 'Standard User';

    // Permission Set API names 
    public static final String PERMISSION_SET_USER = 'AIAssistUser';
    public static final String PERMISSION_SET_ADMIN_USER = 'AIAssistAdminUser';
    public static final String PERMISSION_SET_SUPER_USER = 'AIAssistSuperUser';

    // AIUserSettings__c.TermsAcknowledgedStatus__c
    public static final String TERMS_ACKNOWLEDGED_STATUS_NOT_SENT = 'Not Sent';

    // The single Permission Set granted for each AIAssistUserType__c value
    public static final Map<String, String> PERMISSION_SET_BY_USER_TYPE = new Map<String, String>{
        USER_TYPE_STANDARD => PERMISSION_SET_USER,
        USER_TYPE_ADMIN => PERMISSION_SET_ADMIN_USER,
        USER_TYPE_SUPER_USER => PERMISSION_SET_SUPER_USER
    };

    // AIPlatformLogEvent__e.ExceptionType__c
    public static final String LOG_TYPE_CUSTOM_MESSAGE   = 'Custom Message';

    // AIAssistGlobalUtility.generateDeveloperName - field DeveloperName__c is populated from this source field on any object that has both.
    public static final String DEVELOPER_NAME_FIELD_API_NAME = 'DeveloperName__c';
    public static final String DEVELOPER_NAME_SOURCE_FIELD_API_NAME = 'Name';

    // AIAssistGlobalUtility.generatePublicId
    public static final String PUBLIC_ID_FIELD_API_NAME = 'PublicId__c';

    // AIDataSource__c.SourceType__c
    public static final String DATA_SOURCE_TYPE_APEX = 'Apex';
    public static final String DATA_SOURCE_TYPE_SOQL = 'SOQL';
}