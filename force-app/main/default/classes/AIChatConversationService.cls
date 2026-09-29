/*
Class Name: AIChatConversationService

=================================================================
=================================================================

Description: Everything about loading and listing AIConversation__c / AIConversationMessage__c
records for display - the Active conversation a chat window auto-loads (findActiveConversation),
opening one (buildConversationView), paging through its messages oldest-first (loadMessagePage,
loadMessagesAfter), the history panel's list (getConversationHistory), reopening a Closed one
(resumeConversation) and a plain-text transcript (exportConversation).

Also the two ownership guards (assertOwnsConversation, assertOwnsAgentMessage) - every
conversation-bound method only acts on conversations the running user owns, so these are called
first by this class and by every other AIChatController service that's handed a conversation or
message Id.

Sending and processing a message is still owned by AIConversationMessageService (validation,
locking, async job) - this class only translates its records into what the chat window displays.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-28     Chandler Stuart          Split out of AIChatController.
1.1          2026-09-29     Chandler Stuart          Message queries run WITH SYSTEM_MODE - their Execution Step subquery reads AIDataSource__r, which AI Assist Users can't access, so the conversation failed to load for them.
*/

public with sharing class AIChatConversationService {

    // Throws unless the running user owns the conversation. Returns it with the fields the callers need.
    public static AIConversation__c assertOwnsConversation(Id conversationId) {

        if (conversationId == null || conversationId.getSobjectType() != AIConversation__c.SObjectType) throw new AIChatDataStructure.AIChatControllerException('A valid AI Conversation Id is required.');

        List<AIConversation__c> conversations = [ SELECT Id, Status__c, AIAgent__c, ProcessingLockedUntil__c, RelatedRecordId__c
                                                  FROM AIConversation__c
                                                  WHERE Id = :conversationId AND OwnerId = :UserInfo.getUserId()
                                                  LIMIT 1 ];

        if (conversations.isEmpty()) throw new AIChatDataStructure.AIChatControllerException('AI Conversation not found.');
        return conversations[0];
    }

    // Throws unless messageId is an AI Agent reply in a conversation the running user owns.
    public static AIConversationMessage__c assertOwnsAgentMessage(Id messageId) {

        if (messageId == null || messageId.getSobjectType() != AIConversationMessage__c.SObjectType) throw new AIChatDataStructure.AIChatControllerException('A valid message Id is required.');

        List<AIConversationMessage__c> messages = [ SELECT Id, AIConversation__c, AIConversation__r.Name, AIConversation__r.PublicId__c, AIConversation__r.RelatedRecordId__c, Sender__c, TokenCount__c, SuggestedWorkflowActionId__c, CreatedDate
                                                    FROM AIConversationMessage__c
                                                    WHERE Id = :messageId AND AIConversation__r.OwnerId = :UserInfo.getUserId()
                                                    LIMIT 1 ];

        if (messages.isEmpty() || messages[0].Sender__c != AIAssistApplicationConstants.SENDER_AI_AGENT) throw new AIChatDataStructure.AIChatControllerException('AI reply not found.');
        return messages[0];
    }

    // The user's newest Active conversation with this Agent on this record (or with no record, when there's no record context).
    public static AIConversation__c findActiveConversation(Id agentId, Id recordId) {

        String relatedRecordId = recordId == null ? null : String.valueOf(recordId);

        List<AIConversation__c> conversations = [ SELECT Id, Name, Status__c, ConversationCloseReason__c, AIAgent__r.Name, MessageCount__c, RelatedRecordId__c, RelatedObjectAPIName__c, LastModifiedDate,
                                                    (SELECT MessageBody__c FROM AIConversationMessages__r WHERE Sender__c = :AIAssistApplicationConstants.SENDER_USER ORDER BY CreatedDate ASC LIMIT 1)
                                                  FROM AIConversation__c
                                                  WHERE OwnerId = :UserInfo.getUserId()
                                                  AND AIAgent__c = :agentId
                                                  AND RelatedRecordId__c = :relatedRecordId
                                                  AND Status__c = :AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE
                                                  ORDER BY LastModifiedDate DESC
                                                  LIMIT 1 ];

        return conversations.isEmpty() ? null : conversations[0];
    }

    // Reopens a Closed conversation so it can be continued - only when its Agent allows resuming (AIAgent__c.AllowConversationResume__c).
    public static void resumeConversation(Id conversationId) {

        AIConversation__c conversation = assertOwnsConversation(conversationId);

        List<AIAgent__c> agents = [ SELECT Id, IsActive__c, AllowConversationResume__c, RetentionTrigger__c FROM AIAgent__c WHERE Id = :conversation.AIAgent__c LIMIT 1 ];

        Boolean canResume = !agents.isEmpty() && agents[0].IsActive__c && agents[0].AllowConversationResume__c && conversation.Status__c == AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED;
        if (!canResume) throw new AIChatDataStructure.AIChatControllerException('This conversation can\'t be continued. Start a new one instead.');

        AIConversation__c reopened = new AIConversation__c(
            Id = conversationId,
            Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE,
            ConversationCloseReason__c = null,
            ConversationClosedTimestamp__c = null
        );

        // A close-date retention expiry no longer applies once it's open again - recalculated the next time it closes.
        if (agents[0].RetentionTrigger__c == AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CLOSED_DATE) reopened.RetentionExpiryDate__c = null;

        update reopened;
    }

    // The history panel's list - the user's own conversations, newest activity first. onlyThisRecord narrows it to recordId. Search is done in the browser over the returned titles.
    public static List<AIChatDataStructure.ConversationSummary> getConversationHistory(String recordId, Boolean onlyThisRecord) {

        Id userId = UserInfo.getUserId();
        String relatedRecordId = String.isBlank(recordId) ? null : String.valueOf(Id.valueOf(recordId));
        Boolean filterByRecord = onlyThisRecord == true && relatedRecordId != null;

        List<AIConversation__c> conversations;

        if (filterByRecord) {
            conversations = [ SELECT Id, Name, Status__c, ConversationCloseReason__c, AIAgent__r.Name, MessageCount__c, RelatedRecordId__c, RelatedObjectAPIName__c, LastModifiedDate,
                                (SELECT MessageBody__c FROM AIConversationMessages__r WHERE Sender__c = :AIAssistApplicationConstants.SENDER_USER ORDER BY CreatedDate ASC LIMIT 1)
                              FROM AIConversation__c
                              WHERE OwnerId = :userId AND RelatedRecordId__c = :relatedRecordId
                              ORDER BY LastModifiedDate DESC
                              LIMIT :AIAssistApplicationConstants.CHAT_HISTORY_MAX_CONVERSATIONS ];
        } else {
            conversations = [ SELECT Id, Name, Status__c, ConversationCloseReason__c, AIAgent__r.Name, MessageCount__c, RelatedRecordId__c, RelatedObjectAPIName__c, LastModifiedDate,
                                (SELECT MessageBody__c FROM AIConversationMessages__r WHERE Sender__c = :AIAssistApplicationConstants.SENDER_USER ORDER BY CreatedDate ASC LIMIT 1)
                              FROM AIConversation__c
                              WHERE OwnerId = :userId
                              ORDER BY LastModifiedDate DESC
                              LIMIT :AIAssistApplicationConstants.CHAT_HISTORY_MAX_CONVERSATIONS ];
        }

        List<AIChatDataStructure.ConversationSummary> summaries = new List<AIChatDataStructure.ConversationSummary>();
        for (AIConversation__c conversation : conversations) summaries.add(toConversationSummary(conversation));

        return summaries;
    }

    // A plain-text transcript of the conversation - command instructions and System messages are left out. Only for callers that have already checked AIUserSettings__c.ConversationExportEnabled__c.
    public static String exportConversation(Id conversationId) {

        List<AIConversation__c> withAgent = [ SELECT Name, AIAgent__r.Name, CreatedDate FROM AIConversation__c WHERE Id = :conversationId LIMIT 1 ];
        String agentName = withAgent[0].AIAgent__r == null ? 'AI Agent' : withAgent[0].AIAgent__r.Name;

        List<String> lines = new List<String>{ withAgent[0].Name + ' - ' + agentName, 'Exported ' + System.now().format(), '' };
        Map<String, String> realValueByFakeValue = AIChatDebugService.getRealValueByFakeValue(conversationId);

        for (AIConversationMessage__c message : [ SELECT Sender__c, MessageBody__c, CreatedDate
                                                  FROM AIConversationMessage__c
                                                  WHERE AIConversation__c = :conversationId AND Sender__c != :AIAssistApplicationConstants.SENDER_SYSTEM
                                                  ORDER BY CreatedDate ASC, Id ASC ]) {
            String speaker = message.Sender__c == AIAssistApplicationConstants.SENDER_USER ? UserInfo.getName() : agentName;
            lines.add('[' + message.CreatedDate.format() + '] ' + speaker + ':');
            String displayText = AIChatCommandService.getDisplayText(message.MessageBody__c);
            lines.add(message.Sender__c == AIAssistApplicationConstants.SENDER_AI_AGENT ? AIChatDebugService.restorePii(displayText, realValueByFakeValue) : displayText);
            lines.add('');
        }

        return String.join(lines, '\n');
    }

    public static AIChatDataStructure.ConversationView buildConversationView(Id conversationId, Integer pageSize, AIChatDataStructure.UserState user, AIChatDataStructure.UiSettings ui) {

        AIConversation__c conversation = [ SELECT Id, Name, Status__c, ConversationCloseReason__c, AIAgent__c, AIAgent__r.Name, AIAgent__r.IsActive__c, AIAgent__r.AllowConversationResume__c,
                                                  RelatedRecordId__c, RelatedObjectAPIName__c, ProcessingLockedUntil__c,
                                                  (SELECT MessageBody__c FROM AIConversationMessages__r WHERE Sender__c = :AIAssistApplicationConstants.SENDER_USER ORDER BY CreatedDate ASC LIMIT 1)
                                           FROM AIConversation__c
                                           WHERE Id = :conversationId
                                           LIMIT 1 ];

        AIChatDataStructure.ConversationView view = new AIChatDataStructure.ConversationView();
        view.id = conversation.Id;
        view.name = conversation.Name;
        view.title = getConversationTitle(conversation);
        view.status = conversation.Status__c;
        view.closeReason = conversation.ConversationCloseReason__c;
        view.agentId = conversation.AIAgent__c;
        view.agentName = conversation.AIAgent__r == null ? null : conversation.AIAgent__r.Name;
        view.isActive = conversation.Status__c == AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE;
        view.canResume = conversation.Status__c == AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED && conversation.AIAgent__r != null && conversation.AIAgent__r.IsActive__c && conversation.AIAgent__r.AllowConversationResume__c;
        view.isProcessing = conversation.ProcessingLockedUntil__c != null && conversation.ProcessingLockedUntil__c > System.now();
        view.relatedRecordId = conversation.RelatedRecordId__c;
        view.relatedObjectApiName = conversation.RelatedObjectAPIName__c;

        AIChatDataStructure.MessagePage page = loadMessagePage(conversationId, null, pageSize, user, ui);
        view.messages = page.messages;
        view.hasMoreMessages = page.hasMore;

        return view;
    }

    // The message queries below run WITH SYSTEM_MODE: SOQL at this API version enforces object/field access, and the Sources chips read AIDataSource__r.DeveloperName__c,
    // which AI Assist Users have no access to (Data Source configuration isn't theirs to see). Sharing still applies - with sharing, and every caller has checked ownership.
    // One page of displayable messages, oldest first. Queried newest-first with one extra row to learn whether there are more. System messages (failed-turn audit rows) are never shown.
    public static AIChatDataStructure.MessagePage loadMessagePage(Id conversationId, Id beforeMessageId, Integer pageSize, AIChatDataStructure.UserState user, AIChatDataStructure.UiSettings ui) {

        Set<String> visibleSenders = new Set<String>{ AIAssistApplicationConstants.SENDER_USER, AIAssistApplicationConstants.SENDER_AI_AGENT };
        Integer rowsToQuery = pageSize + 1;
        Id userId = UserInfo.getUserId();

        List<AIConversationMessage__c> newestFirst;

        if (beforeMessageId == null) {
            newestFirst = [ SELECT Id, AIConversation__c, Sender__c, MessageBody__c, TokenCount__c, SuggestedWorkflowActionId__c, CreatedDate,
                                (SELECT StepOrder__c, Status__c, StepDetail__c, DurationMilliseconds__c, AIDataSource__c, AIDataSource__r.DeveloperName__c, AIWorkflowAction__c, AIWorkflowAction__r.ActionName__c FROM AIExecutionSteps__r ORDER BY StepOrder__c),
                                (SELECT Rating__c FROM AIFeedbacks__r WHERE CreatedById = :userId ORDER BY CreatedDate DESC LIMIT 1)
                            FROM AIConversationMessage__c
                            WHERE AIConversation__c = :conversationId AND Sender__c IN :visibleSenders
                            WITH SYSTEM_MODE
                            ORDER BY CreatedDate DESC, Id DESC
                            LIMIT :rowsToQuery ];
        } else {
            AIConversationMessage__c boundary = [ SELECT CreatedDate FROM AIConversationMessage__c WHERE Id = :beforeMessageId LIMIT 1 ];
            Datetime boundaryDate = boundary.CreatedDate;

            newestFirst = [ SELECT Id, AIConversation__c, Sender__c, MessageBody__c, TokenCount__c, SuggestedWorkflowActionId__c, CreatedDate,
                                (SELECT StepOrder__c, Status__c, StepDetail__c, DurationMilliseconds__c, AIDataSource__c, AIDataSource__r.DeveloperName__c, AIWorkflowAction__c, AIWorkflowAction__r.ActionName__c FROM AIExecutionSteps__r ORDER BY StepOrder__c),
                                (SELECT Rating__c FROM AIFeedbacks__r WHERE CreatedById = :userId ORDER BY CreatedDate DESC LIMIT 1)
                            FROM AIConversationMessage__c
                            WHERE AIConversation__c = :conversationId AND Sender__c IN :visibleSenders
                            AND (CreatedDate < :boundaryDate OR (CreatedDate = :boundaryDate AND Id < :beforeMessageId))
                            WITH SYSTEM_MODE
                            ORDER BY CreatedDate DESC, Id DESC
                            LIMIT :rowsToQuery ];
        }

        AIChatDataStructure.MessagePage page = new AIChatDataStructure.MessagePage();
        page.hasMore = newestFirst.size() > pageSize;
        if (page.hasMore) newestFirst.remove(newestFirst.size() - 1);

        List<AIConversationMessage__c> oldestFirst = new List<AIConversationMessage__c>();
        for (Integer messageIndex = newestFirst.size() - 1; messageIndex >= 0; messageIndex--) oldestFirst.add(newestFirst[messageIndex]);

        page.messages = toChatMessages(oldestFirst, user, ui);
        return page;
    }

    // Every displayable message newer than afterMessageId (all of them when it's blank), oldest first.
    public static List<AIChatDataStructure.ChatMessage> loadMessagesAfter(Id conversationId, Id afterMessageId, AIChatDataStructure.UserState user, AIChatDataStructure.UiSettings ui) {

        Set<String> visibleSenders = new Set<String>{ AIAssistApplicationConstants.SENDER_USER, AIAssistApplicationConstants.SENDER_AI_AGENT };
        Id userId = UserInfo.getUserId();

        List<AIConversationMessage__c> boundary = afterMessageId == null ? new List<AIConversationMessage__c>() : [ SELECT CreatedDate FROM AIConversationMessage__c WHERE Id = :afterMessageId LIMIT 1 ];

        List<AIConversationMessage__c> messages;

        if (boundary.isEmpty()) {
            messages = [ SELECT Id, AIConversation__c, Sender__c, MessageBody__c, TokenCount__c, SuggestedWorkflowActionId__c, CreatedDate,
                             (SELECT StepOrder__c, Status__c, StepDetail__c, DurationMilliseconds__c, AIDataSource__c, AIDataSource__r.DeveloperName__c, AIWorkflowAction__c, AIWorkflowAction__r.ActionName__c FROM AIExecutionSteps__r ORDER BY StepOrder__c),
                             (SELECT Rating__c FROM AIFeedbacks__r WHERE CreatedById = :userId ORDER BY CreatedDate DESC LIMIT 1)
                         FROM AIConversationMessage__c
                         WHERE AIConversation__c = :conversationId AND Sender__c IN :visibleSenders
                         WITH SYSTEM_MODE
                         ORDER BY CreatedDate ASC, Id ASC
                         LIMIT 200 ];
        } else {
            Datetime boundaryDate = boundary[0].CreatedDate;

            messages = [ SELECT Id, AIConversation__c, Sender__c, MessageBody__c, TokenCount__c, SuggestedWorkflowActionId__c, CreatedDate,
                             (SELECT StepOrder__c, Status__c, StepDetail__c, DurationMilliseconds__c, AIDataSource__c, AIDataSource__r.DeveloperName__c, AIWorkflowAction__c, AIWorkflowAction__r.ActionName__c FROM AIExecutionSteps__r ORDER BY StepOrder__c),
                             (SELECT Rating__c FROM AIFeedbacks__r WHERE CreatedById = :userId ORDER BY CreatedDate DESC LIMIT 1)
                         FROM AIConversationMessage__c
                         WHERE AIConversation__c = :conversationId AND Sender__c IN :visibleSenders
                         AND (CreatedDate > :boundaryDate OR (CreatedDate = :boundaryDate AND Id > :afterMessageId))
                         WITH SYSTEM_MODE
                         ORDER BY CreatedDate ASC, Id ASC
                         LIMIT 200 ];
        }

        return toChatMessages(messages, user, ui);
    }

    // Resolves every suggested Workflow Action on the page in one query, then maps each message.
    private static List<AIChatDataStructure.ChatMessage> toChatMessages(List<AIConversationMessage__c> messages, AIChatDataStructure.UserState user, AIChatDataStructure.UiSettings ui) {

        Map<Id, AIWorkflowAction__c> actionsById = new Map<Id, AIWorkflowAction__c>();
        Boolean showActions = ui.inlineActionsEnabled && user.workflowActionsEnabled;

        if (showActions) {
            Set<Id> actionIds = new Set<Id>();
            for (AIConversationMessage__c message : messages) {
                Id actionId = AIChatDataStructure.toIdOrNull(message.SuggestedWorkflowActionId__c);
                if (actionId != null) actionIds.add(actionId);
            }
            if (!actionIds.isEmpty()) {
                actionsById = new Map<Id, AIWorkflowAction__c>([ SELECT Id, ActionName__c, Description__c, RequiresConfirmation__c, ConfirmationMessage__c, InputSchema__c
                                                                  FROM AIWorkflowAction__c WHERE Id IN :actionIds AND IsActive__c = true ]);
            }
        }

        List<AIChatDataStructure.ChatMessage> chatMessages = new List<AIChatDataStructure.ChatMessage>();
        Map<Id, Map<String, String>> realValueByFakeValueByConversation = new Map<Id, Map<String, String>>();

        for (AIConversationMessage__c message : messages) {

            AIChatDataStructure.ChatMessage chatMessage = toChatMessage(message, actionsById, message.AIExecutionSteps__r, message.AIFeedbacks__r);

            if (chatMessage.sender == 'agent') {
                if (!realValueByFakeValueByConversation.containsKey(message.AIConversation__c)) realValueByFakeValueByConversation.put(message.AIConversation__c, AIChatDebugService.getRealValueByFakeValue(message.AIConversation__c));
                chatMessage.displayText = AIChatDebugService.restorePii(chatMessage.displayText, realValueByFakeValueByConversation.get(message.AIConversation__c));
            }

            chatMessages.add(chatMessage);
        }

        return chatMessages;
    }

    public static AIChatDataStructure.ChatMessage toChatMessage(AIConversationMessage__c message, Map<Id, AIWorkflowAction__c> actionsById, List<AIExecutionStep__c> steps, List<AIFeedback__c> feedback) {

        AIChatDataStructure.ChatMessage chatMessage = new AIChatDataStructure.ChatMessage();
        chatMessage.id = message.Id;
        chatMessage.conversationId = message.AIConversation__c;
        chatMessage.sender = message.Sender__c == AIAssistApplicationConstants.SENDER_USER ? 'user' : 'agent';
        chatMessage.displayText = AIChatCommandService.getDisplayText(message.MessageBody__c);
        chatMessage.createdDate = message.CreatedDate == null ? System.now() : message.CreatedDate;
        chatMessage.tokenCount = message.TokenCount__c;

        if (chatMessage.sender == 'user' && AIChatCommandService.isCommandText(chatMessage.displayText)) {
            chatMessage.isCommand = true;
            chatMessage.commandName = AIChatCommandService.getCommandToken(chatMessage.displayText);
        }

        if (feedback != null && !feedback.isEmpty()) chatMessage.feedbackRating = feedback[0].Rating__c;

        Set<Id> ranActionIds = new Set<Id>();
        Set<String> sourceNames = new Set<String>();

        if (steps != null) {
            for (AIExecutionStep__c step : steps) {
                chatMessage.steps.add(toExecutionStep(step));
                if (step.AIDataSource__c != null && step.AIDataSource__r != null) sourceNames.add(AIChatDataStructure.humanise(step.AIDataSource__r.DeveloperName__c));
                if (step.AIWorkflowAction__c != null && step.Status__c == AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS) ranActionIds.add(step.AIWorkflowAction__c);
            }
        }
        chatMessage.sources.addAll(sourceNames);

        Id actionId = AIChatDataStructure.toIdOrNull(message.SuggestedWorkflowActionId__c);
        if (actionId != null && actionsById.containsKey(actionId)) {
            chatMessage.suggestedAction = AIChatActionService.toSuggestedAction(actionsById.get(actionId));
            chatMessage.suggestedAction.hasRun = ranActionIds.contains(actionId);
        }

        return chatMessage;
    }

    public static AIChatDataStructure.ExecutionStep toExecutionStep(AIExecutionStep__c step) {

        AIChatDataStructure.ExecutionStep executionStep = new AIChatDataStructure.ExecutionStep();
        executionStep.stepOrder = step.StepOrder__c == null ? null : step.StepOrder__c.intValue();
        executionStep.status = step.Status__c;
        executionStep.isSuccess = step.Status__c == AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS;
        executionStep.durationMs = step.DurationMilliseconds__c == null ? null : step.DurationMilliseconds__c.longValue();

        if (String.isNotBlank(step.StepDetail__c)) executionStep.label = step.StepDetail__c;
        else if (step.AIDataSource__r != null) executionStep.label = 'Read ' + AIChatDataStructure.humanise(step.AIDataSource__r.DeveloperName__c);
        else if (step.AIWorkflowAction__r != null) executionStep.label = 'Ran ' + step.AIWorkflowAction__r.ActionName__c;
        else if (step.AIDataSource__c == null && step.AIWorkflowAction__c == null) executionStep.label = 'Provider callout'; // AIExecutionStepRecorder's callout-type step - no Data Source or Workflow Action to name.
        else executionStep.label = 'Step ' + executionStep.stepOrder;

        return executionStep;
    }

    public static AIChatDataStructure.ConversationSummary toConversationSummary(AIConversation__c conversation) {

        AIChatDataStructure.ConversationSummary summary = new AIChatDataStructure.ConversationSummary();
        summary.id = conversation.Id;
        summary.title = getConversationTitle(conversation);
        summary.status = conversation.Status__c;
        summary.closeReason = conversation.ConversationCloseReason__c;
        summary.agentName = conversation.AIAgent__r == null ? null : conversation.AIAgent__r.Name;
        summary.messageCount = conversation.MessageCount__c == null ? 0 : conversation.MessageCount__c.intValue();
        summary.lastActivity = conversation.LastModifiedDate;
        summary.relatedRecordId = conversation.RelatedRecordId__c;
        summary.relatedObjectApiName = conversation.RelatedObjectAPIName__c;

        return summary;
    }

    // A conversation has no title field - it's named after its first user message.
    private static String getConversationTitle(AIConversation__c conversation) {

        List<AIConversationMessage__c> firstMessages = conversation.AIConversationMessages__r;
        if (firstMessages == null || firstMessages.isEmpty()) return conversation.Name;

        String firstLine = AIChatCommandService.getDisplayText(firstMessages[0].MessageBody__c).normalizeSpace();
        return firstLine.abbreviate(AIAssistApplicationConstants.CHAT_CONVERSATION_TITLE_MAX_LENGTH);
    }
}