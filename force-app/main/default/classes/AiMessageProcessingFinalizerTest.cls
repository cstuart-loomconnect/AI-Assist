/*
Class Name: AiMessageProcessingFinalizerTest

=================================================================
=================================================================

Description: Testing utility for the AiMessageProcessingFinalizer class.

=================================================================
=================================================================
Applicable Classes:

AiMessageProcessingFinalizer: Coverage 90%+ (the uncatchable-failure branch needs a real FinalizerContext, which tests can't construct)

Version      Date               Author                   Description
1.0          2026-09-27         Chandler Stuart          Initial development
1.1          2026-09-27         Chandler Stuart          Retry scenario updated - retries are enqueued immediately, with no delay.
*/

@IsTest private class AiMessageProcessingFinalizerTest {

    // testScenario1: With no retry requested and no newer message waiting, the finalizer releases the conversation's lock and enqueues nothing.
    // testScenario2: With a newer user message waiting, the finalizer keeps the lock and enqueues one job for that message.
    // testScenario3: With a retry requested, the finalizer enqueues one retry job immediately and resets the lock.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        settings.ProcessingLockMinutes__c = 10;
        upsert settings;

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, false)[0];
        agent.IsActive__c = true;
        insert agent;

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, 1, true)[0];
        update new AIConversation__c(Id = conversation.Id, ProcessingLockedUntil__c = System.now().addMinutes(10));
    }

    @IsTest static void testScenario1() {

        AIConversation__c conversation = [ SELECT Id FROM AIConversation__c LIMIT 1 ];
        AIConversationMessage__c processedMessage = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, 3, 1, true)[0];

        Test.startTest();
            new AiMessageProcessingFinalizer(processedMessage.Id, conversation.Id, 1).execute(null);
            Integer jobsEnqueued = Limits.getQueueableJobs();
        Test.stopTest();

        Assert.areEqual(0, jobsEnqueued, 'Nothing is waiting, so no job should be enqueued.');
        Assert.isNull([ SELECT ProcessingLockedUntil__c FROM AIConversation__c WHERE Id = :conversation.Id ].ProcessingLockedUntil__c, 'The lock should be released.');
    }

    @IsTest static void testScenario2() {

        AIConversation__c conversation = [ SELECT Id FROM AIConversation__c LIMIT 1 ];
        List<AIConversationMessage__c> messages = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, 3, 2, true);

        Test.startTest();
            new AiMessageProcessingFinalizer(messages[0].Id, conversation.Id, 1).execute(null);
            Integer jobsEnqueued = Limits.getQueueableJobs();
            Datetime lockedUntil = [ SELECT ProcessingLockedUntil__c FROM AIConversation__c WHERE Id = :conversation.Id ].ProcessingLockedUntil__c;
        Test.stopTest();

        Assert.areEqual(1, jobsEnqueued, 'One job should be enqueued for the waiting message.');
        Assert.isNotNull(lockedUntil, 'The lock should be kept for the waiting message.');
    }

    @IsTest static void testScenario3() {

        AIConversation__c conversation = [ SELECT Id FROM AIConversation__c LIMIT 1 ];
        AIConversationMessage__c processedMessage = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, 3, 1, true)[0];

        AiMessageProcessingFinalizer finalizer = new AiMessageProcessingFinalizer(processedMessage.Id, conversation.Id, 2);
        finalizer.requestRetry(150);

        Test.startTest();
            finalizer.execute(null);
            Integer jobsEnqueued = Limits.getQueueableJobs();
            Datetime lockedUntil = [ SELECT ProcessingLockedUntil__c FROM AIConversation__c WHERE Id = :conversation.Id ].ProcessingLockedUntil__c;
        Test.stopTest();

        Assert.areEqual(1, jobsEnqueued, 'One retry job should be enqueued.');
        Assert.isTrue(lockedUntil > System.now().addMinutes(9), 'The lock should be reset to the 10 minute lock time for the retry.');
        Assert.isTrue(finalizer.shouldRetry, 'The retry request should be recorded.');
        Assert.areEqual(150, finalizer.totalTokensUsed, 'The tokens spent so far should be carried to the retry.');
    }
}