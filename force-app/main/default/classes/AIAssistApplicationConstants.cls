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

Version      Author                   Description
1.0          Chandler Stuart          Initial development
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

    // AIWorkflowAction__c.ActionType__c
    public static final String WORKFLOW_ACTION_TYPE_APEX = 'Apex';
    public static final String WORKFLOW_ACTION_TYPE_FLOW = 'Flow';

    // AIAgent__c.RetentionTrigger__c
    public static final String RETENTION_TRIGGER_CONVERSATION_CREATED_DATE = 'Conversation Created Date';
    public static final String RETENTION_TRIGGER_CONVERSATION_CLOSED_DATE = 'Conversation Closed Date';
    public static final String RETENTION_TRIGGER_LAST_MESSAGE_DATE = 'Last Message Date';

    // AIConversation__c.Status__c
    public static final String CONVERSATION_STATUS_ACTIVE = 'Active';
    public static final String CONVERSATION_STATUS_CLOSED = 'Closed';
    public static final String CONVERSATION_STATUS_ARCHIVED = 'Archived';

    // AIConversation__c.ConversationCloseReason__c
    public static final String CONVERSATION_CLOSE_REASON_IDLE_TIMEOUT = 'Idle Timeout';
    public static final String CONVERSATION_CLOSE_REASON_USER_CLOSED = 'User Closed';
    public static final String CONVERSATION_CLOSE_REASON_MESSAGE_LIMIT_REACHED = 'Message Limit Reached';
    public static final String CONVERSATION_CLOSE_REASON_TOKEN_LIMIT_REACHED = 'Token Limit Reached';
    public static final String CONVERSATION_CLOSE_REASON_SYSTEM_OVERRIDE = 'System Override';

    // AIConversationMessage__c.Sender__c
    public static final String SENDER_USER = 'User';
    public static final String SENDER_AI_AGENT = 'AI Agent';
    public static final String SENDER_SYSTEM = 'System';

    // AIExecutionStep__c.Status__c
    public static final String EXECUTION_STEP_STATUS_SUCCESS = 'Success';
    public static final String EXECUTION_STEP_STATUS_FAILED = 'Failed';

    // AIModelConfiguration__c.AIProvider__c
    public static final String AI_PROVIDER_ANTHROPIC = 'Anthropic';
    public static final String AI_PROVIDER_OPEN_AI = 'Open AI';

    // AIPIIRegistry__c.SyncStatus__c
    public static final String PII_SYNC_STATUS_NOT_SYNCED = 'Not Synced';
    public static final String PII_SYNC_STATUS_QUEUED = 'Queued';
    public static final String PII_SYNC_STATUS_IN_PROGRESS = 'In Progress';
    public static final String PII_SYNC_STATUS_SYNCED = 'Synced';
    public static final String PII_SYNC_STATUS_FAILED = 'Failed';

    // AIPiiRegistryWorker - used when AIAssistSettings__c.ToolingAPIVersion__c is blank.
    public static final String DEFAULT_TOOLING_API_VERSION = '62.0';

    // AIPiiRegistryWorker - bounds the Tooling API query when AIPIIRegistry__c.MaxFieldsToQuery__c is blank. Matches that field's own precision ceiling (999) so a sync is always bounded either way.
    public static final Integer DEFAULT_MAX_PII_FIELDS_TO_QUERY = 999;

    // AIPIIFieldMetadata__c.PIIFieldType__c - set once by AIPiiFieldTypeClassifier during AIPiiRegistryWorker's sync.
    public static final String PII_FIELD_TYPE_NAME = 'Name';
    public static final String PII_FIELD_TYPE_EMAIL = 'Email';
    public static final String PII_FIELD_TYPE_PHONE = 'Phone';
    public static final String PII_FIELD_TYPE_ADDRESS = 'Address';
    public static final String PII_FIELD_TYPE_SSN = 'SSN';
    public static final String PII_FIELD_TYPE_BANK_ACCOUNT = 'Bank Account';
    public static final String PII_FIELD_TYPE_CREDIT_CARD = 'Credit Card';
    public static final String PII_FIELD_TYPE_DATE_OF_BIRTH = 'Date of Birth';
    public static final String PII_FIELD_TYPE_IP_ADDRESS = 'IP Address';
    public static final String PII_FIELD_TYPE_GOVERNMENT_ID = 'Government ID';
    public static final String PII_FIELD_TYPE_NATIONAL_INSURANCE_NUMBER = 'National Insurance Number';
    public static final String PII_FIELD_TYPE_NHS_NUMBER = 'NHS Number';
    public static final String PII_FIELD_TYPE_VAT_NUMBER = 'VAT Number';
    public static final String PII_FIELD_TYPE_MEDICAL_RECORD = 'Medical Record Number';
    public static final String PII_FIELD_TYPE_VEHICLE_REGISTRATION = 'Vehicle Registration';
    public static final String PII_FIELD_TYPE_USERNAME = 'Username';
    public static final String PII_FIELD_TYPE_PASSWORD = 'Password';
    public static final String PII_FIELD_TYPE_OTHER = 'Other';

    // AIPiiDataMaskingRule__mdt.Strategy__c
    public static final String PII_MASKING_STRATEGY_SUBSTITUTE_FROM_LIST = 'SubstituteFromList';
    public static final String PII_MASKING_STRATEGY_RANDOMIZE_BY_PATTERN = 'RandomizeByPattern';

    // AIPiiFieldType__mdt.MatchField__c
    public static final String PII_MATCH_FIELD_NAME_OR_LABEL_CONTAINS = 'NameOrLabelContains';
    public static final String PII_MATCH_FIELD_API_NAME_EXACT = 'ApiNameExact';
    public static final String PII_MATCH_FIELD_DATA_TYPE_CONTAINS = 'DataTypeContains';

    // AiDataSourceResultProcessor
    public static final Integer DATA_SOURCE_RESULT_MAX_PARENT_DEPTH = 4;
    public static final Integer DATA_SOURCE_RESULT_MAX_CHILD_DEPTH = 3;
    public static final String DATA_SOURCE_RESULT_REDACTED_ERROR_VALUE = '***REDACTED-ERROR***';

    // AiMessageProcessingQueueable
    public static final Integer MESSAGE_PROCESSING_MAX_MESSAGE_HISTORY = 50;
    public static final String MESSAGE_PROCESSING_GENERIC_FAILURE_MESSAGE = 'Something went wrong generating a response. Please try again.';
}