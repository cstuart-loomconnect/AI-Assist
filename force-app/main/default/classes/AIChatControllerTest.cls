/*
Class Name: AIChatControllerTest

=================================================================
=================================================================

Description: Testing utility for AIChatController.

Sends never wrap sendMessage in Test.startTest/stopTest - the enqueued AiMessageProcessingQueueable
would otherwise run and attempt a provider callout. Only the controller's own work is under test.

=================================================================
=================================================================
Applicable Classes:

AIChatController, AIChatDataStructure, AIChatStateService, AIChatContextService, AIChatCommandService,
AIChatUsageService, AIChatConversationService, AIChatActionService, AIChatFeedbackService,
AIChatDebugService

Version      Date               Author                   Description
1.0          2026-09-27         Chandler Stuart          Initial development
1.1          2026-09-27         Chandler Stuart          Added testScenario13 (PII restored on read).
1.2          2026-09-27         Chandler Stuart          testScenario10 covers getPiiMappings.
1.3          2026-09-27         Chandler Stuart          Commands are in-memory AIChatCommand__mdt records (AIChatCommandService.testCommands) - scenario 1 also covers Agent, AvailableTo__c and display order filtering; scenario 12 the AvailableTo__c levels.
1.4          2026-09-28         Chandler Stuart          AIChatController split into AIChatDataStructure and eight services - references updated to where each type/method now lives; no scenario or assertion changed.
*/

@IsTest private class AIChatControllerTest {

    // testScenario1: A READY context on an Account record - the object's Agent is picked first, its commands (only active ones for this object, any Agent and the user's type, in Display Order), PII protection, usage and the user's Active conversation (auto-loaded) all come back.
    // testScenario2: Each blocking state - app off (INACTIVE), maintenance (MAINTENANCE), channel not allowed (CHANNEL_DISABLED), terms not agreed (TERMS) and no Agent (NO_AGENT) - is returned in priority order.
    // testScenario3: A Manual Only Agent doesn't auto-load the Active conversation, but still offers it as openConversation.
    // testScenario4: sendMessage - a plain message starts a conversation; the next one continues it; a command is expanded with its hidden Prompt Text and shown as the command only; an unknown command and a blank message come back as ERROR without sending.
    // testScenario5: sendMessage refusals - a disallowed channel comes back BLOCKED and a reached usage limit comes back LIMIT, with the usage flags set.
    // testScenario6: getConversationUpdate returns only messages after the given one (never System messages), and getEarlierMessages pages backwards by MaxVisibleMessageHistory__c.
    // testScenario7: submitFeedback saves one rating per user per message (replacing it on a second rating, with the reason prefixed to the comment) and rejects an invalid rating.
    // testScenario8: acknowledgeTerms records the current terms version, clearing the TERMS state.
    // testScenario9: runSuggestedAction runs the Workflow Action suggested on the reply, records an Execution Step, and the reply then shows the action as run; it refuses when inline actions are turned off.
    // testScenario10: Debug trace, PII mappings, failure detail and export are each gated by the user's settings, and return the conversation's details when allowed.
    // testScenario11: closeConversation, openConversation, resumeConversation and getConversationHistory - including refusing another user's conversation and a resume the Agent doesn't allow.
    // testScenario12: Helper parsing - input schemas become form fields, command bodies are split for display, Developer Names are humanised, AvailableTo__c levels include the ones above them.
    // testScenario13: A reply saved with fake PII values is shown and exported with the real values, longest fake value first, while the saved reply keeps the fake values.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = true;
        settings.DisableExceptionLogging__c = false;
        settings.CurrentTermsVersion__c = '2.0';
        upsert settings;

        AIAssistUISettings__c uiSettings = AIAssistUISettings__c.getOrgDefaults();
        uiSettings.IsMaintenanceMode__c = false;
        uiSettings.MaxVisibleMessageHistory__c = 2;
        upsert uiSettings;
    }

    // Terms agreed for the running user, so the context reaches READY.
    private static void agreeTerms() {
        insert new AITermsAcknowledgment__c(User__c = UserInfo.getUserId(), AcknowledgedDate__c = System.now(), TermsVersion__c = '2.0');
    }

    // Custom Metadata records can't be inserted in a test - built in memory and handed to AIChatCommandService.testCommands instead.
    private static AIChatCommand__mdt createCommand(String command, String objectApiName, Decimal displayOrder, String availableTo) {
        return new AIChatCommand__mdt(Command__c = command, Description__c = command, ObjectAPIName__c = objectApiName, DisplayOrder__c = displayOrder, AvailableTo__c = availableTo, IsActive__c = true);
    }

    private static AIAgent__c createAgent(String objectType, String loadTrigger) {
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, false)[0];
        agent.IsActive__c = true;
        agent.ObjectType__c = objectType;
        agent.ConversationLoadTrigger__c = loadTrigger;
        agent.AllowConversationResume__c = true;
        insert agent;
        return agent;
    }

    private static AIConversation__c createConversation(Id agentId, Id recordId) {
        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agentId, 1, false)[0];
        conversation.RelatedRecordId__c = recordId == null ? null : String.valueOf(recordId);
        conversation.RelatedObjectAPIName__c = recordId == null ? null : 'Account';
        insert conversation;
        return conversation;
    }

    private static AIConversationMessage__c createMessage(Id conversationId, String sender, String body) {
        AIConversationMessage__c message = new AIConversationMessage__c(AIConversation__c = conversationId, Sender__c = sender, MessageBody__c = body, TokenCount__c = 10);
        insert message;
        return message;
    }

    private static String sendRequest(Id conversationId, Id agentId, String text, Id recordId) {
        Map<String, Object> request = new Map<String, Object>{
            'conversationId' => conversationId,
            'agentId' => agentId,
            'text' => text,
            'channel' => AIAssistApplicationConstants.CHANNEL_RECORD_PAGE_CHAT,
            'recordId' => recordId,
            'objectApiName' => recordId == null ? null : 'Account'
        };
        return JSON.serialize(request);
    }

    @IsTest static void testScenario1() {

        agreeTerms();
        Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];
        AIAgent__c generalAgent = createAgent(null, null);
        AIAgent__c accountAgent = createAgent('Account', AIAssistApplicationConstants.CONVERSATION_LOAD_TRIGGER_ON_PAGE_LOAD);

        // The running user's type decides which commands are offered - set explicitly, since it depends on the org. Run as the same user to keep the User update apart from the DML below.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = UserInfo.getUserId(), AIAssistUserType__c = AIAssistApplicationConstants.USER_TYPE_STANDARD);
        }

        AIChatCommand__mdt retiredCommand = createCommand('/retired', null, 3, AIAssistApplicationConstants.CHAT_COMMAND_AVAILABLE_TO_ALL_USERS);
        retiredCommand.IsActive__c = false;
        AIChatCommand__mdt otherAgentCommand = createCommand('/other-agent', null, 4, AIAssistApplicationConstants.CHAT_COMMAND_AVAILABLE_TO_ALL_USERS);
        otherAgentCommand.AgentDeveloperName__c = 'Some_Other_Agent';

        // Listed out of order, to prove they're sorted by DisplayOrder__c.
        AIChatCommandService.testCommands = new List<AIChatCommand__mdt>{
            createCommand('/brief', null, 2, AIAssistApplicationConstants.CHAT_COMMAND_AVAILABLE_TO_ALL_USERS),
            createCommand('/admin-only', null, 1, AIAssistApplicationConstants.CHAT_COMMAND_AVAILABLE_TO_ADMINS_ONLY),
            createCommand('/opportunity-only', 'Opportunity', 1, AIAssistApplicationConstants.CHAT_COMMAND_AVAILABLE_TO_ALL_USERS),
            createCommand('/summary', 'Account', 1, AIAssistApplicationConstants.CHAT_COMMAND_AVAILABLE_TO_ALL_USERS),
            retiredCommand,
            otherAgentCommand
        };

        AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(1, 'Account', false)[0];
        registry.Active__c = true;
        registry.SyncStatus__c = AIAssistApplicationConstants.PII_SYNC_STATUS_SYNCED;
        insert registry;

        AIConversation__c conversation = createConversation(accountAgent.Id, account.Id);
        createMessage(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 'Who is the main contact?');
        createMessage(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, '**Jordan** is the main contact.');

        Test.startTest();
            AIChatDataStructure.ChatContext context = AIChatController.getChatContext(account.Id, 'Account', AIAssistApplicationConstants.CHANNEL_RECORD_PAGE_CHAT, null);
        Test.stopTest();

        Assert.areEqual(AIAssistApplicationConstants.CHAT_STATE_READY, context.state, 'Should be ready.');
        Assert.areEqual(accountAgent.Id, context.agent.id, 'The Account Agent should be picked before the general one.');
        Assert.areEqual(2, context.agents.size(), 'Both active Agents should be offered.');
        Assert.areEqual(2, context.commands.size(), 'Only active commands for this object, any Agent and a Standard User should be offered.');
        Assert.areEqual('/summary', context.commands[0].command, 'Commands should be sorted by Display Order.');
        Assert.isTrue(context.commands[0].isRecordSpecific, 'The Account command should be marked record-specific.');
        Assert.areEqual('Any record', context.commands[1].scopeLabel, 'A command with no object should apply to any record.');
        Assert.isTrue(context.record.piiProtected, 'A synced PII Registry should mark the record protected.');
        Assert.areEqual(account.Name, context.record.recordName, 'The record name should be resolved.');
        Assert.areEqual('Account', context.record.objectLabel, 'The object label should be resolved.');
        Assert.isNotNull(context.conversation, 'The Active conversation should auto-load.');
        Assert.areEqual(2, context.conversation.messages.size(), 'Both messages should load.');
        Assert.areEqual('agent', context.conversation.messages[1].sender, 'The reply should be an agent message.');
        Assert.areEqual('Who is the main contact?', context.conversation.title, 'The title should be the first user message.');
        Assert.isNotNull(context.usage, 'Usage should be returned.');

        AIChatDataStructure.ChatContext pinned = AIChatController.getChatContext(account.Id, 'Account', AIAssistApplicationConstants.CHANNEL_RECORD_PAGE_CHAT, generalAgent.Id);
        Assert.areEqual(generalAgent.Id, pinned.agent.id, 'An agentKey should pick that Agent.');
    }

    @IsTest static void testScenario2() {

        AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(UserInfo.getUserId(), false);
        userSettings.IsActive__c = true;
        userSettings.AllowedChannels__c = AIAssistApplicationConstants.CHANNEL_UTILITY_BAR;
        insert userSettings;

        Test.startTest();

            AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
            settings.IsApplicationActive__c = false;
            update settings;
            Assert.areEqual(AIAssistApplicationConstants.CHAT_STATE_INACTIVE, AIChatController.getChatContext(null, null, AIAssistApplicationConstants.CHANNEL_RECORD_PAGE_CHAT, null).state, 'App off should come first.');

            settings.IsApplicationActive__c = true;
            update settings;
            AIAssistUISettings__c uiSettings = AIAssistUISettings__c.getOrgDefaults();
            uiSettings.IsMaintenanceMode__c = true;
            update uiSettings;
            Assert.areEqual(AIAssistApplicationConstants.CHAT_STATE_MAINTENANCE, AIChatController.getChatContext(null, null, AIAssistApplicationConstants.CHANNEL_RECORD_PAGE_CHAT, null).state, 'Maintenance should come next.');

            uiSettings.IsMaintenanceMode__c = false;
            update uiSettings;
            Assert.areEqual(AIAssistApplicationConstants.CHAT_STATE_CHANNEL_DISABLED, AIChatController.getChatContext(null, null, AIAssistApplicationConstants.CHANNEL_RECORD_PAGE_CHAT, null).state, 'A channel outside the allow-list should be disabled.');

            AIChatDataStructure.ChatContext termsContext = AIChatController.getChatContext(null, null, AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, null);
            Assert.areEqual(AIAssistApplicationConstants.CHAT_STATE_TERMS, termsContext.state, 'Terms should be required until agreed.');
            Assert.areEqual('2.0', termsContext.terms.version, 'The current terms version should be returned.');

            agreeTerms();
            Assert.areEqual(AIAssistApplicationConstants.CHAT_STATE_NO_AGENT, AIChatController.getChatContext(null, null, AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, null).state, 'With no active Agent there is nothing to chat with.');

        Test.stopTest();
    }

    @IsTest static void testScenario3() {

        agreeTerms();
        Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];
        AIAgent__c agent = createAgent('Account', AIAssistApplicationConstants.CONVERSATION_LOAD_TRIGGER_MANUAL_ONLY);
        AIConversation__c conversation = createConversation(agent.Id, account.Id);
        createMessage(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 'Hello');

        Test.startTest();
            AIChatDataStructure.ChatContext context = AIChatController.getChatContext(account.Id, 'Account', AIAssistApplicationConstants.CHANNEL_RECORD_PAGE_CHAT, null);
        Test.stopTest();

        Assert.isNull(context.conversation, 'A Manual Only Agent shouldn\'t auto-load the conversation.');
        Assert.areEqual(conversation.Id, context.openConversation.id, 'The Active conversation should still be offered.');
    }

    @IsTest static void testScenario4() {

        Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];
        AIAgent__c agent = createAgent('Account', null);
        AIChatCommand__mdt riskCheck = createCommand('/risk-check', 'Account', 1, AIAssistApplicationConstants.CHAT_COMMAND_AVAILABLE_TO_ALL_USERS);
        riskCheck.PromptText__c = 'List risks to the close date.';
        AIChatCommandService.testCommands = new List<AIChatCommand__mdt>{ riskCheck };

        AIChatDataStructure.SendResult first = AIChatController.sendMessage(sendRequest(null, agent.Id, 'Summarise this account', account.Id));
        Assert.areEqual(AIAssistApplicationConstants.CHAT_SEND_STATUS_SENT, first.status, 'The first message should send.');
        Assert.isTrue(first.isNewConversation, 'The first message should start a conversation.');
        Assert.areEqual('user', first.userMessage.sender, 'The returned message should be the user\'s.');

        AIChatDataStructure.SendResult second = AIChatController.sendMessage(sendRequest(first.conversationId, agent.Id, '/risk-check focus on legal', account.Id));
        Assert.areEqual(first.conversationId, second.conversationId, 'Passing the conversation should continue it.');
        Assert.isFalse(second.isNewConversation, 'Continuing shouldn\'t start a new conversation.');
        Assert.isTrue(second.userMessage.isCommand, 'The command should be recognised.');
        Assert.areEqual('/risk-check', second.userMessage.commandName, 'The command name should be split out.');
        Assert.areEqual('/risk-check focus on legal', second.userMessage.displayText, 'Only what the user typed should be displayed.');

        AIConversationMessage__c saved = [SELECT MessageBody__c FROM AIConversationMessage__c WHERE Id = :second.userMessage.id];
        Assert.isTrue(saved.MessageBody__c.contains('List risks to the close date.'), 'The hidden prompt should be sent to the model.');

        AIChatDataStructure.SendResult unknown = AIChatController.sendMessage(sendRequest(first.conversationId, agent.Id, '/nope', account.Id));
        Assert.areEqual(AIAssistApplicationConstants.CHAT_SEND_STATUS_ERROR, unknown.status, 'An unknown command shouldn\'t send.');

        AIChatDataStructure.SendResult blank = AIChatController.sendMessage(sendRequest(first.conversationId, agent.Id, '   ', account.Id));
        Assert.areEqual(AIAssistApplicationConstants.CHAT_SEND_STATUS_ERROR, blank.status, 'A blank message shouldn\'t send.');

        Assert.areEqual(2, [SELECT COUNT() FROM AIConversationMessage__c WHERE AIConversation__c = :first.conversationId], 'Only the two valid messages should be saved.');
    }

    @IsTest static void testScenario5() {

        AIAgent__c agent = createAgent(null, null);

        AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(UserInfo.getUserId(), false);
        userSettings.IsActive__c = true;
        userSettings.AllowedChannels__c = AIAssistApplicationConstants.CHANNEL_UTILITY_BAR;
        insert userSettings;

        AIChatDataStructure.SendResult blocked = AIChatController.sendMessage(sendRequest(null, agent.Id, 'Hello', null));
        Assert.areEqual(AIAssistApplicationConstants.CHAT_SEND_STATUS_BLOCKED, blocked.status, 'A disallowed channel should be blocked.');

        userSettings.AllowedChannels__c = null;
        userSettings.UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES;
        userSettings.MaxTokensPer24Hours__c = 5;
        update userSettings;

        AIConversation__c existing = createConversation(agent.Id, null);
        createMessage(existing.Id, AIAssistApplicationConstants.SENDER_USER, 'Earlier usage');

        AIChatDataStructure.SendResult limited = AIChatController.sendMessage(sendRequest(null, agent.Id, 'Hello again', null));
        Assert.areEqual(AIAssistApplicationConstants.CHAT_SEND_STATUS_LIMIT, limited.status, 'A reached token limit should be LIMIT.');
        Assert.isTrue(limited.usage.blockMessages, 'Block New Messages should block messages once the token limit is reached.');
        Assert.isTrue(limited.usage.limitReached, 'The limit should be reported as reached.');
        Assert.isNotNull(limited.usage.resetsInMinutes, 'The reset time should be given.');
    }

    @IsTest static void testScenario6() {

        AIAgent__c agent = createAgent(null, null);
        AIConversation__c conversation = createConversation(agent.Id, null);

        AIConversationMessage__c first = createMessage(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 'One');
        createMessage(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 'Two');
        createMessage(conversation.Id, AIAssistApplicationConstants.SENDER_SYSTEM, 'AI response failed: hidden');
        AIConversationMessage__c third = createMessage(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 'Three');

        Test.startTest();
            AIChatDataStructure.ConversationUpdate conversationUpdate = AIChatController.getConversationUpdate(conversation.Id, first.Id);
            AIChatDataStructure.ConversationUpdate everything = AIChatController.getConversationUpdate(conversation.Id, null);
            AIChatDataStructure.MessagePage earlier = AIChatController.getEarlierMessages(conversation.Id, third.Id);
        Test.stopTest();

        for (AIChatDataStructure.ChatMessage message : everything.messages) {
            Assert.areNotEqual('AI response failed: hidden', message.displayText, 'System messages should never be shown.');
        }
        Assert.areEqual(3, everything.messages.size(), 'All visible messages should come back with no boundary.');
        Assert.isTrue(conversationUpdate.messages.size() <= 2, 'Only messages after the boundary should come back.');
        Assert.areEqual('Active', conversationUpdate.status, 'The status should be returned.');
        Assert.isTrue(earlier.messages.size() <= 2, 'A page should be at most MaxVisibleMessageHistory__c messages.');
    }

    @IsTest static void testScenario7() {

        AIAgent__c agent = createAgent(null, null);
        AIConversation__c conversation = createConversation(agent.Id, null);
        AIConversationMessage__c reply = createMessage(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 'An answer');

        Test.startTest();

            AIChatController.submitFeedback(reply.Id, AIAssistApplicationConstants.FEEDBACK_RATING_HELPFUL, null, null);
            AIChatController.submitFeedback(reply.Id, AIAssistApplicationConstants.FEEDBACK_RATING_NOT_HELPFUL, 'Not accurate', 'A newer quote exists.');

            try {
                AIChatController.submitFeedback(reply.Id, 'Meh', null, null);
                Assert.fail('An invalid rating should have thrown.');
            } catch (AuraHandledException ex) {
                Assert.isTrue(ex.getMessage().contains('Helpful'), 'The error should list the valid ratings.');
            }

        Test.stopTest();

        List<AIFeedback__c> feedback = [SELECT Rating__c, Comment__c, AIConversation__c FROM AIFeedback__c WHERE AIConversationMessage__c = :reply.Id];
        Assert.areEqual(1, feedback.size(), 'Rating again should replace the earlier rating.');
        Assert.areEqual(AIAssistApplicationConstants.FEEDBACK_RATING_NOT_HELPFUL, feedback[0].Rating__c, 'The latest rating should be kept.');
        Assert.areEqual('[Not accurate] A newer quote exists.', feedback[0].Comment__c, 'The reason should prefix the comment.');
        Assert.areEqual(conversation.Id, feedback[0].AIConversation__c, 'The feedback should link to the conversation.');
    }

    @IsTest static void testScenario8() {

        createAgent(null, null);
        Assert.areEqual(AIAssistApplicationConstants.CHAT_STATE_TERMS, AIChatController.getChatContext(null, null, null, null).state, 'Terms should be required first.');

        Test.startTest();
            AIChatController.acknowledgeTerms();
        Test.stopTest();

        AITermsAcknowledgment__c acknowledgment = [SELECT TermsVersion__c FROM AITermsAcknowledgment__c WHERE User__c = :UserInfo.getUserId() LIMIT 1];
        Assert.areEqual('2.0', acknowledgment.TermsVersion__c, 'The current terms version should be recorded.');
        Assert.areEqual(AIAssistApplicationConstants.CHAT_STATE_READY, AIChatController.getChatContext(null, null, null, null).state, 'Agreeing should clear the terms state.');
    }

    @IsTest static void testScenario9() {

        AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AIChatControllerTest.TestExecutor', false)[0];
        action.IsActive__c = true;
        action.ActionName__c = 'Create task';
        action.InputSchema__c = '{"type":"object","properties":{"subject":{"type":"string","description":"Task subject"},"dueDate":{"type":"string","format":"date"}},"required":["subject"]}';
        insert action;

        AIAgent__c agent = createAgent(null, null);
        AIConversation__c conversation = createConversation(agent.Id, null);
        AIConversationMessage__c reply = new AIConversationMessage__c(AIConversation__c = conversation.Id, Sender__c = AIAssistApplicationConstants.SENDER_AI_AGENT, MessageBody__c = 'Suggest a task', SuggestedWorkflowActionId__c = action.Id);
        insert reply;

        Test.startTest();
            AIChatDataStructure.ActionResult result = AIChatController.runSuggestedAction(reply.Id, '{"subject":"Send refreshed quote"}');
        Test.stopTest();

        Assert.isTrue(result.isSuccess, 'The action should run.');
        Assert.areEqual('Task created: Send refreshed quote', result.message, 'The executor\'s result should be returned.');

        AIExecutionStep__c step = [SELECT Status__c, AIWorkflowAction__c FROM AIExecutionStep__c WHERE AIConversationMessage__c = :reply.Id LIMIT 1];
        Assert.areEqual(action.Id, step.AIWorkflowAction__c, 'The run should be recorded against the action.');
        Assert.areEqual(AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS, step.Status__c, 'The step should be a success.');

        AIChatDataStructure.ConversationUpdate conversationUpdate = AIChatController.getConversationUpdate(conversation.Id, null);
        AIChatDataStructure.SuggestedAction suggested = conversationUpdate.messages[0].suggestedAction;
        Assert.isTrue(suggested.hasRun, 'The reply should show the action as already run.');
        Assert.areEqual(2, suggested.inputFields.size(), 'The input schema should become two fields.');

        AIAssistUISettings__c uiSettings = AIAssistUISettings__c.getOrgDefaults();
        uiSettings.AllowInlineWorkflowActions__c = false;
        update uiSettings;

        try {
            AIChatController.runSuggestedAction(reply.Id, null);
            Assert.fail('Running should be refused when inline actions are off.');
        } catch (AuraHandledException ex) {
            Assert.isTrue(ex.getMessage().contains('turned off'), 'The refusal should explain why.');
        }
    }

    @IsTest static void testScenario10() {

        AIAgent__c agent = createAgent(null, null);
        AIConversation__c conversation = createConversation(agent.Id, null);
        createMessage(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 'Question');
        AIConversationMessage__c reply = createMessage(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 'Answer');
        createMessage(conversation.Id, AIAssistApplicationConstants.SENDER_SYSTEM, 'AI response failed: provider timeout');
        insert AIAssistTestDataFactory.createAIPIIMapping(conversation.Id, new Map<String, String>{ 'PERSON_1' => 'Jordan', 'EMAIL_1' => 'j@example.com' }, false);

        try {
            AIChatController.getDebugTrace(reply.Id);
            Assert.fail('The trace should be refused without debug mode.');
        } catch (AuraHandledException ex) {
            Assert.isTrue(ex.getMessage().contains('Debug mode is off'), 'The refusal should mention debug mode.');
        }

        try {
            AIChatController.getPiiMappings(reply.Id);
            Assert.fail('The PII mappings should be refused without debug mode.');
        } catch (AuraHandledException ex) {
            Assert.isTrue(ex.getMessage().contains('Debug mode is off'), 'The refusal should mention debug mode.');
        }

        try {
            AIChatController.exportConversation(conversation.Id);
            Assert.fail('Export should be refused when it isn\'t enabled.');
        } catch (AuraHandledException ex) {
            Assert.isTrue(ex.getMessage().contains('Exporting'), 'The refusal should mention exporting.');
        }

        AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(UserInfo.getUserId(), false);
        userSettings.IsActive__c = true;
        userSettings.DebugModeEnabled__c = true;
        userSettings.ConversationExportEnabled__c = true;
        insert userSettings;

        Test.startTest();
            AIChatDataStructure.DebugTrace trace = AIChatController.getDebugTrace(reply.Id);
            Map<String, Object> piiMappings = (Map<String, Object>) JSON.deserializeUntyped(AIChatController.getPiiMappings(reply.Id));
            AIChatDataStructure.FailureDetail detail = AIChatController.getFailureDetail(conversation.Id);
            String transcript = AIChatController.exportConversation(conversation.Id);
        Test.stopTest();

        Assert.areEqual(conversation.Id, trace.conversationId, 'The trace should name the conversation.');
        Assert.isNotNull(trace.userMessageId, 'The prompting user message should be found.');
        Assert.areEqual(2, trace.piiFieldsMasked, 'Both mapped values should be counted.');
        Assert.areEqual(new Map<String, Object>{ 'PERSON_1' => 'Jordan', 'EMAIL_1' => 'j@example.com' }, piiMappings, 'Every mapped pair should be returned as JSON.');
        Assert.areEqual('AI response failed: provider timeout', detail.debugDetail, 'Debug users should see the failure detail.');
        Assert.isTrue(transcript.contains('Question') && transcript.contains('Answer'), 'The transcript should contain the conversation.');
        Assert.isFalse(transcript.contains('provider timeout'), 'System messages should be left out of the transcript.');
    }

    @IsTest static void testScenario11() {

        AIAgent__c agent = createAgent(null, null);
        AIConversation__c conversation = createConversation(agent.Id, null);
        createMessage(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 'Pricing history');

        Test.startTest();

            AIChatController.closeConversation(conversation.Id);
            AIChatDataStructure.ConversationView closed = AIChatController.openConversation(conversation.Id);
            Assert.isFalse(closed.isActive, 'The conversation should be closed.');
            Assert.isTrue(closed.canResume, 'An Agent allowing resume should let it be continued.');

            AIChatDataStructure.ConversationView resumed = AIChatController.resumeConversation(conversation.Id);
            Assert.isTrue(resumed.isActive, 'Resuming should reopen the conversation.');

            List<AIChatDataStructure.ConversationSummary> history = AIChatController.getConversationHistory(null, false);
            Assert.areEqual(1, history.size(), 'The user\'s conversation should be listed.');
            Assert.areEqual('Pricing history', history[0].title, 'It should be titled by its first message.');

            agent.AllowConversationResume__c = false;
            update agent;
            AIChatController.closeConversation(conversation.Id);
            try {
                AIChatController.resumeConversation(conversation.Id);
                Assert.fail('Resuming should be refused when the Agent doesn\'t allow it.');
            } catch (AuraHandledException ex) {
                Assert.isTrue(ex.getMessage().contains('can\'t be continued'), 'The refusal should explain why.');
            }

        Test.stopTest();

        User otherUser = AIAssistTestDataFactory.createStandardUsers(AIAssistApplicationConstants.USER_TYPE_STANDARD, 1, true)[0];
        System.runAs(otherUser) {
            try {
                AIChatController.openConversation(conversation.Id);
                Assert.fail('Another user\'s conversation should be refused.');
            } catch (AuraHandledException ex) {
                Assert.isNotNull(ex.getMessage(), 'A readable error should be returned.');
            }
        }
    }

    @IsTest static void testScenario12() {

        List<AIChatDataStructure.ActionInputField> fields = AIChatActionService.parseInputSchema('{"properties":{"amount":{"type":"number"},"notify":{"type":"boolean"},"notes":{"type":"string","maxLength":1000},"when":{"type":"string","format":"date-time","title":"When"}},"required":["amount"]}');
        Map<String, AIChatDataStructure.ActionInputField> byName = new Map<String, AIChatDataStructure.ActionInputField>();
        for (AIChatDataStructure.ActionInputField field : fields) byName.put(field.name, field);

        Assert.areEqual('number', byName.get('amount').inputType, 'Numbers should map to number inputs.');
        Assert.isTrue(byName.get('amount').required, 'Required properties should be marked.');
        Assert.areEqual('checkbox', byName.get('notify').inputType, 'Booleans should map to checkboxes.');
        Assert.areEqual('textarea', byName.get('notes').inputType, 'Long strings should map to text areas.');
        Assert.areEqual('When', byName.get('when').label, 'A title should be used as the label.');
        Assert.areEqual(0, AIChatActionService.parseInputSchema('not json').size(), 'A malformed schema should give no fields.');

        String adminsOnly = AIAssistApplicationConstants.CHAT_COMMAND_AVAILABLE_TO_ADMINS_ONLY;
        String superUsersAndAdmins = AIAssistApplicationConstants.CHAT_COMMAND_AVAILABLE_TO_SUPER_USERS_AND_ADMINS;
        Assert.isTrue(AIChatCommandService.isCommandAvailableToUserType(adminsOnly, AIAssistApplicationConstants.USER_TYPE_ADMIN), 'Admins Only should include Admins.');
        Assert.isFalse(AIChatCommandService.isCommandAvailableToUserType(adminsOnly, AIAssistApplicationConstants.USER_TYPE_SUPER_USER), 'Admins Only should exclude Super Users.');
        Assert.isTrue(AIChatCommandService.isCommandAvailableToUserType(superUsersAndAdmins, AIAssistApplicationConstants.USER_TYPE_SUPER_USER), 'Super Users and Admins should include Super Users.');
        Assert.isFalse(AIChatCommandService.isCommandAvailableToUserType(superUsersAndAdmins, AIAssistApplicationConstants.USER_TYPE_STANDARD), 'Super Users and Admins should exclude Standard Users.');
        Assert.isTrue(AIChatCommandService.isCommandAvailableToUserType(AIAssistApplicationConstants.CHAT_COMMAND_AVAILABLE_TO_ALL_USERS, null), 'All Users should include a user with no type.');

        String body = '/brief' + AIAssistApplicationConstants.CHAT_COMMAND_PROMPT_SEPARATOR + 'Hidden instructions';
        Assert.areEqual('/brief', AIChatCommandService.getDisplayText(body), 'Only the typed part should be displayed.');
        Assert.isTrue(AIChatCommandService.isCommandText('/risk-check focus'), 'A command with text should be recognised.');
        Assert.isFalse(AIChatCommandService.isCommandText('/etc/hosts'), 'A path isn\'t a command.');
        Assert.areEqual('Contact Roles', AIChatDataStructure.humanise('ContactRoles'), 'CamelCase should be split.');
        Assert.areEqual('Open cases', AIChatDataStructure.humanise('open_cases'), 'Underscores should become spaces.');
    }

    @IsTest static void testScenario13() {

        AIAgent__c agent = createAgent(null, null);
        AIConversation__c conversation = createConversation(agent.Id, null);
        insert AIAssistTestDataFactory.createAIPIIMapping(conversation.Id, new Map<String, String>{ 'Elena Whitfield' => 'Morgan Reyes', 'Marcus' => 'Morgan', 'elena@meridian.example' => 'avery.bennett@example.com' }, false);

        createMessage(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 'How do I reach the CIO?');
        AIConversationMessage__c reply = createMessage(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, '**Morgan Reyes** (CIO) - avery.bennett@example.com. Ask Morgan for an intro.');

        AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(UserInfo.getUserId(), false);
        userSettings.IsActive__c = true;
        userSettings.ConversationExportEnabled__c = true;
        insert userSettings;

        Test.startTest();
            AIChatDataStructure.ConversationUpdate conversationUpdate = AIChatController.getConversationUpdate(conversation.Id, null);
            String transcript = AIChatController.exportConversation(conversation.Id);
        Test.stopTest();

        String expected = '**Elena Whitfield** (CIO) - elena@meridian.example. Ask Marcus for an intro.';
        Assert.areEqual(expected, conversationUpdate.messages[1].displayText, 'Every fake value should be restored, the longest first.');
        Assert.isTrue(transcript.contains(expected), 'The export should show the real values too.');
        Assert.isTrue([SELECT MessageBody__c FROM AIConversationMessage__c WHERE Id = :reply.Id].MessageBody__c.contains('Morgan Reyes'), 'The saved reply should keep its fake values.');
        Assert.areEqual('No mapping here', AIChatDebugService.restorePii('No mapping here', new Map<String, String>()), 'Text with no mapping should be unchanged.');
    }

    // A real IAIWorkflowActionExecutor - AiWorkflowActionDispatcher resolves ApexClassName__c via Type.forName().
    public class TestExecutor implements IAIWorkflowActionExecutor {
        public Object execute(Id recordId, Map<String, Object> inputParameters) {
            return 'Task created: ' + inputParameters.get('subject');
        }
    }
}