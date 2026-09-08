/*
Class Name: AIConversationIdleTimeoutBatchTest

=================================================================
=================================================================

Description: Testing utility for the AI Conversation Idle Timeout job.

=================================================================
=================================================================
Applicable Classes:

AIConversationIdleTimeoutBatch: 92%

Version      Date           Author                   Description
1.0          2026-09-08     Chandler Stuart          Initial development
*/

@IsTest private class AIConversationIdleTimeoutBatchTest {

    // testScenario1: Running the batch closes only Active conversations whose idle time (measured from their last message, or their own CreatedDate when they have no messages) has met or exceeded the Agent's IdleTimeoutMinutes__c, stamping ConversationCloseReason__c = 'Idle Timeout', and leaves recently-active conversations Active.
    // testScenario2: When the Agent's IdleTimeoutMinutes__c is blank, no idle timeout is enforced and even long-idle conversations stay Active.
    // testScenario3: Invoking the job through its Schedulable entry point runs the batch and closes an idle conversation.
    // testScenario4: A conversation that is already Closed is not re-processed, and a null / blank IdleTimeoutMinutes__c short-circuits before any update.

    private static final Integer IDLE_TIMEOUT_MINUTES = 30;

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = true;
        settings.DisableExceptionLogging__c = false;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, IDLE_TIMEOUT_MINUTES, true)[0];

        // Idle: created well past the timeout, no messages -> measured from CreatedDate.
        AIConversation__c idleNoMessages = AIAssistTestDataFactory.createAIConversations(agent.Id, 1, true)[0];
        Test.setCreatedDate(idleNoMessages.Id, Datetime.now().addMinutes(-24 * 60));

        // Idle: recent conversation, but its only message is well past the timeout -> measured from the message.
        AIConversation__c idleOldMessage = AIAssistTestDataFactory.createAIConversations(agent.Id, 1, true)[0];
        AIConversationMessage__c oldMessage = AIAssistTestDataFactory.createAIConversationMessages(idleOldMessage.Id, 5, 1, true)[0];
        Test.setCreatedDate(oldMessage.Id, Datetime.now().addMinutes(-24 * 60));

        // Active: created long ago, but a message landed just now -> within the idle window.
        AIConversation__c recentMessage = AIAssistTestDataFactory.createAIConversations(agent.Id, 1, true)[0];
        Test.setCreatedDate(recentMessage.Id, Datetime.now().addMinutes(-24 * 60));
        AIAssistTestDataFactory.createAIConversationMessages(recentMessage.Id, 5, 1, true);

        // Active: just created, no messages -> within the idle window.
        AIConversation__c recentlyCreated = AIAssistTestDataFactory.createAIConversations(agent.Id, 1, true)[0];

        Test.startTest();
            Database.executeBatch(new AIConversationIdleTimeoutBatch());
        Test.stopTest();

        Map<Id, AIConversation__c> conversationsById = new Map<Id, AIConversation__c>([
            SELECT Id, Status__c, ConversationCloseReason__c FROM AIConversation__c
        ]);

        Assert.areEqual(AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED, conversationsById.get(idleNoMessages.Id).Status__c, 'An idle conversation with no messages should be closed based on its CreatedDate.');
        Assert.areEqual(AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_IDLE_TIMEOUT, conversationsById.get(idleNoMessages.Id).ConversationCloseReason__c, 'A conversation closed by the batch should record the Idle Timeout close reason.');

        Assert.areEqual(AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED, conversationsById.get(idleOldMessage.Id).Status__c, 'A conversation whose last message is past the idle window should be closed.');
        Assert.areEqual(AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_IDLE_TIMEOUT, conversationsById.get(idleOldMessage.Id).ConversationCloseReason__c, 'A conversation closed by the batch should record the Idle Timeout close reason.');

        Assert.areEqual(AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE, conversationsById.get(recentMessage.Id).Status__c, 'A conversation with a recent message should stay Active.');
        Assert.areEqual(AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE, conversationsById.get(recentlyCreated.Id).Status__c, 'A recently-created conversation with no messages should stay Active.');
    }

    @IsTest static void testScenario2() {

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, true)[0];

        AIConversation__c idleNoMessages = AIAssistTestDataFactory.createAIConversations(agent.Id, 1, true)[0];
        Test.setCreatedDate(idleNoMessages.Id, Datetime.now().addMinutes(-24 * 60));

        Test.startTest();
            Database.executeBatch(new AIConversationIdleTimeoutBatch());
        Test.stopTest();

        AIConversation__c reloaded = [SELECT Status__c, ConversationCloseReason__c FROM AIConversation__c WHERE Id = :idleNoMessages.Id];
        Assert.areEqual(AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE, reloaded.Status__c, 'A blank IdleTimeoutMinutes__c means no idle timeout is enforced.');
        Assert.areEqual(null, reloaded.ConversationCloseReason__c, 'A conversation left open should have no close reason.');
    }

    @IsTest static void testScenario3() {

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, IDLE_TIMEOUT_MINUTES, true)[0];

        AIConversation__c idleNoMessages = AIAssistTestDataFactory.createAIConversations(agent.Id, 1, true)[0];
        Test.setCreatedDate(idleNoMessages.Id, Datetime.now().addMinutes(-24 * 60));

        Test.startTest();
            new AIConversationIdleTimeoutBatch().execute((SchedulableContext) null);
        Test.stopTest();

        AIConversation__c reloaded = [SELECT Status__c FROM AIConversation__c WHERE Id = :idleNoMessages.Id];
        Assert.areEqual(AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED, reloaded.Status__c, 'Running the job through its Schedulable entry point should close an idle conversation.');
    }

    @IsTest static void testScenario4() {

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, IDLE_TIMEOUT_MINUTES, true)[0];

        // Already Closed and long idle: excluded by the start() query, so it stays as-is.
        AIConversation__c alreadyClosed = AIAssistTestDataFactory.createAIConversations(agent.Id, 1, true)[0];
        Test.setCreatedDate(alreadyClosed.Id, Datetime.now().addMinutes(-24 * 60));
        alreadyClosed.Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED;
        update alreadyClosed;

        // Idle but tied to an Agent with no idle timeout: processed by the batch, but skipped before any update.
        AIAgent__c agentNoTimeout = AIAssistTestDataFactory.createAIAgents(1, true)[0];
        AIConversation__c idleNoTimeout = AIAssistTestDataFactory.createAIConversations(agentNoTimeout.Id, 1, true)[0];
        Test.setCreatedDate(idleNoTimeout.Id, Datetime.now().addMinutes(-24 * 60));

        Test.startTest();
            Database.executeBatch(new AIConversationIdleTimeoutBatch());
        Test.stopTest();

        AIConversation__c reloadedClosed = [SELECT Status__c, ConversationCloseReason__c FROM AIConversation__c WHERE Id = :alreadyClosed.Id];
        Assert.areEqual(AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED, reloadedClosed.Status__c, 'An already-Closed conversation is untouched by the batch.');
        Assert.areEqual(null, reloadedClosed.ConversationCloseReason__c, 'The batch should not stamp an Idle Timeout reason on a conversation it did not close.');

        AIConversation__c reloadedNoTimeout = [SELECT Status__c FROM AIConversation__c WHERE Id = :idleNoTimeout.Id];
        Assert.areEqual(AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE, reloadedNoTimeout.Status__c, 'A conversation whose Agent has no idle timeout stays Active.');

        Integer platformLogCount = [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'AIConversationIdleTimeoutBatch'];
        Assert.areEqual(0, platformLogCount, 'A clean run should log no exceptions.');
    }
}