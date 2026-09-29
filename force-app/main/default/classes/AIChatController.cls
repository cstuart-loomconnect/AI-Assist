/*
Class Name: AIChatController

=================================================================
=================================================================

Description: The Apex controller behind the AI Assist chat window (the aiAssistChat LWC and its
child components). Every @AuraEnabled method here is one round trip the window makes; the logic
behind each is split across a handful of services so this class stays a thin translator between
what the window asks for and what it should be shown:

AIChatDataStructure                  - the response shapes shared by every service below, and the one
                              exception type (AIChatDataStructure.AIChatControllerException) a service
                              throws for a refusal the window should show verbatim.
AIChatStateService          - maintenance, app inactive, channel not allowed, terms version -
                              the settings behind ChatContext.state, and the canonical read of
                              the running user's AIUserSettings__c row.
AIChatContextService        - the record context strip, its PII-protected badge, and which
                              Agent is offered/picked for it.
AIChatCommandService        - AIChatCommand__mdt: which slash commands exist here, and splitting
                              a message body into what's shown vs. a command's hidden prompt.
AIChatUsageService           - the usage meter and the three UsageLimitReachedBehavior__c modes.
AIChatConversationService   - loading, paging, listing, resuming and exporting conversations -
                              and the two ownership guards every conversation/message Id goes
                              through first.
AIChatActionService          - the Suggested Action card, its InputSchema__c fields, and running
                              it through AiWorkflowActionDispatcher.
AIChatFeedbackService        - thumbs up/down and terms acknowledgement.
AIChatDebugService            - the debug trace, PII mappings modal and failure detail - every
                              place a real (unmasked) PII value is handled lives here.

Sending and processing a message is still owned by AIConversationMessageService (validation,
locking, async job); this class translates its results and exceptions into something the chat
window can show (SendResult), and reads back the conversation for display via
AIChatConversationService.

Every conversation-bound method only acts on conversations the running user owns, checked by
AIChatConversationService.assertOwnsConversation / assertOwnsAgentMessage. App settings are read
straight from AIAssistSettings__c.getOrgDefaults() rather than a per-transaction cache, so a
settings change is always reflected on the next call.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-27     Chandler Stuart          Initial development
1.1          2026-09-27     Chandler Stuart          Replies show real PII - fake values from the conversation's AIPIIMapping__c are restored on read (display and export), never saved.
1.2          2026-09-27     Chandler Stuart          Added getPiiMappings - debug mode's PII masking pairs for the Debug Trace's "pii mappings" modal.
1.3          2026-09-27     Chandler Stuart          Slash commands read from AIChatCommand__mdt (replaces the AIChatCommand__c object) - Agent by Developer Name, and limited by AvailableTo__c to the user's AI Assist User Type.
1.4          2026-09-28     Chandler Stuart          Split into AIChatDataStructure and eight services (see above) - this class keeps only the @AuraEnabled entry points the aiAssistChat LWC family imports by name, plus the exception translation every one of them shares.
*/

public with sharing class AIChatController {

    // =============================================================
    // Entry points
    // =============================================================

    // Everything the chat window needs to render, in one round trip. agentKey (an AIAgent__c Id or DeveloperName__c) picks the Agent when given and available; otherwise the first Agent for the object.
    @AuraEnabled
    public static AIChatDataStructure.ChatContext getChatContext(String recordId, String objectApiName, String channel, String agentKey) {
        try {

            AIChatDataStructure.ChatContext context = new AIChatDataStructure.ChatContext();
            context.channel = channel;

            AIAssistSettings__c appSettings = AIAssistSettings__c.getOrgDefaults();
            AIAssistUISettings__c uiSettings = AIAssistUISettings__c.getInstance();
            AIUserSettings__c userSettings = AIChatStateService.getUserSettings();

            context.ui = AIChatStateService.buildUiSettings(uiSettings);
            context.user = AIChatStateService.buildUserState(userSettings);

            if (appSettings.IsApplicationActive__c == false) { context.state = AIAssistApplicationConstants.CHAT_STATE_INACTIVE; return context; }
            if (uiSettings.IsMaintenanceMode__c == true) { context.state = AIAssistApplicationConstants.CHAT_STATE_MAINTENANCE; return context; }
            if (!AIChatStateService.isChannelAllowed(userSettings, channel)) { context.state = AIAssistApplicationConstants.CHAT_STATE_CHANNEL_DISABLED; return context; }

            context.terms = AIChatStateService.buildTermsState(appSettings);
            if (context.terms.required) { context.state = AIAssistApplicationConstants.CHAT_STATE_TERMS; return context; }

            context.record = AIChatContextService.buildRecordContext(recordId, objectApiName);
            context.agents = AIChatContextService.getAvailableAgents(context.record.objectApiName);
            context.agent = AIChatContextService.selectAgent(context.agents, agentKey);

            if (context.agent == null) { context.state = AIAssistApplicationConstants.CHAT_STATE_NO_AGENT; return context; }

            context.state = AIAssistApplicationConstants.CHAT_STATE_READY;
            context.usage = AIChatUsageService.buildUsageState(userSettings);
            context.commands = AIChatCommandService.getAvailableCommands(context.agent.id, context.record);

            AIConversation__c activeConversation = AIChatConversationService.findActiveConversation(context.agent.id, context.record.recordId);

            if (activeConversation != null) {
                context.openConversation = AIChatConversationService.toConversationSummary(activeConversation);

                Boolean shouldAutoLoad = context.agent.loadTrigger != AIAssistApplicationConstants.CONVERSATION_LOAD_TRIGGER_MANUAL_ONLY;
                if (shouldAutoLoad) context.conversation = AIChatConversationService.buildConversationView(activeConversation.Id, context.ui.messagePageSize, context.user, context.ui);
            }

            return context;

        } catch (Exception ex) {
            throw toAuraException(ex, 'getChatContext');
        }
    }

    // Older messages for "Show earlier messages" - the page before beforeMessageId, oldest first.
    @AuraEnabled
    public static AIChatDataStructure.MessagePage getEarlierMessages(Id conversationId, Id beforeMessageId) {
        try {

            AIChatConversationService.assertOwnsConversation(conversationId);

            AIAssistUISettings__c uiSettings = AIAssistUISettings__c.getInstance();
            AIChatDataStructure.UiSettings ui = AIChatStateService.buildUiSettings(uiSettings);
            AIChatDataStructure.UserState user = AIChatStateService.buildUserState(AIChatStateService.getUserSettings());

            return AIChatConversationService.loadMessagePage(conversationId, beforeMessageId, ui.messagePageSize, user, ui);

        } catch (Exception ex) {
            throw toAuraException(ex, 'getEarlierMessages');
        }
    }

    // Called when AIMessageReadyEvent__e arrives (or by the polling fallback) - every displayable message newer than afterMessageId, plus whether a reply is still being worked on.
    @AuraEnabled
    public static AIChatDataStructure.ConversationUpdate getConversationUpdate(Id conversationId, Id afterMessageId) {
        try {

            AIConversation__c conversation = AIChatConversationService.assertOwnsConversation(conversationId);

            AIAssistUISettings__c uiSettings = AIAssistUISettings__c.getInstance();
            AIUserSettings__c userSettings = AIChatStateService.getUserSettings();

            AIChatDataStructure.ConversationUpdate conversationUpdate = new AIChatDataStructure.ConversationUpdate();
            conversationUpdate.status = conversation.Status__c;
            conversationUpdate.isProcessing = conversation.ProcessingLockedUntil__c != null && conversation.ProcessingLockedUntil__c > System.now();
            conversationUpdate.messages = AIChatConversationService.loadMessagesAfter(conversationId, afterMessageId, AIChatStateService.buildUserState(userSettings), AIChatStateService.buildUiSettings(uiSettings));
            conversationUpdate.usage = AIChatUsageService.buildUsageState(userSettings);

            return conversationUpdate;

        } catch (Exception ex) {
            throw toAuraException(ex, 'getConversationUpdate');
        }
    }

    // Sends one message. Never throws for an expected refusal (limits, blocked, paused) - those come back as a status the chat window renders in place; only unexpected failures throw.
    @AuraEnabled
    public static AIChatDataStructure.SendResult sendMessage(String requestJson) {

        AIChatDataStructure.SendResult result = new AIChatDataStructure.SendResult();

        try {

            AIChatDataStructure.SendRequest request = (AIChatDataStructure.SendRequest) JSON.deserialize(requestJson, AIChatDataStructure.SendRequest.class);
            String text = request.text == null ? '' : request.text.trim();

            if (String.isBlank(text)) return failSend(result, AIAssistApplicationConstants.CHAT_SEND_STATUS_ERROR, 'Type a message first.');

            AIAssistSettings__c appSettings = AIAssistSettings__c.getOrgDefaults();
            if (appSettings.IsApplicationActive__c == false) return failSend(result, AIAssistApplicationConstants.CHAT_SEND_STATUS_BLOCKED, 'AI Assist is turned off.');
            if (AIAssistUISettings__c.getInstance().IsMaintenanceMode__c == true) return failSend(result, AIAssistApplicationConstants.CHAT_SEND_STATUS_BLOCKED, 'AI Assist is down for maintenance.');

            String messageBody = text;

            if (AIChatCommandService.isCommandText(text)) {
                AIChatCommand__mdt command = AIChatCommandService.findCommand(AIChatCommandService.getCommandToken(text), request.agentId, request.objectApiName);
                if (command == null) return failSend(result, AIAssistApplicationConstants.CHAT_SEND_STATUS_ERROR, AIChatCommandService.getCommandToken(text) + ' isn\'t a command here. Type / to see the list.');
                if (String.isNotBlank(command.PromptText__c)) messageBody = text + AIAssistApplicationConstants.CHAT_COMMAND_PROMPT_SEPARATOR + command.PromptText__c;
            }

            try {

                AIConversationMessage__c userMessage = AIConversationMessageService.sendMessage(request.conversationId, request.agentId, messageBody, request.channel, request.objectApiName, request.recordId);

                result.status = AIAssistApplicationConstants.CHAT_SEND_STATUS_SENT;
                result.conversationId = userMessage.AIConversation__c;
                result.isNewConversation = request.conversationId != userMessage.AIConversation__c;
                result.userMessage = AIChatConversationService.toChatMessage(userMessage, new Map<Id, AIWorkflowAction__c>(), null, null);

            } catch (AIConversationMessageService.AIConversationMessageServiceException refusal) {
                // Already logged by the service - only translated here. Unexpected failures ("Failed to ...") can carry system detail, so the user gets a plain message instead.
                result.status = classifySendRefusal(refusal.getMessage());
                Boolean isUnexpectedFailure = result.status == AIAssistApplicationConstants.CHAT_SEND_STATUS_ERROR && refusal.getMessage().startsWith('Failed to');
                result.message = isUnexpectedFailure ? 'Your message couldn\'t be sent. Please try again.' : refusal.getMessage();
            }

            result.usage = AIChatUsageService.buildUsageState(AIChatStateService.getUserSettings());
            return result;

        } catch (Exception ex) {
            throw toAuraException(ex, 'sendMessage');
        }
    }

    // "Try again" after a failed reply, and "Regenerate" on the newest reply - re-runs the newest user message.
    @AuraEnabled
    public static void retryLatestMessage(Id conversationId) {
        try {

            AIChatConversationService.assertOwnsConversation(conversationId);
            AIConversationMessageService.retryLatestMessage(conversationId);

        } catch (AIConversationMessageService.AIConversationMessageServiceException refusal) {
            throw newAuraException(refusal.getMessage());
        } catch (Exception ex) {
            throw toAuraException(ex, 'retryLatestMessage');
        }
    }

    // The user ending a conversation from the window's menu.
    @AuraEnabled
    public static void closeConversation(Id conversationId) {
        try {

            AIChatConversationService.assertOwnsConversation(conversationId);
            AIConversationMessageService.closeConversation(conversationId, AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_USER_CLOSED);

        } catch (Exception ex) {
            throw toAuraException(ex, 'closeConversation');
        }
    }

    // Opens one of the user's conversations from the history panel.
    @AuraEnabled
    public static AIChatDataStructure.ConversationView openConversation(Id conversationId) {
        try {

            AIChatConversationService.assertOwnsConversation(conversationId);

            AIChatDataStructure.UiSettings ui = AIChatStateService.buildUiSettings(AIAssistUISettings__c.getInstance());
            AIChatDataStructure.UserState user = AIChatStateService.buildUserState(AIChatStateService.getUserSettings());

            return AIChatConversationService.buildConversationView(conversationId, ui.messagePageSize, user, ui);

        } catch (Exception ex) {
            throw toAuraException(ex, 'openConversation');
        }
    }

    // Reopens a Closed conversation so it can be continued - only when its Agent allows resuming (AIAgent__c.AllowConversationResume__c).
    @AuraEnabled
    public static AIChatDataStructure.ConversationView resumeConversation(Id conversationId) {
        try {

            AIChatConversationService.resumeConversation(conversationId);
            return openConversation(conversationId);

        } catch (AIChatDataStructure.AIChatControllerException refusal) {
            throw newAuraException(refusal.getMessage());
        } catch (Exception ex) {
            throw toAuraException(ex, 'resumeConversation');
        }
    }

    // The history panel's list - the user's own conversations, newest activity first. onlyThisRecord narrows it to recordId. Search is done in the browser over the returned titles.
    @AuraEnabled
    public static List<AIChatDataStructure.ConversationSummary> getConversationHistory(String recordId, Boolean onlyThisRecord) {
        try {

            return AIChatConversationService.getConversationHistory(recordId, onlyThisRecord);

        } catch (Exception ex) {
            throw toAuraException(ex, 'getConversationHistory');
        }
    }

    // Thumbs up / down on an AI reply.
    @AuraEnabled
    public static void submitFeedback(Id messageId, String rating, String reason, String comment) {
        try {

            AIChatFeedbackService.submitFeedback(messageId, rating, reason, comment);

        } catch (AIChatDataStructure.AIChatControllerException refusal) {
            throw newAuraException(refusal.getMessage());
        } catch (Exception ex) {
            throw toAuraException(ex, 'submitFeedback');
        }
    }

    // "Agree and continue" on the first-run terms screen.
    @AuraEnabled
    public static void acknowledgeTerms() {
        try {

            AIChatFeedbackService.acknowledgeTerms();

        } catch (Exception ex) {
            throw toAuraException(ex, 'acknowledgeTerms');
        }
    }

    // Runs the Workflow Action suggested on an AI reply, when the user clicks it. Only while suggested actions are allowed for the user.
    @AuraEnabled
    public static AIChatDataStructure.ActionResult runSuggestedAction(Id messageId, String inputsJson) {
        try {

            AIConversationMessage__c message = AIChatConversationService.assertOwnsAgentMessage(messageId);

            AIChatDataStructure.UiSettings ui = AIChatStateService.buildUiSettings(AIAssistUISettings__c.getInstance());
            AIChatDataStructure.UserState user = AIChatStateService.buildUserState(AIChatStateService.getUserSettings());

            if (!ui.inlineActionsEnabled || !user.workflowActionsEnabled) throw new AIChatDataStructure.AIChatControllerException('Suggested actions are turned off for you.');

            return AIChatActionService.run(message, inputsJson);

        } catch (AIChatDataStructure.AIChatControllerException refusal) {
            throw newAuraException(refusal.getMessage());
        } catch (Exception ex) {
            throw toAuraException(ex, 'runSuggestedAction');
        }
    }

    // Debug mode's request trace for one AI reply. Only for users with AIUserSettings__c.DebugModeEnabled__c.
    @AuraEnabled
    public static AIChatDataStructure.DebugTrace getDebugTrace(Id messageId) {
        try {

            if (!AIChatStateService.buildUserState(AIChatStateService.getUserSettings()).debugMode) throw new AIChatDataStructure.AIChatControllerException('Debug mode is off for your user.');

            AIConversationMessage__c reply = AIChatConversationService.assertOwnsAgentMessage(messageId);
            return AIChatDebugService.getDebugTrace(reply);

        } catch (AIChatDataStructure.AIChatControllerException refusal) {
            throw newAuraException(refusal.getMessage());
        } catch (Exception ex) {
            throw toAuraException(ex, 'getDebugTrace');
        }
    }

    // Debug mode's PII masking pairs for the reply's conversation - same gate as getDebugTrace.
    @AuraEnabled
    public static String getPiiMappings(Id messageId) {
        try {

            if (!AIChatStateService.buildUserState(AIChatStateService.getUserSettings()).debugMode) throw new AIChatDataStructure.AIChatControllerException('Debug mode is off for your user.');

            AIConversationMessage__c reply = AIChatConversationService.assertOwnsAgentMessage(messageId);
            return AIChatDebugService.getPiiMappings(reply.AIConversation__c);

        } catch (AIChatDataStructure.AIChatControllerException refusal) {
            throw newAuraException(refusal.getMessage());
        } catch (Exception ex) {
            throw toAuraException(ex, 'getPiiMappings');
        }
    }

    // Shown on the "Couldn't reach the AI service" card.
    @AuraEnabled
    public static AIChatDataStructure.FailureDetail getFailureDetail(Id conversationId) {
        try {

            AIChatConversationService.assertOwnsConversation(conversationId);
            Boolean debugMode = AIChatStateService.buildUserState(AIChatStateService.getUserSettings()).debugMode;

            return AIChatDebugService.getFailureDetail(conversationId, debugMode);

        } catch (Exception ex) {
            throw toAuraException(ex, 'getFailureDetail');
        }
    }

    // A plain-text transcript of the conversation - only for users with AIUserSettings__c.ConversationExportEnabled__c.
    @AuraEnabled
    public static String exportConversation(Id conversationId) {
        try {

            if (!AIChatStateService.buildUserState(AIChatStateService.getUserSettings()).exportEnabled) throw new AIChatDataStructure.AIChatControllerException('Exporting conversations is turned off for you.');

            AIChatConversationService.assertOwnsConversation(conversationId);
            return AIChatConversationService.exportConversation(conversationId);

        } catch (AIChatDataStructure.AIChatControllerException refusal) {
            throw newAuraException(refusal.getMessage());
        } catch (Exception ex) {
            throw toAuraException(ex, 'exportConversation');
        }
    }

    // =============================================================
    // Guards and helpers
    // =============================================================

    // Maps AIConversationMessageService's refusal messages onto how the window shows them: LIMIT refreshes the usage banner, BLOCKED shows the "Not sent" card.
    private static String classifySendRefusal(String refusalMessage) {

        String message = refusalMessage == null ? '' : refusalMessage;

        if (message.contains('reached your limit') || message.contains('reached your usage limit')) return AIAssistApplicationConstants.CHAT_SEND_STATUS_LIMIT;
        if (message.contains('is not enabled for your account') || message.contains('is not active') || message == AIAssistApplicationConstants.NEW_CONVERSATIONS_PAUSED_MESSAGE) return AIAssistApplicationConstants.CHAT_SEND_STATUS_BLOCKED;

        return AIAssistApplicationConstants.CHAT_SEND_STATUS_ERROR;
    }

    private static AIChatDataStructure.SendResult failSend(AIChatDataStructure.SendResult result, String status, String message) {
        result.status = status;
        result.message = message;
        return result;
    }

    // Logs the unexpected failure once and hands the LWC a readable message (AuraHandledException's message is otherwise hidden in tests).
    private static AuraHandledException toAuraException(Exception ex, String methodName) {
        AIPlatformLogManager.logException(ex, 'AIChatController', methodName);
        return newAuraException(ex instanceof AIChatDataStructure.AIChatControllerException ? ex.getMessage() : 'Something went wrong in AI Assist. Please try again.');
    }

    private static AuraHandledException newAuraException(String message) {
        AuraHandledException auraException = new AuraHandledException(message);
        auraException.setMessage(message);
        return auraException;
    }
}