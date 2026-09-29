/*
Class Name: AIChatDataStructure

=================================================================
=================================================================

Description: The response shapes returned to the aiAssistChat LWC family, and the small pieces
shared by every AIChatController service (AIChatStateService, AIChatContextService,
AIChatCommandService, AIChatUsageService, AIChatConversationService, AIChatActionService,
AIChatFeedbackService, AIChatDebugService). Kept in one place so those services can pass the same
wrapper types between each other without depending on AIChatController itself.

AIChatControllerException is the one exception type every service throws for a refusal the chat
window should show verbatim (a bad rating, a conversation the user doesn't own, a command that
doesn't exist here) - AIChatController unwraps it without extra logging, since it isn't a failure.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-28     Chandler Stuart          Split out of AIChatController - see that class for the version history behind these shapes.
1.1          2026-09-28     Chandler Stuart          ExecutionStep.durationMs; DebugTrace.toolCallingIterationsUsed/Max, attemptNumber, sentPreviewText, requestJson, responseJson - the AIExecutionStep__c fields AIExecutionStepRecorder now writes.
*/

public class AIChatDataStructure {

    public class AIChatControllerException extends Exception {}

    public class ChatContext {
        @AuraEnabled public String state;
        @AuraEnabled public String channel;
        @AuraEnabled public UiSettings ui;
        @AuraEnabled public UserState user;
        @AuraEnabled public UsageState usage;
        @AuraEnabled public TermsState terms;
        @AuraEnabled public RecordContext record;
        @AuraEnabled public List<AgentOption> agents = new List<AgentOption>();
        @AuraEnabled public AgentOption agent;
        @AuraEnabled public List<CommandOption> commands = new List<CommandOption>();
        @AuraEnabled public ConversationView conversation;
        @AuraEnabled public ConversationSummary openConversation;
    }

    public class UiSettings {
        @AuraEnabled public Boolean showTimestamps = false;
        @AuraEnabled public Boolean feedbackEnabled = true;
        @AuraEnabled public Boolean typingIndicatorEnabled = true;
        @AuraEnabled public Boolean showExecutionTrace = false;
        @AuraEnabled public Boolean inlineActionsEnabled = true;
        @AuraEnabled public String suggestedActionsDisplay = AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_CARDS;
        @AuraEnabled public Integer messagePageSize = AIAssistApplicationConstants.CHAT_DEFAULT_MESSAGE_PAGE_SIZE;
        @AuraEnabled public Boolean newChatsDisabled = false;
    }

    public class UserState {
        @AuraEnabled public Id userId;
        @AuraEnabled public String firstName;
        @AuraEnabled public Boolean debugMode = false;
        @AuraEnabled public Boolean exportEnabled = false;
        @AuraEnabled public Boolean workflowActionsEnabled = true;
    }

    public class UsageState {
        @AuraEnabled public Decimal tokensUsed = 0;
        @AuraEnabled public Decimal tokenLimit;
        @AuraEnabled public String behavior;
        @AuraEnabled public Boolean limitReached = false;
        @AuraEnabled public Boolean blockMessages = false;
        @AuraEnabled public Boolean blockNewConversations = false;
        @AuraEnabled public Boolean notifyOnly = false;
        @AuraEnabled public Integer resetsInMinutes;
    }

    public class TermsState {
        @AuraEnabled public Boolean required = false;
        @AuraEnabled public String version;
        @AuraEnabled public String policyUrl;
    }

    public class RecordContext {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String objectLabel;
        @AuraEnabled public String objectLabelPlural;
        @AuraEnabled public String recordName;
        @AuraEnabled public Boolean piiProtected = false;
    }

    public class AgentOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String description;
        @AuraEnabled public String greeting;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String loadTrigger;
        @AuraEnabled public Boolean allowResume = false;
    }

    public class CommandOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String command;
        @AuraEnabled public String description;
        @AuraEnabled public String scopeLabel;
        @AuraEnabled public Boolean isRecordSpecific = false;
    }

    public class ConversationView {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String title;
        @AuraEnabled public String status;
        @AuraEnabled public String closeReason;
        @AuraEnabled public Id agentId;
        @AuraEnabled public String agentName;
        @AuraEnabled public Boolean isActive = false;
        @AuraEnabled public Boolean canResume = false;
        @AuraEnabled public Boolean isProcessing = false;
        @AuraEnabled public String relatedRecordId;
        @AuraEnabled public String relatedObjectApiName;
        @AuraEnabled public List<ChatMessage> messages = new List<ChatMessage>();
        @AuraEnabled public Boolean hasMoreMessages = false;
    }

    public class ConversationSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        @AuraEnabled public String status;
        @AuraEnabled public String closeReason;
        @AuraEnabled public String agentName;
        @AuraEnabled public Integer messageCount = 0;
        @AuraEnabled public Datetime lastActivity;
        @AuraEnabled public String relatedRecordId;
        @AuraEnabled public String relatedObjectApiName;
    }

    public class ChatMessage {
        @AuraEnabled public Id id;
        @AuraEnabled public Id conversationId;
        @AuraEnabled public String sender;
        @AuraEnabled public String displayText;
        @AuraEnabled public Boolean isCommand = false;
        @AuraEnabled public String commandName;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Decimal tokenCount;
        @AuraEnabled public String feedbackRating;
        @AuraEnabled public SuggestedAction suggestedAction;
        @AuraEnabled public List<String> sources = new List<String>();
        @AuraEnabled public List<ExecutionStep> steps = new List<ExecutionStep>();
    }

    public class SuggestedAction {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String description;
        @AuraEnabled public Boolean requiresConfirmation = false;
        @AuraEnabled public String confirmationMessage;
        @AuraEnabled public Boolean hasRun = false;
        @AuraEnabled public List<ActionInputField> inputFields = new List<ActionInputField>();
    }

    public class ActionInputField {
        @AuraEnabled public String name;
        @AuraEnabled public String label;
        @AuraEnabled public String inputType;
        @AuraEnabled public Boolean required = false;
        @AuraEnabled public String helpText;
    }

    public class ExecutionStep {
        @AuraEnabled public Integer stepOrder;
        @AuraEnabled public String label;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean isSuccess = false;
        @AuraEnabled public Long durationMs;
    }

    public class MessagePage {
        @AuraEnabled public List<ChatMessage> messages = new List<ChatMessage>();
        @AuraEnabled public Boolean hasMore = false;
    }

    public class ConversationUpdate {
        @AuraEnabled public List<ChatMessage> messages = new List<ChatMessage>();
        @AuraEnabled public Boolean isProcessing = false;
        @AuraEnabled public String status;
        @AuraEnabled public UsageState usage;
    }

    public class SendRequest {
        public Id conversationId;
        public Id agentId;
        public String text;
        public String channel;
        public Id recordId;
        public String objectApiName;
    }

    public class SendResult {
        @AuraEnabled public String status;
        @AuraEnabled public String message;
        @AuraEnabled public Id conversationId;
        @AuraEnabled public Boolean isNewConversation = false;
        @AuraEnabled public ChatMessage userMessage;
        @AuraEnabled public UsageState usage;
    }

    public class FailureDetail {
        @AuraEnabled public String reference;
        @AuraEnabled public String debugDetail;
    }

    public class ActionResult {
        @AuraEnabled public Boolean isSuccess = false;
        @AuraEnabled public String message;
    }

    public class DebugTrace {
        @AuraEnabled public Id conversationId;
        @AuraEnabled public String conversationName;
        @AuraEnabled public String conversationPublicId;
        @AuraEnabled public Id userMessageId;
        @AuraEnabled public Id replyMessageId;
        @AuraEnabled public Boolean isSuccess = true;
        @AuraEnabled public Long durationMs;
        @AuraEnabled public String modelConfiguration;
        @AuraEnabled public String provider;
        @AuraEnabled public String model;
        @AuraEnabled public Decimal promptTokens;
        @AuraEnabled public Decimal replyTokens;
        @AuraEnabled public Integer toolCalls = 0;
        @AuraEnabled public Integer piiFieldsMasked = 0;
        @AuraEnabled public Integer toolCallingIterationsUsed;
        @AuraEnabled public Integer toolCallingIterationsMax;
        @AuraEnabled public Integer attemptNumber;
        @AuraEnabled public String sentPreviewText;
        @AuraEnabled public String requestJson;
        @AuraEnabled public String responseJson;
        @AuraEnabled public List<ExecutionStep> steps = new List<ExecutionStep>();
    }

    // =============================================================
    // Shared helpers
    // =============================================================

    public static Id toIdOrNull(String value) {
        try {
            return String.isBlank(value) ? null : Id.valueOf(value);
        } catch (Exception invalidId) {
            return null;
        }
    }

    // "ContactRoles" / "Contact_Roles" -> "Contact Roles".
    public static String humanise(String developerName) {

        if (String.isBlank(developerName)) return '';

        String spaced = developerName.replace('_', ' ').replaceAll('([a-z0-9])([A-Z])', '$1 $2').normalizeSpace();
        return spaced.left(1).toUpperCase() + spaced.substring(1);
    }
}