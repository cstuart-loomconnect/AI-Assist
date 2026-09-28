/*
Class Name: AIConversationMessageService

=================================================================
=================================================================

Description: The entry point for a user sending a message - what the chat LWC calls. Never
talks to the AI provider itself - that's handed off entirely to the async job.

Flow:
[1] Validate the request (Agent active, channel allowed, usage limits on AIUserSettings__c).
[2] Find an Active conversation to reuse, or start a new one - per AIAgent__c.SingleActiveConversationPer_Record__c, closing the existing one first if it hit the Agent's per-conversation message/token cap.
[3] Take the conversation's processing lock (AIConversationLockService), insert the user's
    AIConversationMessage__c, and enqueue AiMessageProcessingQueueable - but only if the lock was
    free. If another message is still being processed, this one waits and is started by that
    job's AiMessageProcessingFinalizer.

Also owns manually closing a conversation, distinct from the Idle/Retention batch jobs'
automated closing.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-21     Chandler Stuart          Initial development
1.1          2026-09-26     Chandler Stuart          Only public entry points (sendMessage, closeConversation) log; private helpers rethrow unlogged. Split updateConversationToClosed out of closeConversation. Dropped SaveResult logs that duplicated the thrown exception.
1.2          2026-09-27     Chandler Stuart          Retry event carries PriorAttemptTokensUsed__c so tokens spent before a retry aren't lost.
1.3          2026-09-27     Chandler Stuart          One message processed per conversation at a time (AIConversationLockService). Retries moved to AiMessageProcessingFinalizer - AIMessageCalloutEvent__e removed. Failed turns record their tokens via a System message.
1.4          2026-09-27     Chandler Stuart          Failed turns show the user a generic message; the detailed error goes only into the failed-turn System message and the logs.
1.5          2026-09-27     Chandler Stuart          sendMessage overload continues a known conversation by Id (the chat window). Added retryLatestMessage (Try again / Regenerate). New conversations are refused while AIAssistUISettings__c.DisableUserInitiatedChat__c is on.
1.6          2026-09-28     Chandler Stuart          handleAgentResult/processValidAIMessage take an optional AIExecutionStepTracker, recorded onto the reply via AIExecutionStepRecorder once it exists. The 2-arg overloads are kept for existing callers that have no trace to pass.
*/

public without sharing class AIConversationMessageService {

    public class AIConversationMessageServiceException extends Exception {}

    // Validates the request, finds-or-creates the Active conversation, inserts the user's message, and enqueues async AI processing. Returns the inserted user message.
    public static AIConversationMessage__c sendMessage(Id agentId, String messageBody, String channel, String relatedObjectApiName, Id relatedRecordId) {
        return sendMessage(null, agentId, messageBody, channel, relatedObjectApiName, relatedRecordId);
    }

    // As above, but continues conversationId when it's still Active, owned by the user and on the same Agent - the chat window passes the conversation it has open. Anything else (blank, closed, over its caps) starts a new conversation, so check the returned message's AIConversation__c.
    public static AIConversationMessage__c sendMessage(Id conversationId, Id agentId, String messageBody, String channel, String relatedObjectApiName, Id relatedRecordId) {
        try {

            if (agentId == null) throw new AIConversationMessageServiceException('An Agent Id is required.');
            if (String.isBlank(messageBody)) throw new AIConversationMessageServiceException('A message body is required.');

            AIAgent__c agent = getActiveAgent(agentId);
            AIUserSettings__c userSettings = getUserSettings(UserInfo.getUserId());

            Boolean channelAllowed = isChannelAllowed(userSettings, channel);
            if (!channelAllowed) throw new AIConversationMessageServiceException('Channel "' + channel + '" is not enabled for your account.');

            AIConversation__c conversation = conversationId != null ? getContinuingConversation(agent, conversationId) : getReusableConversation(agent, relatedRecordId);
            Boolean isNewConversation = conversation == null;

            if (isNewConversation && AIAssistUISettings__c.getInstance().DisableUserInitiatedChat__c == true) throw new AIConversationMessageServiceException(AIAssistApplicationConstants.NEW_CONVERSATIONS_PAUSED_MESSAGE);

            Boolean withinUsageLimits = isWithinUsageLimits(userSettings, isNewConversation);
            if (!withinUsageLimits) throw new AIConversationMessageServiceException('You have reached your usage limit.');

            if (isNewConversation) {
                conversation = new AIConversation__c(
                    AIAgent__c = agent.Id,
                    Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE,
                    Channel__c = channel,
                    RelatedObjectAPIName__c = relatedObjectApiName,
                    RelatedRecordId__c = relatedRecordId == null ? null : String.valueOf(relatedRecordId)
                );

                Database.SaveResult conversationSaveResult = Database.insert(conversation, false);
                if (!conversationSaveResult.isSuccess()) throw new AIConversationMessageServiceException('Failed to create conversation: ' + conversationSaveResult.getErrors()[0].getMessage());
            }

            // Locked before the message is inserted, so a job finishing at the same moment either sees this message or finds the lock already released - it can't miss it.
            Boolean shouldStartProcessing = AIConversationLockService.lockConversation(conversation.Id);

            AIConversationMessage__c userMessage = new AIConversationMessage__c(
                AIConversation__c = conversation.Id,
                Sender__c = AIAssistApplicationConstants.SENDER_USER,
                MessageBody__c = messageBody,
                TokenCount__c = estimateTokenCount(messageBody)
            );

            Database.SaveResult userMessageSaveResult = Database.insert(userMessage, false);
            if (!userMessageSaveResult.isSuccess()) throw new AIConversationMessageServiceException('Failed to create message: ' + userMessageSaveResult.getErrors()[0].getMessage());

            // Only when this message took the lock - otherwise it waits, and the running job's finalizer starts it.
            if (shouldStartProcessing) {
                System.enqueueJob(new AiMessageProcessingQueueable(userMessage.Id, conversation.Id));
            }

            return userMessage;

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIConversationMessageService', 'sendMessage');
            throw ex instanceof AIConversationMessageServiceException ? ex : new AIConversationMessageServiceException('Failed to send message: ' + ex.getMessage(), ex);
        }
    }


    // Re-runs the AI response for the conversation's newest user message - the chat window's Try again (after a failed turn) and Regenerate. Only the newest message can be re-run: the finalizer hands the lock to the newest user message, so re-running an older one would answer the newest twice. Returns the re-run message's Id.
    public static Id retryLatestMessage(Id conversationId) {
        try {

            if (conversationId == null || conversationId.getSobjectType() != AIConversation__c.SObjectType) throw new AIConversationMessageServiceException('A valid AI Conversation Id is required.');

            List<AIConversation__c> conversations = [ SELECT Id, Status__c FROM AIConversation__c WHERE Id =:conversationId AND OwnerId =:UserInfo.getUserId() LIMIT 1 ];
            if (conversations.isEmpty()) throw new AIConversationMessageServiceException('AI Conversation not found for Id: ' + conversationId);
            if (conversations[0].Status__c != AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE) throw new AIConversationMessageServiceException('This conversation has ended. Start a new one to keep going.');

            List<AIConversationMessage__c> newestUserMessages = [ SELECT Id
                                                                  FROM AIConversationMessage__c
                                                                  WHERE AIConversation__c =:conversationId
                                                                  AND Sender__c =:AIAssistApplicationConstants.SENDER_USER
                                                                  ORDER BY CreatedDate DESC, Id DESC
                                                                  LIMIT 1 ];

            if (newestUserMessages.isEmpty()) throw new AIConversationMessageServiceException('There is no message to try again.');

            Boolean hasLock = AIConversationLockService.lockConversation(conversationId);
            if (!hasLock) throw new AIConversationMessageServiceException('Still working on your last message - try again once it has finished.');

            System.enqueueJob(new AiMessageProcessingQueueable(newestUserMessages[0].Id, conversationId));

            return newestUserMessages[0].Id;

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIConversationMessageService', 'retryLatestMessage');
            throw ex instanceof AIConversationMessageServiceException ? ex : new AIConversationMessageServiceException('Failed to try the message again: ' + ex.getMessage(), ex);
        }
    }

    // Evaluates one final AgentResult from AIAgentManager.executeAiMessage and performs whichever update follows - the manager itself never touches the database or the event bus. Retryable results never reach here; AiMessageProcessingQueueable hands those to AiMessageProcessingFinalizer to schedule.
    public static void handleAgentResult(Id conversationId, AIAgentManager.AgentResult result) {
        handleAgentResult(conversationId, result, null);
    }

    // As above, but with the turn's AIExecutionStepTracker - read back into the AIExecutionStep__c rows recorded on the reply (AIExecutionStepRecorder) once it exists.
    public static void handleAgentResult(Id conversationId, AIAgentManager.AgentResult result, AIExecutionStepTracker trace) {
        try {

            if (result.isSuccessful) { processValidAIMessage(conversationId, result, trace); return; }

            // A failed turn still spent tokens (earlier iterations, earlier attempts) - record them, with the detailed error, before telling the UI.
            processFailedAIMessageTokens(conversationId, result.totalTokensUsed, result.errorMessage);

            // The user only sees a generic message - result.errorMessage can contain configuration details (Named Credentials, model names, provider errors).
            processInvalidAIMessage(conversationId, AIAssistApplicationConstants.MESSAGE_PROCESSING_GENERIC_FAILURE_MESSAGE);

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIConversationMessageService', 'handleAgentResult');
            processInvalidAIMessage(conversationId, AIAssistApplicationConstants.MESSAGE_PROCESSING_GENERIC_FAILURE_MESSAGE);
        }
    }

    // Inserts the AI Agent's reply and publishes AIMessageReadyEvent__e so the chat LWC's empApi subscription picks it up.
    public static void processValidAIMessage(Id conversationId, AIAgentManager.AgentResult result) {
        processValidAIMessage(conversationId, result, null);
    }

    // As above, but also records trace's steps against the reply (AIExecutionStepRecorder) - a Master-Detail child needs a real parent Id, so this can't happen any earlier than here.
    public static void processValidAIMessage(Id conversationId, AIAgentManager.AgentResult result, AIExecutionStepTracker trace) {
        try {

            AIConversationMessage__c replyMessage = new AIConversationMessage__c(
                AIConversation__c = conversationId,
                Sender__c = AIAssistApplicationConstants.SENDER_AI_AGENT,
                MessageBody__c = result.replyText,
                TokenCount__c = result.totalTokensUsed,
                SuggestedWorkflowActionId__c = result.suggestedWorkflowActionId
            );

            Database.SaveResult replyMessageSaveResult = Database.insert(replyMessage, false);
            if (!replyMessageSaveResult.isSuccess()) throw new AIConversationMessageServiceException('Failed to insert reply message: ' + replyMessageSaveResult.getErrors()[0].getMessage());

            AIExecutionStepRecorder.record(replyMessage.Id, trace);

            EventBus.publish(new AIMessageReadyEvent__e(
                AIConversationId__c = conversationId,
                AIConversationMessageId__c = replyMessage.Id,
                IsSuccess__c = true
            ));

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIConversationMessageService', 'processValidAIMessage');
            processInvalidAIMessage(conversationId, AIAssistApplicationConstants.MESSAGE_PROCESSING_GENERIC_FAILURE_MESSAGE);
        }
    }

    // Publishes the failure event the chat LWC's empApi subscription is waiting on. Never throws - by the time this is called there's nothing left to catch it.
    public static void processInvalidAIMessage(Id conversationId, String errorMessage) {
        try {

            if (conversationId == null) return;

            EventBus.publish(new AIMessageReadyEvent__e(
                AIConversationId__c = conversationId,
                IsSuccess__c = false,
                ErrorMessage__c = errorMessage
            ));

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIConversationMessageService', 'processInvalidAIMessage');
        }
    }

    // Records the tokens a failed turn spent as a System message, so they still count toward ConversationTokenUsage__c and the usage limits (via AIConversationMessageTriggerHandler). System messages are never shown to the model. Nothing is recorded when no tokens were spent. Never throws.
    public static void processFailedAIMessageTokens(Id conversationId, Decimal tokensUsed, String failureReason) {
        try {

            if (conversationId == null || tokensUsed == null || tokensUsed <= 0) return;

            AIConversationMessage__c failedTurnMessage = new AIConversationMessage__c(
                AIConversation__c = conversationId,
                Sender__c = AIAssistApplicationConstants.SENDER_SYSTEM,
                MessageBody__c = AIAssistApplicationConstants.MESSAGE_PROCESSING_FAILED_TURN_PREFIX + (String.isBlank(failureReason) ? 'Unknown error.' : failureReason),
                TokenCount__c = tokensUsed
            );

            Database.SaveResult failedTurnSaveResult = Database.insert(failedTurnMessage, false);
            if (!failedTurnSaveResult.isSuccess()) throw new AIConversationMessageServiceException('Failed to record failed turn tokens: ' + failedTurnSaveResult.getErrors()[0].getMessage());

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIConversationMessageService', 'processFailedAIMessageTokens');
        }
    }

    // Manually ends a conversation - distinct from the Idle Timeout / Retention batch jobs' automated closing. Public entry point, so the failure is logged here; internal callers use updateConversationToClosed so it isn't logged twice.
    public static void closeConversation(Id conversationId, String closeReason) {
        try {

            updateConversationToClosed(conversationId, closeReason);

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIConversationMessageService', 'closeConversation');
            throw ex instanceof AIConversationMessageServiceException ? ex : new AIConversationMessageServiceException('Failed to close conversation: ' + ex.getMessage(), ex);
        }
    }

    // Throws without logging - whichever public entry point called it (closeConversation or sendMessage) logs the failure once.
    private static void updateConversationToClosed(Id conversationId, String closeReason) {
        try {

            if (conversationId == null) throw new AIConversationMessageServiceException('A Conversation Id is required.');

            AIConversation__c conversation = new AIConversation__c(
                Id = conversationId,
                Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED,
                ConversationCloseReason__c = String.isBlank(closeReason) ? AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_USER_CLOSED : closeReason
            );

            Database.SaveResult conversationSaveResult = Database.update(conversation, false);
            if (!conversationSaveResult.isSuccess()) throw new AIConversationMessageServiceException('Failed to close conversation: ' + conversationSaveResult.getErrors()[0].getMessage());

        } catch (Exception ex) {
            throw ex instanceof AIConversationMessageServiceException ? ex : new AIConversationMessageServiceException('Failed to close conversation: ' + ex.getMessage(), ex);
        }
    }

    // "Notify Only" never blocks. "Block New Messages" blocks everything. "Block New Conversations Only" only applies the caps that matter when starting a new conversation, so an already-active conversation can keep going. Returns true when the user is within their limits; throws AIConversationMessageServiceException with the specific limit that was hit otherwise.
    private static Boolean isWithinUsageLimits(AIUserSettings__c userSettings, Boolean isNewConversation) {
        try {

            if (userSettings == null || !userSettings.IsActive__c) return true;
            if (userSettings.UsageLimitReachedBehavior__c == AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY) return true;

            Boolean shouldBlockEverything = userSettings.UsageLimitReachedBehavior__c == AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES;
            Boolean shouldBlockNewConversations = userSettings.UsageLimitReachedBehavior__c == AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY;

            if (!shouldBlockEverything && !(shouldBlockNewConversations && isNewConversation)) return true;

            // Cap how many conversations this user can have Active at once - only checked when starting a new one, since reusing an existing conversation doesn't add to that count.
            if (isNewConversation && userSettings.MaxConcurrentConversations__c != null) {
                Integer activeConversations = [ SELECT COUNT() FROM AIConversation__c WHERE OwnerId =:UserInfo.getUserId() AND Status__c =:AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE ];
                if (activeConversations >= userSettings.MaxConcurrentConversations__c) throw new AIConversationMessageServiceException('You\'ve reached your limit of ' + userSettings.MaxConcurrentConversations__c.intValue() + ' concurrent conversations.');
            }

            // Cap how many new conversations this user can start in a rolling 24 hour window, regardless of their Active/Closed status.
            if (isNewConversation && userSettings.MaxConversationsPer24Hours__c != null) {
                Integer conversationsLast24Hours = [ SELECT COUNT() FROM AIConversation__c WHERE OwnerId =:UserInfo.getUserId() AND CreatedDate = LAST_N_DAYS:1 ];
                if (conversationsLast24Hours >= userSettings.MaxConversationsPer24Hours__c) throw new AIConversationMessageServiceException('You\'ve reached your limit of ' + userSettings.MaxConversationsPer24Hours__c.intValue() + ' new conversations per 24 hours.');
            }

            // Cap total tokens burned across all of this user's conversations created in the last 24 hours - applies to every message, not just ones starting a new conversation.
            if (userSettings.MaxTokensPer24Hours__c != null) {
                AggregateResult[] tokenResults = [ SELECT SUM(ConversationTokenUsage__c) totalTokens FROM AIConversation__c WHERE OwnerId = :UserInfo.getUserId() AND CreatedDate = LAST_N_DAYS:1 ];
                Decimal tokensLast24Hours = tokenResults.isEmpty() || tokenResults[0].get('totalTokens') == null ? 0 : (Decimal) tokenResults[0].get('totalTokens');
                if (tokensLast24Hours >= userSettings.MaxTokensPer24Hours__c) throw new AIConversationMessageServiceException('You\'ve reached your limit of ' + userSettings.MaxTokensPer24Hours__c.intValue() + ' tokens per 24 hours.');
            }

            return true;

        } catch (Exception ex) {
            throw ex instanceof AIConversationMessageServiceException ? ex : new AIConversationMessageServiceException('Failed to enforce usage limits: ' + ex.getMessage(), ex);
        }
    }

    // Looks up the Agent by Id and confirms it's Active. Throws if the Id doesn't resolve to a record (also covers FLS/sharing stripping it) or the Agent is inactive.
    private static AIAgent__c getActiveAgent(Id agentId) {
        try {

            if (agentId == null || agentId.getSobjectType() != AIAgent__c.SObjectType) throw new AIConversationMessageServiceException('A valid AI Agent Id is required.');

            List<AIAgent__c> agents = [ SELECT Id, DeveloperName__c, IsActive__c, MaxMessagesPerConversation__c, MaxTokensPerConversation__c, SingleActiveConversationPer_Record__c, AIModelConfiguration__c
                                        FROM AIAgent__c
                                        WHERE Id =:agentId
                                        LIMIT 1 ];

            if (agents.isEmpty()) throw new AIConversationMessageServiceException('AI Agent not found for Id: ' + agentId);
            if (!agents[0].IsActive__c) throw new AIConversationMessageServiceException('AI Agent "' + agents[0].DeveloperName__c + '" is not active.');

            return agents[0];

        } catch (Exception ex) {
            throw ex instanceof AIConversationMessageServiceException ? ex : new AIConversationMessageServiceException('Failed to retrieve AI Agent: ' + ex.getMessage(), ex);
        }
    }

    // Only applies when SingleActiveConversationPer_Record__c is on and a related record was given. If the existing Active conversation has hit the Agent's per-conversation cap, it's closed here (with the matching reason) and null is returned so the caller starts a fresh one instead of blocking the user.
    private static AIConversation__c getReusableConversation(AIAgent__c agent, Id relatedRecordId) {
        try {

            if (agent == null || relatedRecordId == null) return null;
            if (!agent.SingleActiveConversationPer_Record__c) return null;

            List<AIConversation__c> existingConversations = [SELECT Id, Status__c, MessageCount__c, ConversationTokenUsage__c
                                                            FROM AIConversation__c
                                                            WHERE AIAgent__c =:agent.Id
                                                            AND RelatedRecordId__c =:String.valueOf(relatedRecordId)
                                                            AND Status__c =:AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE
                                                            AND OwnerId =:UserInfo.getUserId()
                                                            LIMIT 1 ];

            if (existingConversations.isEmpty()) return null;

            return closeIfOverConversationCaps(agent, existingConversations[0]);

        } catch (Exception ex) {
            throw ex instanceof AIConversationMessageServiceException ? ex : new AIConversationMessageServiceException('Failed to get reusable conversation: ' + ex.getMessage(), ex);
        }
    }

    // The conversation the chat window has open - only continued while it's Active, the user's own and on the same Agent. Returns null (start a new one) otherwise, including when it has hit the Agent's per-conversation caps.
    private static AIConversation__c getContinuingConversation(AIAgent__c agent, Id conversationId) {
        try {

            if (agent == null || conversationId == null || conversationId.getSobjectType() != AIConversation__c.SObjectType) return null;

            List<AIConversation__c> conversations = [ SELECT Id, Status__c, MessageCount__c, ConversationTokenUsage__c
                                                      FROM AIConversation__c
                                                      WHERE Id =:conversationId
                                                      AND AIAgent__c =:agent.Id
                                                      AND Status__c =:AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE
                                                      AND OwnerId =:UserInfo.getUserId()
                                                      LIMIT 1 ];

            if (conversations.isEmpty()) return null;

            return closeIfOverConversationCaps(agent, conversations[0]);

        } catch (Exception ex) {
            throw ex instanceof AIConversationMessageServiceException ? ex : new AIConversationMessageServiceException('Failed to get the open conversation: ' + ex.getMessage(), ex);
        }
    }

    // Returns the conversation to keep appending to, or null once it has hit the Agent's max message or token count - it's closed here with the matching reason so the caller starts a fresh one instead of blocking the user.
    private static AIConversation__c closeIfOverConversationCaps(AIAgent__c agent, AIConversation__c existingConversation) {

        if (agent.MaxMessagesPerConversation__c != null && existingConversation.MessageCount__c != null && existingConversation.MessageCount__c >= agent.MaxMessagesPerConversation__c) {
            updateConversationToClosed(existingConversation.Id, AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_MESSAGE_LIMIT_REACHED);
            return null;
        }

        if (agent.MaxTokensPerConversation__c != null && existingConversation.ConversationTokenUsage__c != null && existingConversation.ConversationTokenUsage__c >= agent.MaxTokensPerConversation__c) {
            updateConversationToClosed(existingConversation.Id, AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_TOKEN_LIMIT_REACHED);
            return null;
        }

        return existingConversation;
    }

    // A rough, cheap estimate (~4 characters per token) for immediate usage-cap bookkeeping - not an exact provider-reported count, which only becomes known after the callout.
    private static Decimal estimateTokenCount(String text) {
        return String.isBlank(text) ? 0 : Math.ceil(text.length() / 4.0);
    }

    // No settings row, no configured allow-list, or no channel supplied all mean unrestricted - only an explicit allow-list that excludes the channel blocks the request. Returns true when the channel is allowed; throws AIConversationMessageServiceException otherwise.
    private static Boolean isChannelAllowed(AIUserSettings__c userSettings, String channel) {
        try {

            if (userSettings == null || String.isBlank(userSettings.AllowedChannels__c) || String.isBlank(channel)) return true;

            Set<String> allowedChannels = new Set<String>(userSettings.AllowedChannels__c.split(AIAssistApplicationConstants.DELIMITER_MULTI_SELECT_SEPARATOR));
            if (!allowedChannels.contains(channel)) throw new AIConversationMessageServiceException('Channel "' + channel + '" is not enabled for your account.');

            return true;

        } catch (Exception ex) {
            throw ex instanceof AIConversationMessageServiceException ? ex : new AIConversationMessageServiceException('Failed to validate channel: ' + ex.getMessage(), ex);
        }
    }

    // No AIUserSettings__c row means no configured limits for this user - treated as unrestricted rather than blocked.
    private static AIUserSettings__c getUserSettings(Id userId) {
        try {

            if (userId == null || userId.getSObjectType() != User.SObjectType) return null;

            List<AIUserSettings__c> settingsList = [ SELECT Id, IsActive__c, MaxConcurrentConversations__c, MaxConversationsPer24Hours__c, MaxTokensPer24Hours__c, UsageLimitReachedBehavior__c, AllowedChannels__c
                                                    FROM AIUserSettings__c
                                                    WHERE User__c =:userId
                                                    LIMIT 1 ];

            return settingsList.isEmpty() ? null : settingsList[0];

        } catch (Exception ex) {
            throw ex instanceof AIConversationMessageServiceException ? ex : new AIConversationMessageServiceException('Failed to retrieve user settings: ' + ex.getMessage(), ex);
        }
    }

}