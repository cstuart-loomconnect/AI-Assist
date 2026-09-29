/*
Class Name: AIConversationLockServiceTest

=================================================================
=================================================================

Description: Testing utility for the AIConversationLockService class.

=================================================================
=================================================================
Applicable Classes:

AIConversationLockService: Coverage 100%

Version      Date               Author                   Description
1.0          2026-09-27         Chandler Stuart          Initial development
1.1          2026-09-27         Chandler Stuart          extendLock no longer takes a retry delay.
*/

@IsTest private class AIConversationLockServiceTest {

    // testScenario1: lockConversation locks a free conversation and returns true; a second lockConversation while it's locked returns false.
    // testScenario2: An expired lock (ProcessingLockedUntil__c in the past) counts as free, so lockConversation takes it over - a lock can never be held forever.
    // testScenario3: releaseLockOrGetNextMessage releases the lock when the processed message is the user's newest, and keeps it (returning the waiting message's Id) when a newer user message arrived.
    // testScenario4: extendLock resets the lock to the usual lock time from now.
    // testScenario5: lockConversation throws for an Id that isn't a conversation; releaseLockOrGetNextMessage and extendLock do nothing for one.

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

        AIAssistTestDataFactory.createAIConversations(agent.Id, 1, true);
    }

    @IsTest static void testScenario1() {

        AIConversation__c conversation = [ SELECT Id FROM AIConversation__c LIMIT 1 ];

        Test.startTest();
            Boolean firstLockResult = AIConversationLockService.lockConversation(conversation.Id);
            Boolean secondLockResult = AIConversationLockService.lockConversation(conversation.Id);
        Test.stopTest();

        Assert.isTrue(firstLockResult, 'A free conversation should be locked.');
        Assert.isFalse(secondLockResult, 'An already-locked conversation should not be locked again.');
        Assert.isTrue([ SELECT ProcessingLockedUntil__c FROM AIConversation__c WHERE Id = :conversation.Id ].ProcessingLockedUntil__c > System.now(), 'The lock should expire in the future.');
    }

    @IsTest static void testScenario2() {

        AIConversation__c conversation = [ SELECT Id FROM AIConversation__c LIMIT 1 ];
        update new AIConversation__c(Id = conversation.Id, ProcessingLockedUntil__c = System.now().addMinutes(-1));

        Test.startTest();
            Boolean lockResult = AIConversationLockService.lockConversation(conversation.Id);
        Test.stopTest();

        Assert.isTrue(lockResult, 'An expired lock should be taken over.');
    }

    @IsTest static void testScenario3() {

        AIConversation__c conversation = [ SELECT Id FROM AIConversation__c LIMIT 1 ];
        List<AIConversationMessage__c> messages = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, 3, 2, true);
        AIConversationMessage__c olderMessage = messages[0];
        AIConversationMessage__c newerMessage = messages[1];

        AIConversationLockService.lockConversation(conversation.Id);

        Test.startTest();
            Id nextMessageId = AIConversationLockService.releaseLockOrGetNextMessage(conversation.Id, olderMessage.Id);
            Datetime lockedUntilWithWaitingMessage = [ SELECT ProcessingLockedUntil__c FROM AIConversation__c WHERE Id = :conversation.Id ].ProcessingLockedUntil__c;

            Id secondNextMessageId = AIConversationLockService.releaseLockOrGetNextMessage(conversation.Id, newerMessage.Id);
            Datetime lockedUntilWithNoWaitingMessage = [ SELECT ProcessingLockedUntil__c FROM AIConversation__c WHERE Id = :conversation.Id ].ProcessingLockedUntil__c;
        Test.stopTest();

        Assert.areEqual(newerMessage.Id, nextMessageId, 'The newer message was waiting, so it should be handed the lock.');
        Assert.isNotNull(lockedUntilWithWaitingMessage, 'The lock should be kept for the waiting message.');
        Assert.isNull(secondNextMessageId, 'Nothing is waiting once the newest message has been processed.');
        Assert.isNull(lockedUntilWithNoWaitingMessage, 'The lock should be released when nothing is waiting.');
    }

    @IsTest static void testScenario4() {

        AIConversation__c conversation = [ SELECT Id FROM AIConversation__c LIMIT 1 ];

        Test.startTest();
            AIConversationLockService.extendLock(conversation.Id);
        Test.stopTest();

        Datetime lockedUntil = [ SELECT ProcessingLockedUntil__c FROM AIConversation__c WHERE Id = :conversation.Id ].ProcessingLockedUntil__c;
        Assert.isTrue(lockedUntil > System.now().addMinutes(9), 'The lock should be reset to the 10 minute lock time.');
    }

    @IsTest static void testScenario5() {

        Id notAConversationId = UserInfo.getUserId();

        Test.startTest();
            try {
                AIConversationLockService.lockConversation(notAConversationId);
                Assert.fail('lockConversation should throw for an Id that isn\'t a conversation.');
            } catch (AIConversationLockService.AIConversationLockServiceException ex) {
                Assert.isTrue(ex.getMessage().contains('not found'), 'The error should say the conversation wasn\'t found.');
            }

            Id nextMessageId = AIConversationLockService.releaseLockOrGetNextMessage(notAConversationId, null);
            AIConversationLockService.extendLock(null);
        Test.stopTest();

        Assert.isNull(nextMessageId, 'Nothing can be handed off for an Id that isn\'t a conversation.');
    }
}