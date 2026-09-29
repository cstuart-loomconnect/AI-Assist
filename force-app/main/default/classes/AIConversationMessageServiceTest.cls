/*
Class Name: AIConversationMessageServiceTest

=================================================================
=================================================================

Description: Testing utility for AIConversationMessageService.

=================================================================
=================================================================
Applicable Classes:

AIConversationMessageService: Coverage 100%

Version      Date               Author                   Description
1.0          2026-09-22         Chandler Stuart          Initial development
1.1          2026-09-27         Chandler Stuart          Added testScenario7 (processing lock) and testScenario8 (failed turns record their tokens).
1.2          2026-09-27         Chandler Stuart          Added testScenario9 (continuing a conversation by Id), testScenario10 (retryLatestMessage) and testScenario11 (new conversations paused).
*/

@IsTest private class AIConversationMessageServiceTest {

    // testScenario1: A happy-path sendMessage call with no existing conversation, no channel restriction, and no usage limits creates a new Active conversation and inserts the user's message with an estimated TokenCount__c.
    // testScenario2: Input validation and business-rule failures - a null Agent Id, a blank message body, an inactive Agent, and a disallowed channel - each throw AIConversationMessageServiceException rather than sending.
    // testScenario3: When SingleActiveConversationPer_Record__c is on, sendMessage reuses the existing Active conversation for the same Agent/related record/owner instead of creating a new one.
    // testScenario4: When the reusable conversation has already hit the Agent's MaxMessagesPerConversation__c or MaxTokensPerConversation__c cap, sendMessage closes it out with the matching reason and starts a fresh conversation instead of continuing it.
    // testScenario5: UsageLimitReachedBehavior__c is honored - Block New Conversations Only blocks a brand-new conversation once MaxConcurrentConversations__c or MaxConversationsPer24Hours__c is reached, Block New Messages blocks everything once MaxTokensPer24Hours__c is reached, and Notify Only never blocks even over those same limits.
    // testScenario6: closeConversation sets Status__c to Closed with the given reason, defaults to User Closed when no reason is supplied, and throws when no Conversation Id is given.
    // testScenario7: A message sent while the conversation is already processing another is saved but not enqueued - it waits for the running job's finalizer.
    // testScenario8: handleAgentResult with a failed result records the tokens spent as a System message; a failed result with no tokens records nothing.
    // testScenario9: sendMessage with a conversation Id continues that conversation while it's Active, owned by the user and on the same Agent; a closed one, or one over the Agent's message cap (closed with Message Limit Reached), starts a new conversation instead.
    // testScenario10: retryLatestMessage re-runs the newest user message once the lock is free, and refuses while it's still locked, for a closed conversation and for one with no user message.
    // testScenario11: While AIAssistUISettings__c.IsUserInitiatedChatEnabled__c is off, a message that would start a new conversation is refused, but an open conversation can still be continued.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, false)[0];
        agent.IsActive__c = true;
        insert agent;

        Test.startTest();
            AIConversationMessage__c result = AIConversationMessageService.sendMessage(agent.Id, 'Hello there', AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, 'Account', null);
        Test.stopTest();

        Assert.isNotNull(result.Id, 'The user message should have been inserted.');
        Assert.areEqual(AIAssistApplicationConstants.SENDER_USER, result.Sender__c, 'Sender should be User.');
        Assert.areEqual(Math.ceil('Hello there'.length() / 4.0), result.TokenCount__c, 'TokenCount__c should reflect the ~4 chars-per-token estimate.');

        AIConversation__c conversation = [SELECT Id, Status__c, Channel__c, AIAgent__c FROM AIConversation__c WHERE AIAgent__c = :agent.Id LIMIT 1];
        Assert.areEqual(AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE, conversation.Status__c, 'A new conversation should be Active.');
        Assert.areEqual(result.AIConversation__c, conversation.Id, 'The message should belong to the newly created conversation.');
    }

    @IsTest static void testScenario2() {

        AIAgent__c activeAgent = AIAssistTestDataFactory.createAIAgents(1, false)[0];
        activeAgent.IsActive__c = true;
        insert activeAgent;

        AIAgent__c inactiveAgent = AIAssistTestDataFactory.createAIAgents(1, false)[0];
        inactiveAgent.IsActive__c = false;
        insert inactiveAgent;

        AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(UserInfo.getUserId(), false);
        userSettings.IsActive__c = true;
        userSettings.AllowedChannels__c = AIAssistApplicationConstants.CHANNEL_MOBILE;
        insert userSettings;

        Test.startTest();

            try {
                AIConversationMessageService.sendMessage(null, 'Hello', AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, null, null);
                Assert.fail('A null Agent Id should have thrown.');
            } catch (AIConversationMessageService.AIConversationMessageServiceException ex) {
                Assert.isTrue(ex.getMessage().contains('Agent Id is required'), 'Error should explain the Agent Id is missing.');
            }

            try {
                AIConversationMessageService.sendMessage(activeAgent.Id, '', AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, null, null);
                Assert.fail('A blank message body should have thrown.');
            } catch (AIConversationMessageService.AIConversationMessageServiceException ex) {
                Assert.isTrue(ex.getMessage().contains('message body is required'), 'Error should explain the message body is missing.');
            }

            try {
                AIConversationMessageService.sendMessage(inactiveAgent.Id, 'Hello', AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, null, null);
                Assert.fail('An inactive Agent should have thrown.');
            } catch (AIConversationMessageService.AIConversationMessageServiceException ex) {
                Assert.isTrue(ex.getMessage().contains('is not active'), 'Error should explain the Agent is inactive.');
            }

            try {
                AIConversationMessageService.sendMessage(activeAgent.Id, 'Hello', AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, null, null);
                Assert.fail('A channel not on the allow-list should have thrown.');
            } catch (AIConversationMessageService.AIConversationMessageServiceException ex) {
                Assert.isTrue(ex.getMessage().contains('is not enabled'), 'Error should explain the channel is not enabled.');
            }

        Test.stopTest();
    }

    @IsTest static void testScenario3() {

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, false)[0];
        agent.IsActive__c = true;
        agent.SingleActiveConversationPer_Record__c = true;
        insert agent;

        Id relatedRecordId = AIAssistTestDataFactory.createAccounts(1, true)[0].Id;

        AIConversation__c existingConversation = new AIConversation__c(
            AIAgent__c = agent.Id,
            Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE,
            Channel__c = AIAssistApplicationConstants.CHANNEL_UTILITY_BAR,
            RelatedObjectAPIName__c = 'Account',
            RelatedRecordId__c = String.valueOf(relatedRecordId)
        );
        insert existingConversation;

        Test.startTest();
            AIConversationMessage__c result = AIConversationMessageService.sendMessage(agent.Id, 'Follow-up message', AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, 'Account', relatedRecordId);
        Test.stopTest();

        Assert.areEqual(existingConversation.Id, result.AIConversation__c, 'The message should be appended to the existing Active conversation for this record.');
        Assert.areEqual(1, [SELECT COUNT() FROM AIConversation__c WHERE AIAgent__c = :agent.Id], 'No new conversation should have been created.');
    }

    @IsTest static void testScenario4() {

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, false)[0];
        agent.IsActive__c = true;
        agent.SingleActiveConversationPer_Record__c = true;
        agent.MaxMessagesPerConversation__c = 2;
        insert agent;

        Id relatedRecordId = AIAssistTestDataFactory.createAccounts(1, true)[0].Id;

        AIConversation__c existingConversation = new AIConversation__c(
            AIAgent__c = agent.Id,
            Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE,
            Channel__c = AIAssistApplicationConstants.CHANNEL_UTILITY_BAR,
            RelatedObjectAPIName__c = 'Account',
            RelatedRecordId__c = String.valueOf(relatedRecordId)
        );
        insert existingConversation;

        AIAssistTestDataFactory.createAIConversationMessages(existingConversation.Id, 10, 2, true); // Hits the MaxMessagesPerConversation__c cap of 2.

        Test.startTest();
            AIConversationMessage__c result = AIConversationMessageService.sendMessage(agent.Id, 'One more message', AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, 'Account', relatedRecordId);
        Test.stopTest();

        AIConversation__c closedConversation = [SELECT Status__c, ConversationCloseReason__c FROM AIConversation__c WHERE Id = :existingConversation.Id];
        Assert.areEqual(AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED, closedConversation.Status__c, 'The over-the-cap conversation should have been closed.');
        Assert.areEqual(AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_MESSAGE_LIMIT_REACHED, closedConversation.ConversationCloseReason__c, 'Close reason should reflect the message limit.');
        Assert.areNotEqual(existingConversation.Id, result.AIConversation__c, 'A new conversation should have been started instead of continuing the closed one.');

        // Same behavior for the token cap, on a second related record so it exercises its own reusable conversation.
        agent.MaxMessagesPerConversation__c = null;
        agent.MaxTokensPerConversation__c = 5;
        update agent;

        Id secondRelatedRecordId = AIAssistTestDataFactory.createAccounts(1, true)[0].Id;

        AIConversation__c existingTokenConversation = new AIConversation__c(
            AIAgent__c = agent.Id,
            Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE,
            Channel__c = AIAssistApplicationConstants.CHANNEL_UTILITY_BAR,
            RelatedObjectAPIName__c = 'Account',
            RelatedRecordId__c = String.valueOf(secondRelatedRecordId),
            ConversationTokenUsage__c = 10 // Set directly rather than via a child message insert - the AIConversationMessageTriggerHandler's recursion guard is a static that stays tripped for the rest of this test method, so a second insert here wouldn't roll up anyway. Hits the MaxTokensPerConversation__c cap of 5.
        );
        insert existingTokenConversation;

        AIConversationMessage__c tokenCapResult = AIConversationMessageService.sendMessage(agent.Id, 'One more message', AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, 'Account', secondRelatedRecordId);

        AIConversation__c closedTokenConversation = [SELECT Status__c, ConversationCloseReason__c FROM AIConversation__c WHERE Id = :existingTokenConversation.Id];
        Assert.areEqual(AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED, closedTokenConversation.Status__c, 'The over-the-cap conversation should have been closed.');
        Assert.areEqual(AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_TOKEN_LIMIT_REACHED, closedTokenConversation.ConversationCloseReason__c, 'Close reason should reflect the token limit.');
        Assert.areNotEqual(existingTokenConversation.Id, tokenCapResult.AIConversation__c, 'A new conversation should have been started instead of continuing the closed one.');
    }

    @IsTest static void testScenario5() {

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, false)[0];
        agent.IsActive__c = true;
        insert agent;

        AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(UserInfo.getUserId(), false);
        userSettings.IsActive__c = true;
        userSettings.UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY;
        userSettings.MaxConcurrentConversations__c = 1;
        userSettings.MaxConversationsPer24Hours__c = 1;
        userSettings.MaxTokensPer24Hours__c = 1;
        insert userSettings;

        // Puts the user at their concurrent/24-hour conversation limits, and over their 24-hour token limit, before any of the calls below.
        AIConversation__c existingConversation = AIAssistTestDataFactory.createAIConversations(agent.Id, 1, true)[0];
        AIAssistTestDataFactory.createAIConversationMessages(existingConversation.Id, 10, 1, true);

        Test.startTest();

            try {
                AIConversationMessageService.sendMessage(agent.Id, 'Trying to start another conversation', AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, null, null);
                Assert.fail('Block New Conversations Only should block a brand-new conversation once the concurrent limit is reached.');
            } catch (AIConversationMessageService.AIConversationMessageServiceException ex) {
                Assert.isTrue(ex.getMessage().contains('concurrent conversations'), 'Error should explain the concurrent conversation limit.');
            }

            userSettings.MaxConcurrentConversations__c = null; // Isolates the 24-hour new-conversation cap from the concurrent-conversation cap above.
            update userSettings;

            try {
                AIConversationMessageService.sendMessage(agent.Id, 'Trying to start another conversation', AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, null, null);
                Assert.fail('Block New Conversations Only should block a brand-new conversation once the 24-hour conversation cap is reached.');
            } catch (AIConversationMessageService.AIConversationMessageServiceException ex) {
                Assert.isTrue(ex.getMessage().contains('new conversations per 24 hours'), 'Error should explain the 24-hour new-conversation limit.');
            }

            userSettings.UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES;
            userSettings.MaxConversationsPer24Hours__c = null; // Isolates the 24-hour token cap, which blocks everything - even continuing the existing conversation.
            update userSettings;

            try {
                AIConversationMessageService.sendMessage(agent.Id, 'Appending to the existing conversation', AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, null, null);
                Assert.fail('Block New Messages should block everything once the 24-hour token cap is reached.');
            } catch (AIConversationMessageService.AIConversationMessageServiceException ex) {
                Assert.isTrue(ex.getMessage().contains('tokens per 24 hours'), 'Error should explain the 24-hour token limit.');
            }

            userSettings.UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY;
            update userSettings;

            AIConversationMessage__c result = AIConversationMessageService.sendMessage(agent.Id, 'Notify only should never block', AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, null, null);
            Assert.isNotNull(result.Id, 'Notify Only should never block sending, even over the same limits.');

        Test.stopTest();
    }

    @IsTest static void testScenario6() {

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, false)[0];
        agent.IsActive__c = true;
        insert agent;

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, 1, true)[0];

        Test.startTest();

            AIConversationMessageService.closeConversation(conversation.Id, AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_SYSTEM_OVERRIDE);

            AIConversation__c conversationWithNoReason = AIAssistTestDataFactory.createAIConversations(agent.Id, 1, true)[0];
            AIConversationMessageService.closeConversation(conversationWithNoReason.Id, null);

            try {
                AIConversationMessageService.closeConversation(null, null);
                Assert.fail('A null Conversation Id should have thrown.');
            } catch (AIConversationMessageService.AIConversationMessageServiceException ex) {
                Assert.isTrue(ex.getMessage().contains('Conversation Id is required'), 'Error should explain the Conversation Id is missing.');
            }

        Test.stopTest();

        Map<Id, AIConversation__c> conversationsById = new Map<Id, AIConversation__c>([SELECT Status__c, ConversationCloseReason__c FROM AIConversation__c WHERE Id IN (:conversation.Id, :conversationWithNoReason.Id)]);

        Assert.areEqual(AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED, conversationsById.get(conversation.Id).Status__c, 'Conversation should be Closed.');
        Assert.areEqual(AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_SYSTEM_OVERRIDE, conversationsById.get(conversation.Id).ConversationCloseReason__c, 'Should use the given close reason.');

        Assert.areEqual(AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED, conversationsById.get(conversationWithNoReason.Id).Status__c, 'Conversation should be Closed.');
        Assert.areEqual(AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_USER_CLOSED, conversationsById.get(conversationWithNoReason.Id).ConversationCloseReason__c, 'Should default to User Closed when no reason is supplied.');
    }

    @IsTest static void testScenario7() {

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, false)[0];
        agent.IsActive__c = true;
        agent.SingleActiveConversationPer_Record__c = true;
        insert agent;

        Id relatedRecordId = AIAssistTestDataFactory.createAccounts(1, true)[0].Id;

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, 1, false)[0];
        conversation.Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE;
        conversation.RelatedRecordId__c = String.valueOf(relatedRecordId);
        conversation.ProcessingLockedUntil__c = System.now().addMinutes(10); // Another message is already being processed.
        insert conversation;

        Test.startTest();
            AIConversationMessage__c result = AIConversationMessageService.sendMessage(agent.Id, 'Sent while busy', AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, 'Account', relatedRecordId);
            Integer jobsEnqueued = Limits.getQueueableJobs();
        Test.stopTest();

        Assert.isNotNull(result.Id, 'The message should still be saved.');
        Assert.areEqual(conversation.Id, result.AIConversation__c, 'The message should join the busy conversation.');
        Assert.areEqual(0, jobsEnqueued, 'No job should be enqueued while the conversation is locked.');
    }

    @IsTest static void testScenario8() {

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, false)[0];
        agent.IsActive__c = true;
        insert agent;

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, 1, true)[0];

        AIAgentManager.AgentResult failedResultWithTokens = new AIAgentManager.AgentResult();
        failedResultWithTokens.errorMessage = 'Provider error.';
        failedResultWithTokens.totalTokensUsed = 250;

        AIAgentManager.AgentResult failedResultWithoutTokens = new AIAgentManager.AgentResult();
        failedResultWithoutTokens.errorMessage = 'Configuration error.';

        Test.startTest();
            AIConversationMessageService.handleAgentResult(conversation.Id, failedResultWithTokens);
            AIConversationMessageService.handleAgentResult(conversation.Id, failedResultWithoutTokens);
        Test.stopTest();

        List<AIConversationMessage__c> systemMessages = [ SELECT MessageBody__c, TokenCount__c FROM AIConversationMessage__c WHERE AIConversation__c = :conversation.Id AND Sender__c = :AIAssistApplicationConstants.SENDER_SYSTEM ];

        Assert.areEqual(1, systemMessages.size(), 'Only the failed turn that spent tokens should be recorded.');
        Assert.areEqual(250, systemMessages[0].TokenCount__c, 'The tokens spent should be recorded.');
        Assert.isTrue(systemMessages[0].MessageBody__c.contains('Provider error.'), 'The failure reason should be recorded.');
    }

    @IsTest static void testScenario9() {

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, false)[0];
        agent.IsActive__c = true;
        agent.MaxMessagesPerConversation__c = 3;
        insert agent;

        AIConversationMessage__c first = AIConversationMessageService.sendMessage(null, agent.Id, 'First', AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, null, null);
        AIConversationMessage__c second = AIConversationMessageService.sendMessage(first.AIConversation__c, agent.Id, 'Second', AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, null, null);
        Assert.areEqual(first.AIConversation__c, second.AIConversation__c, 'Passing the open conversation should continue it.');

        AIConversationMessageService.sendMessage(first.AIConversation__c, agent.Id, 'Third', AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, null, null);

        Test.startTest();
            AIConversationMessage__c fourth = AIConversationMessageService.sendMessage(first.AIConversation__c, agent.Id, 'Fourth', AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, null, null);
        Test.stopTest();

        Assert.areNotEqual(first.AIConversation__c, fourth.AIConversation__c, 'A conversation at its message cap should start a new one.');

        AIConversation__c capped = [SELECT Status__c, ConversationCloseReason__c FROM AIConversation__c WHERE Id = :first.AIConversation__c];
        Assert.areEqual(AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED, capped.Status__c, 'The capped conversation should be closed.');
        Assert.areEqual(AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_MESSAGE_LIMIT_REACHED, capped.ConversationCloseReason__c, 'It should be closed for its message limit.');

        AIConversationMessage__c afterClosed = AIConversationMessageService.sendMessage(first.AIConversation__c, agent.Id, 'Fifth', AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, null, null);
        Assert.areNotEqual(first.AIConversation__c, afterClosed.AIConversation__c, 'A closed conversation should never be continued.');
    }

    @IsTest static void testScenario10() {

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, false)[0];
        agent.IsActive__c = true;
        insert agent;

        AIConversationMessage__c sent = AIConversationMessageService.sendMessage(agent.Id, 'Hello', AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, null, null);
        Id conversationId = sent.AIConversation__c;

        try {
            AIConversationMessageService.retryLatestMessage(conversationId);
            Assert.fail('Retrying while the message is still processing should have thrown.');
        } catch (AIConversationMessageService.AIConversationMessageServiceException ex) {
            Assert.isTrue(ex.getMessage().contains('Still working'), 'Error should explain the message is still processing.');
        }

        update new AIConversation__c(Id = conversationId, ProcessingLockedUntil__c = null);

        Test.startTest();
            Id retriedMessageId = AIConversationMessageService.retryLatestMessage(conversationId);
        Test.stopTest();

        Assert.areEqual(sent.Id, retriedMessageId, 'The newest user message should be re-run.');

        AIConversation__c emptyConversation = AIAssistTestDataFactory.createAIConversations(agent.Id, 1, true)[0];
        try {
            AIConversationMessageService.retryLatestMessage(emptyConversation.Id);
            Assert.fail('A conversation with no user message should have thrown.');
        } catch (AIConversationMessageService.AIConversationMessageServiceException ex) {
            Assert.isTrue(ex.getMessage().contains('no message'), 'Error should explain there is nothing to retry.');
        }

        AIConversationMessageService.closeConversation(conversationId, null);
        try {
            AIConversationMessageService.retryLatestMessage(conversationId);
            Assert.fail('A closed conversation should have thrown.');
        } catch (AIConversationMessageService.AIConversationMessageServiceException ex) {
            Assert.isTrue(ex.getMessage().contains('has ended'), 'Error should explain the conversation has ended.');
        }
    }

    @IsTest static void testScenario11() {

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, false)[0];
        agent.IsActive__c = true;
        insert agent;

        AIConversationMessage__c opened = AIConversationMessageService.sendMessage(agent.Id, 'Before the pause', AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, null, null);

        AIAssistUISettings__c uiSettings = AIAssistUISettings__c.getOrgDefaults();
        uiSettings.IsUserInitiatedChatEnabled__c = false;
        upsert uiSettings;

        Test.startTest();

            AIConversationMessage__c continued = AIConversationMessageService.sendMessage(opened.AIConversation__c, agent.Id, 'Still allowed', AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, null, null);
            Assert.areEqual(opened.AIConversation__c, continued.AIConversation__c, 'An open conversation should still continue.');

            try {
                AIConversationMessageService.sendMessage(agent.Id, 'A new chat', AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, null, null);
                Assert.fail('Starting a new conversation should have been refused.');
            } catch (AIConversationMessageService.AIConversationMessageServiceException ex) {
                Assert.areEqual(AIAssistApplicationConstants.NEW_CONVERSATIONS_PAUSED_MESSAGE, ex.getMessage(), 'Error should say new conversations are paused.');
            }

        Test.stopTest();
    }
}