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

    // AIAgentManager.invokeTool - handed to the model in place of a bare "[]" so it can tell a genuine no-match apart from a failure and stop retrying.
    public static final String TOOL_RESULT_NO_RECORDS_FOUND = 'No records found.';

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

    // AIAgentManager - canonical (provider-agnostic) message shape built from AIConversationMessage__c history, before any provider handler reshapes it.
    public static final String CANONICAL_ROLE_KEY = 'role';
    public static final String CANONICAL_CONTENT_KEY = 'content';
    public static final String CANONICAL_ROLE_USER = 'user';
    public static final String CANONICAL_ROLE_ASSISTANT = 'assistant';

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

    // AI provider response handlers - used when AIAssistSettings__c.AIProviderSuccessStatusCodes__c is blank or has no valid codes.
    public static final Set<Integer> DEFAULT_AI_PROVIDER_SUCCESS_STATUS_CODES = new Set<Integer>{ 200 };

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

    // AIAnthropicResponseHandler - field/value names in Anthropic's Messages API response shape.
    public static final String ANTHROPIC_FIELD_CONTENT = 'content';
    public static final String ANTHROPIC_FIELD_BLOCK_TYPE = 'type';
    public static final String ANTHROPIC_BLOCK_TYPE_TEXT = 'text';
    public static final String ANTHROPIC_FIELD_TEXT = 'text';
    public static final String ANTHROPIC_BLOCK_TYPE_TOOL_USE = 'tool_use';
    public static final String ANTHROPIC_BLOCK_TYPE_TOOL_RESULT = 'tool_result';
    public static final String ANTHROPIC_FIELD_TOOL_USE_ID = 'id';
    public static final String ANTHROPIC_FIELD_TOOL_NAME = 'name';
    public static final String ANTHROPIC_FIELD_TOOL_USE_INPUT = 'input';
    public static final String ANTHROPIC_FIELD_TOOL_RESULT_ID = 'tool_use_id';

    public static final String ANTHROPIC_FIELD_USAGE = 'usage';
    public static final String ANTHROPIC_FIELD_USAGE_INPUT_TOKENS = 'input_tokens';
    public static final String ANTHROPIC_FIELD_USAGE_OUTPUT_TOKENS = 'output_tokens';
    public static final String ANTHROPIC_FIELD_ERROR = 'error';
    public static final String ANTHROPIC_FIELD_ERROR_MESSAGE = 'message';
    public static final String ANTHROPIC_FIELD_ERROR_TYPE = 'type';

    public static final String ANTHROPIC_ROLE_KEY = 'role';
    public static final String ANTHROPIC_ROLE_USER = 'user';
    public static final String ANTHROPIC_ROLE_ASSISTANT = 'assistant';

    // AIAnthropicRequestBuilder - field names in Anthropic's Messages API request shape. Tool name reuses ANTHROPIC_FIELD_TOOL_NAME above.
    public static final String ANTHROPIC_FIELD_MODEL = 'model';
    public static final String ANTHROPIC_FIELD_MAX_TOKENS = 'max_tokens';
    public static final String ANTHROPIC_FIELD_MESSAGES = 'messages';
    public static final String ANTHROPIC_FIELD_TEMPERATURE = 'temperature';
    public static final String ANTHROPIC_FIELD_SYSTEM = 'system';
    public static final String ANTHROPIC_FIELD_TOOLS = 'tools';
    public static final String ANTHROPIC_FIELD_TOOL_DESCRIPTION = 'description';
    public static final String ANTHROPIC_FIELD_TOOL_INPUT_SCHEMA = 'input_schema';

    // AIOpenAiRequestBuilder - field/value names in OpenAI's Chat Completions API request shape.
    public static final String OPENAI_FIELD_MODEL = 'model';
    public static final String OPENAI_FIELD_MAX_TOKENS = 'max_tokens';
    public static final String OPENAI_FIELD_MESSAGES = 'messages';
    public static final String OPENAI_FIELD_TEMPERATURE = 'temperature';
    public static final String OPENAI_FIELD_CONTENT = 'content';
    public static final String OPENAI_FIELD_TOOLS = 'tools';
    public static final String OPENAI_FIELD_TOOL_TYPE = 'type';
    public static final String OPENAI_TOOL_TYPE_FUNCTION = 'function';
    public static final String OPENAI_FIELD_TOOL_FUNCTION = 'function';
    public static final String OPENAI_FIELD_TOOL_NAME = 'name';
    public static final String OPENAI_FIELD_TOOL_DESCRIPTION = 'description';
    public static final String OPENAI_FIELD_TOOL_PARAMETERS = 'parameters';

    public static final String OPENAI_ROLE_KEY = 'role';
    public static final String OPENAI_ROLE_SYSTEM = 'system';

    // AIOpenAiResponseHandler - field/value names in OpenAI's Chat Completions API response shape. Content, function, tool name and role key reuse the OPENAI_* constants above.
    public static final String OPENAI_FIELD_CHOICES = 'choices';
    public static final String OPENAI_FIELD_MESSAGE = 'message';
    public static final String OPENAI_FIELD_TOOL_CALLS = 'tool_calls';
    public static final String OPENAI_FIELD_TOOL_CALL_ID = 'id';
    public static final String OPENAI_FIELD_TOOL_CALL_ARGUMENTS = 'arguments';
    public static final String OPENAI_FIELD_TOOL_RESULT_ID = 'tool_call_id';

    public static final String OPENAI_FIELD_USAGE = 'usage';
    public static final String OPENAI_FIELD_USAGE_TOTAL_TOKENS = 'total_tokens';
    public static final String OPENAI_FIELD_ERROR = 'error';
    public static final String OPENAI_FIELD_ERROR_MESSAGE = 'message';
    public static final String OPENAI_FIELD_ERROR_TYPE = 'type';

    public static final String OPENAI_ROLE_TOOL = 'tool';

    // AIAnthropicRequestBuilder / AIOpenAiRequestBuilder - sent on the last tool-calling iteration so the model must answer rather than call another tool.
    public static final String ANTHROPIC_FIELD_TOOL_CHOICE = 'tool_choice';
    public static final String ANTHROPIC_FIELD_TOOL_CHOICE_TYPE = 'type';
    public static final String ANTHROPIC_TOOL_CHOICE_NONE = 'none';
    public static final String OPENAI_FIELD_TOOL_CHOICE = 'tool_choice';
    public static final String OPENAI_TOOL_CHOICE_NONE = 'none';

    // Tool names both AI providers accept - letters, numbers, underscores and hyphens, 1-64 characters. Checked on AIDataSource__c.DeveloperName__c by AIDataSourceTriggerHandler.
    public static final String AI_PROVIDER_TOOL_NAME_PATTERN = '^[a-zA-Z0-9_-]{1,64}$';

    // AIAgentManager - used when AIAssistSettings__c.DefaultMaxToolCallingIterations__c / MaxToolCallingIterationsCap__c / MaxToolCallsPerIteration__c are blank or below 1.
    public static final Integer DEFAULT_MAX_TOOL_CALLING_ITERATIONS = 5;
    public static final Integer DEFAULT_MAX_TOOL_CALLING_ITERATIONS_CAP = 20;
    public static final Integer DEFAULT_MAX_TOOL_CALLS_PER_ITERATION = 5;

    // AIAgentManager - tool results sent back to the model when a tool call isn't run. Worded for the model, so it answers with what it already has rather than asking again.
    public static final String TOOL_RESULT_SKIPPED_TOO_MANY_CALLS = 'Not run: too many tool calls in one step. Ask for fewer tools at once, or answer with the information you already have.';
    public static final String TOOL_RESULT_FAILED = 'This tool failed to run. Answer with the information you already have, or tell the user the information is unavailable.';
    public static final String TOOL_RESULT_SKIPPED_LIMITS_REACHED = 'Not run: Salesforce processing limits for this request have been reached. Answer with the information you already have.';

    // AIConversationMessageService / AiMessageProcessingFinalizer - used when AIAssistSettings__c.ProcessingLockMinutes__c is blank or below 1.
    public static final Integer DEFAULT_PROCESSING_LOCK_MINUTES = 10;

    // AIGovernorLimits - Salesforce allows 120s of total callout time per transaction. No callout starts with less than the minimum left - it would almost certainly time out, and the AI provider may still bill for a request it had already started on.
    public static final Integer MAX_TRANSACTION_CALLOUT_MILLISECONDS = 120000;
    public static final Integer MIN_CALLOUT_TIMEOUT_MILLISECONDS = 5000;

    // AIGovernorLimits - amount of each limit held back before running another tool call - enough for the next AI provider callout and the work after the loop (saving PII mappings, inserting the reply and its trigger).
    public static final Integer TOOL_CALL_RESERVED_SOQL_QUERIES = 20;
    public static final Integer TOOL_CALL_RESERVED_CALLOUTS = 1;
    public static final Integer TOOL_CALL_RESERVED_CPU_MILLISECONDS = 5000;
    public static final Integer TOOL_CALL_RESERVED_HEAP_BYTES = 2000000;

    // AIGovernorLimits - the platform's message when a callout is attempted after uncommitted DML in the same transaction.
    public static final String UNCOMMITTED_WORK_ERROR_TEXT = 'uncommitted work pending';

    // AiMessageProcessingQueueable - shown when the message being answered was deleted before its job ran.
    public static final String MESSAGE_PROCESSING_MESSAGE_UNAVAILABLE = 'This message is no longer available, so no response was generated.';

    // AIConversationMessageService - prefix for the System audit message that records the tokens a failed turn used.
    public static final String MESSAGE_PROCESSING_FAILED_TURN_PREFIX = 'AI response failed: ';

    // AIAgentManager - AI provider callout request.
    public static final String HTTP_METHOD_POST = 'POST';
    public static final String HTTP_HEADER_CONTENT_TYPE = 'Content-Type';
    public static final String CONTENT_TYPE_JSON = 'application/json';

    // AIAgentManager - the model can only ever suggest a Workflow Action, never run one - phase 1 requires the user to trigger it explicitly from the chat UI.
    public static final String SUGGESTED_WORKFLOW_ACTION_JSON_KEY = 'suggested_workflow_action';
    public static final String WORKFLOW_ACTION_PROMPT_INSTRUCTION = 'Workflows (you cannot run these; suggest one only if it genuinely helps, never claim to have run one):';
    public static final String WORKFLOW_ACTION_SUGGESTION_ONLY_REPLY = 'Here\'s a suggested next step.'; // Shown when the model's reply was only a Workflow Action suggestion, so the saved reply is never blank.
    public static final String WORKFLOW_ACTION_PROMPT_JSON_INSTRUCTION = 'To suggest one, end your reply with a line containing only {"' + SUGGESTED_WORKFLOW_ACTION_JSON_KEY + '":"<DeveloperName>"}; otherwise omit it.';
}