/*
Class Name: AiMessageProcessingQueueable

=================================================================
=================================================================

Description: The async worker that does the heavy lifting for one message, run outside the
user's original transaction so the chat UI isn't blocked on a live callout.

Flow:
[0] Attach AiMessageProcessingFinalizer, which runs after this job however it ends - it schedule retries, starts the next waiting message, releases the conversation's processing lock, and reports a job killed by an uncatchable governor limit.
[1] Load everything for the turn - Agent, active Prompt Template, message history, available Data Source/Workflow Action tools.
[2] Call AIAgentManager.executeAiMessage for the result - it only ever makes the callout(s) and returns an AgentResult, never touching the database or the event bus itself. PII mappings its tool calls create are held in memory, then saved here once every callout is done.
[3] A retryable result is handed to the finalizer to schedule. Anything else goes to AIConversationMessageService.handleAgentResult, which completes or fails the turn.

A Data Source that wrote to the database (AIAgentManager.AIDataSourceWriteException) is the one
exception deliberately let out of this job: an unhandled exception rolls the whole transaction back,
undoing the write, and the finalizer then logs it, records the tokens and tells the chat UI.

A failure before a result is even produced (e.g. a loader throwing) is caught and logged rather
than allowed to propagate, since nothing else is watching this transaction - the chat UI instead
learns via an IsSuccess__c = false event from AIConversationMessageService.processInvalidAIMessage.
The conversation Id is passed in up front, so that event can be published even when the triggering
message itself was deleted before the job ran.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-21     Chandler Stuart          Initial development
1.1          2026-09-26     Chandler Stuart          Required loaders rethrow (unlogged) to execute() instead of returning empty records, so one failure produces one log entry.
1.2          2026-09-27     Chandler Stuart          Saves deferred PII mappings after the callouts. Carries prior attempts' token usage across retries.
1.3          2026-09-27     Chandler Stuart          Retries and lock hand-off moved to AiMessageProcessingFinalizer (replaces AIMessageCalloutEvent__e). Message history is the newest 50 up to the triggering message. A deleted triggering message now fails the turn visibly.
1.4          2026-09-27     Chandler Stuart          AIDataSourceWriteException is rethrown so the whole job rolls back, undoing a Data Source's write.
1.5          2026-09-28     Chandler Stuart          Builds the turn's AIExecutionStepTracker before calling executeAiMessage - live progress follows AIAssistUISettings__c.ShowExecutionTraceToUser__c, the heavier detail follows the running user's own AIUserSettings__c.DebugModeEnabled__c (isDebugModeEnabled). Passed through to handleAgentResult so a successful turn's steps get recorded.

*/

public without sharing class AiMessageProcessingQueueable implements Queueable, Database.AllowsCallouts {

    public class AiMessageProcessingQueueableException extends Exception {}

    private static final Integer FIRST_ATTEMPT_NUMBER = 1;

    private Id conversationId;
    private Id triggeringMessageId;
    private Integer attemptNumber;
    private Decimal priorAttemptTokensUsed;

    // A message's first attempt. Only Ids are stored, since Queueable arguments must be serializable and an SObject reference would go stale by execute time.
    public AiMessageProcessingQueueable(Id triggeringMessageId, Id conversationId) {
        this(triggeringMessageId, conversationId, FIRST_ATTEMPT_NUMBER, 0);
    }

    // A retry, scheduled by AiMessageProcessingFinalizer. priorAttemptTokensUsed carries the tokens already spent by earlier failed attempts, so the final reply's TokenCount__c reflects the whole turn rather than just its last attempt.
    public AiMessageProcessingQueueable(Id triggeringMessageId, Id conversationId, Integer attemptNumber, Decimal priorAttemptTokensUsed) {
        this.triggeringMessageId = triggeringMessageId;
        this.conversationId = conversationId;
        this.attemptNumber = attemptNumber == null ? FIRST_ATTEMPT_NUMBER : attemptNumber;
        this.priorAttemptTokensUsed = priorAttemptTokensUsed == null ? 0 : priorAttemptTokensUsed;
    }

    // Entry point run by the platform's async executor; see the class header Flow for the steps.
    public void execute(QueueableContext context) {

        // [0] Attached first, so it runs however this job ends - even on an uncatchable LimitException. context is only null when a test calls execute() directly.
        AiMessageProcessingFinalizer finalizer = new AiMessageProcessingFinalizer(triggeringMessageId, conversationId, attemptNumber);
        if (context != null) System.attachFinalizer(finalizer);

        // Earlier attempts' tokens - known now, so they're still recorded even if this job is killed by a governor limit.
        finalizer.setTokensUsed(priorAttemptTokensUsed);

        try {

            AIConversationMessage__c triggeringMessage = loadTriggeringMessage(triggeringMessageId);

            // Deleted after being enqueued - still tell the chat UI, which is waiting on this turn.
            if (triggeringMessage == null) {
                AIConversationMessageService.processInvalidAIMessage(conversationId, AIAssistApplicationConstants.MESSAGE_PROCESSING_MESSAGE_UNAVAILABLE);
                return;
            }

            AIConversation__c conversation = loadConversation(triggeringMessage.AIConversation__c);

            AIAgent__c agent = loadAgent(conversation.AIAgent__c);
            AIModelConfiguration__c modelConfiguration = loadModelConfiguration(agent.AIModelConfiguration__c);
            AIPromptTemplate__c promptTemplate = loadActivePromptTemplate(agent.Id);
            List<AIConversationMessage__c> messageHistory = loadMessageHistory(triggeringMessage);
            List<AIDataSource__c> availableDataSources = loadAvailableDataSources(agent.Id);
            List<AIWorkflowAction__c> availableWorkflowActions = loadAvailableWorkflowActions(agent.Id);

            // Live progress (the working indicator's steps) follows the org-wide setting; the heavier per-step timing, request/response JSON and sent preview only get captured for a user with debug mode on.
            AIExecutionStepTracker trace = new AIExecutionStepTracker(conversationId, triggeringMessageId, AIAssistUISettings__c.getInstance().ShowExecutionTraceToUser__c == true, isDebugModeEnabled());

            AIAgentManager.AgentResult result = AIAgentManager.executeAiMessage(agent, modelConfiguration, promptTemplate, conversation, messageHistory, availableDataSources, availableWorkflowActions, attemptNumber, trace);
            result.totalTokensUsed += priorAttemptTokensUsed;

            // PII mappings created by tool calls were held in memory so they couldn't block the next callout - every callout is done now, so persist them before any other DML.
            AIPiiMappingService.isDeferringWrites = false;
            AIPiiMappingService.processCachedPIIMappings();

            // [3] A retry is scheduled by the finalizer after this job ends - a delayed, fresh job keeps this user's access and gets fresh governor limits.
            if (result.isRetryable) {
                finalizer.requestRetry(result.totalTokensUsed);
                return;
            }

            AIConversationMessageService.handleAgentResult(conversation.Id, result, trace);

        } catch (AIAgentManager.AIDataSourceWriteException dataSourceWriteException) {
            // Rethrown on purpose, unlogged - escaping the job rolls back the Data Source's write, and the finalizer logs it once and fails the turn.
            finalizer.setTokensUsed(dataSourceWriteException.tokensUsed + priorAttemptTokensUsed);
            throw dataSourceWriteException;

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AiMessageProcessingQueueable', 'execute');
            AIConversationMessageService.processInvalidAIMessage(conversationId, AIAssistApplicationConstants.MESSAGE_PROCESSING_GENERIC_FAILURE_MESSAGE);
        }
    }

    // Queueable jobs run as the user who enqueued them, so this is the chat user who sent triggeringMessage - not an "Automated Process" user. Gates the AIExecutionStepTracker detail only they should incur the storage cost for.
    @TestVisible private static Boolean isDebugModeEnabled() {
        try {

            List<AIUserSettings__c> userSettings = [ SELECT DebugModeEnabled__c FROM AIUserSettings__c WHERE User__c = :UserInfo.getUserId() LIMIT 1 ];
            return !userSettings.isEmpty() && userSettings[0].DebugModeEnabled__c == true;

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AiMessageProcessingQueueable', 'isDebugModeEnabled');
            return false;
        }
    }

    // [1] Re-queries the message that triggered this job, since the object passed to the constructor isn't serialized across the async boundary.
    private static AIConversationMessage__c loadTriggeringMessage(Id messageId) {
        try {

            if (messageId == null || messageId.getSobjectType() != AIConversationMessage__c.SObjectType) return null;

            List<AIConversationMessage__c> messages = [ SELECT Id, MessageBody__c, AIConversation__c, CreatedDate FROM AIConversationMessage__c WHERE Id =:messageId LIMIT 1 ];

            return messages.isEmpty() ? null : messages[0];

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AiMessageProcessingQueueable', 'loadTriggeringMessage');
            return null; // Treated by execute as nothing to process - an empty record would cascade into a second, misleading error from loadConversation.
        }
    }

    // [2] Loads the parent conversation for the triggering message; throws since the orchestrator can't run without it.
    private static AIConversation__c loadConversation(Id conversationId) {
        try {

            if (conversationId == null || conversationId.getSobjectType() != AIConversation__c.SObjectType) throw new AiMessageProcessingQueueableException('Invalid AI Conversation Id: ' + conversationId);

            List<AIConversation__c> conversations = [ SELECT Id, AIAgent__c, RelatedObjectAPIName__c, RelatedRecordId__c FROM AIConversation__c WHERE Id = :conversationId LIMIT 1 ];
            if (conversations.isEmpty()) throw new AiMessageProcessingQueueableException('AI Conversation not found for Id: ' + conversationId);
            return conversations[0];

        } catch (Exception ex) {
            throw ex; // Required for the turn - rethrown for execute() to log once, rather than returning an empty record that cascades into further errors in the loaders after this one.
        }
    }

    // [3] Loads the agent configured on the conversation, including its tool-calling iteration cap.
    private static AIAgent__c loadAgent(Id agentId) {
        try {

            if (agentId == null || agentId.getSobjectType() != AIAgent__c.SObjectType) throw new AiMessageProcessingQueueableException('Invalid AI Agent Id: ' + agentId);

            List<AIAgent__c> agents = [ SELECT Id, DeveloperName__c, AIModelConfiguration__c, MaxToolCallingIterations__c FROM AIAgent__c WHERE Id = :agentId LIMIT 1 ];
            if (agents.isEmpty()) throw new AiMessageProcessingQueueableException('AI Agent not found for Id: ' + agentId);
            return agents[0];

        } catch (Exception ex) {
            throw ex; // Required for the turn - rethrown for execute() to log once, rather than returning an empty record that cascades into further errors in the loaders after this one.
        }
    }

    // [4] Loads the LLM/provider settings the agent calls out with; a missing assignment is a setup error, not a transient failure.
    private static AIModelConfiguration__c loadModelConfiguration(Id modelConfigurationId) {
        try {

            if (modelConfigurationId == null || modelConfigurationId.getSobjectType() != AIModelConfiguration__c.SObjectType) throw new AiMessageProcessingQueueableException('AI Agent has no AI Model Configuration assigned.');

            List<AIModelConfiguration__c> configurations = [ SELECT Id, DeveloperName__c, AIProvider__c, ModelIdentifier__c, NamedCredential__c, ApiPath__c, ApiVersionHeaderName__c, ApiVersionHeaderValue__c, MaximumOutputTokens__c, Temperature__c, RetryAttempts__c
                                                               FROM AIModelConfiguration__c
                                                               WHERE Id = :modelConfigurationId
                                                               LIMIT 1 ];

            if (configurations.isEmpty()) throw new AiMessageProcessingQueueableException('AI Model Configuration not found for Id: ' + modelConfigurationId);
            return configurations[0];

        } catch (Exception ex) {
            throw ex; // Required for the turn - rethrown for execute() to log once, rather than returning an empty record that cascades into further errors in the loaders after this one.
        }
    }

    // [5] No active Prompt Template is not an error - AIAgentManager runs fine with none, it just means no system prompt is assembled.
    private static AIPromptTemplate__c loadActivePromptTemplate(Id agentId) {
        try {

            if (agentId == null || agentId.getSobjectType() != AIAgent__c.SObjectType) return null;

            List<AIPromptTemplate__c> templates = [ SELECT Id, DeveloperName__c, AISystemContext__c, AIPrompt__c, AITone__c, AIExclusionRules__c
                                                     FROM AIPromptTemplate__c
                                                     WHERE AIAgent__c = :agentId AND IsActive__c = true
                                                     LIMIT 1 ];
            return templates.isEmpty() ? null : templates[0];

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AiMessageProcessingQueueable', 'loadActivePromptTemplate');
            return new AIPromptTemplate__c();
        }
    }

    // [6] Loads the most recent messages for context, capped to keep the prompt within a reasonable token budget.
    // Queried newest-first so the LIMIT keeps the latest messages (not the oldest), then reversed back to oldest-first for the model.
    // Stops at the triggering message, so the history always ends with the message being answered - even if the user has sent more since.
    @TestVisible private static List<AIConversationMessage__c> loadMessageHistory(AIConversationMessage__c triggeringMessage) {
        try {

            if (triggeringMessage == null || triggeringMessage.AIConversation__c == null) return new List<AIConversationMessage__c>();

            List<AIConversationMessage__c> newestFirst = [ SELECT Id, Sender__c, MessageBody__c
                                                           FROM AIConversationMessage__c
                                                           WHERE AIConversation__c =:triggeringMessage.AIConversation__c
                                                           AND CreatedDate <= :triggeringMessage.CreatedDate
                                                           ORDER BY CreatedDate DESC, Id DESC
                                                           LIMIT :AIAssistApplicationConstants.MESSAGE_PROCESSING_MAX_MESSAGE_HISTORY ];

            // Walks the list backwards to reverse it - Apex has no List.reverse(), and add(0, message) throws on an empty list.
            List<AIConversationMessage__c> oldestFirst = new List<AIConversationMessage__c>();

            for (Integer messageIndex = newestFirst.size() - 1; messageIndex >= 0; messageIndex--) {
                oldestFirst.add(newestFirst[messageIndex]);
            }

            return oldestFirst;

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AiMessageProcessingQueueable', 'loadMessageHistory');
            return new List<AIConversationMessage__c>();
        }
    }

    // [7] Resolves the Data Source tools currently enabled for the agent via the active AIAgentDataSource__c junction links.
    private static List<AIDataSource__c> loadAvailableDataSources(Id agentId) {
        try {

            if (agentId == null || agentId.getSobjectType() != AIAgent__c.SObjectType) return new List<AIDataSource__c>();

            Set<Id> dataSourceIds = new Set<Id>();
            for (AIAgentDataSource__c link : [ SELECT AIDataSource__c FROM AIAgentDataSource__c WHERE AIAgent__c = :agentId AND IsActive__c = true ]) {
                dataSourceIds.add(link.AIDataSource__c);
            }
            if (dataSourceIds.isEmpty()) return new List<AIDataSource__c>();

            return [ SELECT Id, DeveloperName__c, Description__c, OutputDescription__c, InputSchema__c
                     FROM AIDataSource__c
                     WHERE Id IN :dataSourceIds AND IsActive__c = true ];

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AiMessageProcessingQueueable', 'loadAvailableDataSources');
            return new List<AIDataSource__c>();
        }
    }

    // [8] Resolves the Workflow Action tools currently enabled for the agent via the active AIAgentWorkflowAction__c junction links.
    private static List<AIWorkflowAction__c> loadAvailableWorkflowActions(Id agentId) {
        try {

            if (agentId == null || agentId.getSobjectType() != AIAgent__c.SObjectType) return new List<AIWorkflowAction__c>();

            Set<Id> workflowActionIds = new Set<Id>();
            for (AIAgentWorkflowAction__c link : [ SELECT AIWorkflowAction__c FROM AIAgentWorkflowAction__c WHERE AIAgent__c = :agentId AND IsActive__c = true ]) {
                workflowActionIds.add(link.AIWorkflowAction__c);
            }
            if (workflowActionIds.isEmpty()) return new List<AIWorkflowAction__c>();

            return [ SELECT Id, DeveloperName__c, Description__c, OutputDescription__c, InputSchema__c
                     FROM AIWorkflowAction__c
                     WHERE Id IN :workflowActionIds AND IsActive__c = true ];

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AiMessageProcessingQueueable', 'loadAvailableWorkflowActions');
            return new List<AIWorkflowAction__c>();
        }
    }
}