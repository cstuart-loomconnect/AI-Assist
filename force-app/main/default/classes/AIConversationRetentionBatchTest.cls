/*
Class Name: AIConversationRetentionBatchTest

=================================================================
=================================================================

Description: Testing utility for the AI Conversation Retention job.

=================================================================
=================================================================
Applicable Classes:

AIConversationRetentionBatch: 83%

Version      Date           Author                   Description
1.0          2026-09-08     Chandler Stuart          Initial development
*/

@IsTest private class AIConversationRetentionBatchTest {

    // testScenario1: Running the batch deletes only AIConversation__c records whose RetentionExpiryDate__c is on or before today, cascade-deleting their child AIConversationMessage__c records, and leaves future-dated and null-dated conversations untouched.
    // testScenario2: When AIConversationRetentionBatch.isTestCustomExceptionThrown forces an exception in execute(), it's caught and logged to AIPlatformLog__c rather than surfacing, and the expired conversations are left untouched.
    // testScenario3: Invoking the job through its Schedulable entry point runs the batch, and when no conversation has reached its retention expiry it deletes nothing.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = true;
        settings.DisableExceptionLogging__c = false;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, true)[0];

        List<AIConversation__c> expired = AIAssistTestDataFactory.createAIConversations(agent.Id, 2, Date.today().addDays(-1), true);
        List<AIConversation__c> expiringToday = AIAssistTestDataFactory.createAIConversations(agent.Id, 1, Date.today(), true);
        List<AIConversation__c> future = AIAssistTestDataFactory.createAIConversations(agent.Id, 2, Date.today().addDays(30), true);
        List<AIConversation__c> noExpiry = AIAssistTestDataFactory.createAIConversations(agent.Id, 1, null, true);

        for (AIConversation__c conversation : expired) {
            AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, 5, 2, true);
        }

        Test.startTest();
            Database.executeBatch(new AIConversationRetentionBatch());
        Test.stopTest();

        Set<Id> remainingIds = new Map<Id, AIConversation__c>([SELECT Id FROM AIConversation__c]).keySet();

        Assert.areEqual(3, remainingIds.size(), 'Only the future-dated and null-dated conversations should remain.');
        Assert.isFalse(remainingIds.contains(expired[0].Id), 'A conversation past its retention expiry should be deleted.');
        Assert.isFalse(remainingIds.contains(expired[1].Id), 'A conversation past its retention expiry should be deleted.');
        Assert.isFalse(remainingIds.contains(expiringToday[0].Id), 'A conversation whose retention expiry is today should be deleted.');
        Assert.isTrue(remainingIds.contains(future[0].Id), 'A future-dated conversation should be retained.');
        Assert.isTrue(remainingIds.contains(future[1].Id), 'A future-dated conversation should be retained.');
        Assert.isTrue(remainingIds.contains(noExpiry[0].Id), 'A conversation with no retention expiry date should be retained.');

        Assert.areEqual(0, [SELECT COUNT() FROM AIConversationMessage__c], 'Child messages should cascade-delete with their expired parent conversation.');
    }

    @IsTest static void testScenario2() {

        AIConversationRetentionBatch.isTestCustomExceptionThrown = true;

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, true)[0];
        List<AIConversation__c> expired = AIAssistTestDataFactory.createAIConversations(agent.Id, 3, Date.today().addDays(-5), true);

        Test.startTest();
            Database.executeBatch(new AIConversationRetentionBatch());
        Test.stopTest();

        Assert.areEqual(3, [SELECT COUNT() FROM AIConversation__c], 'A forced exception in execute() should be caught, leaving the expired conversations untouched.');

        Integer platformLogCount = [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'AIConversationRetentionBatch' AND MethodName__c = 'execute'];
        Assert.areEqual(1, platformLogCount, 'The forced exception should be logged to AIPlatformLog__c.');
    }

    @IsTest static void testScenario3() {

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, true)[0];
        List<AIConversation__c> future = AIAssistTestDataFactory.createAIConversations(agent.Id, 2, Date.today().addDays(10), true);

        Test.startTest();
            new AIConversationRetentionBatch().execute((SchedulableContext) null);
        Test.stopTest();

        Assert.areEqual(2, [SELECT COUNT() FROM AIConversation__c], 'No conversation has reached its retention expiry, so none should be deleted.');
    }
}