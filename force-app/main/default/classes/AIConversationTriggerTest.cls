/*
Class Name: AIConversationTriggerTest

=================================================================
=================================================================

Description: Testing utility for the AI Conversation Trigger.

=================================================================
=================================================================
Applicable Classes:

AIConversationTrigger: Coverage 100%
AIConversationTriggerHandler: Coverage 100%

Version      Date           Author                   Description
1.0          2026-09-07     Chandler Stuart          Initial development
*/

@IsTest private class AIConversationTriggerTest {

    // testScenario1: Bulk inserting AIConversation__c records for an Agent with a Conversation Created Date retention trigger generates each record's PublicId__c and RetentionExpiryDate__c from today.
    // testScenario2: Bulk closing AIConversation__c records for an Agent with a Conversation Closed Date retention trigger stamps ConversationClosedTimestamp__c and calculates RetentionExpiryDate__c from the close date.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = true;
        settings.DisableExceptionLogging__c = false;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, false)[0];
        agent.ConversationRetentionDays__c = 30;
        agent.RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE;
        insert agent;

        Test.startTest();
            AIAssistTestDataFactory.createAIConversations(agent.Id, 2, true);
        Test.stopTest();

        List<AIConversation__c> inserted = [SELECT PublicId__c, RetentionExpiryDate__c, RetentionCalculationBasis__c FROM AIConversation__c WHERE AIAgent__c = :agent.Id];

        Assert.areEqual(2, inserted.size(), 'Both bulk-inserted conversations should be created.');

        for (AIConversation__c conversation : inserted) {
            Assert.isNotNull(conversation.PublicId__c, 'PublicId__c should be generated on insert.');
            Assert.areEqual(Date.today().addDays(30), conversation.RetentionExpiryDate__c, 'RetentionExpiryDate__c should be calculated from today using the Agent\'s retention days.');
            Assert.areEqual(AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE, conversation.RetentionCalculationBasis__c, 'RetentionCalculationBasis__c should reflect the Created Date trigger.');
        }
    }

    @IsTest static void testScenario2() {

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, false)[0];
        agent.ConversationRetentionDays__c = 14;
        agent.RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CLOSED_DATE;
        insert agent;

        List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(agent.Id, 2, true);

        List<AIConversation__c> conversationsToClose = new List<AIConversation__c>();
        for (AIConversation__c conversation : conversations) {
            conversationsToClose.add(new AIConversation__c(Id = conversation.Id, Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED));
        }

        Test.startTest();
            update conversationsToClose;
        Test.stopTest();

        List<AIConversation__c> closed = [SELECT ConversationClosedTimestamp__c, RetentionExpiryDate__c, RetentionCalculationBasis__c FROM AIConversation__c WHERE AIAgent__c = :agent.Id];

        Assert.areEqual(2, closed.size(), 'Both bulk-closed conversations should be updated.');

        for (AIConversation__c conversation : closed) {
            Assert.isNotNull(conversation.ConversationClosedTimestamp__c, 'ConversationClosedTimestamp__c should be stamped when a conversation newly closes.');
            Assert.areEqual(conversation.ConversationClosedTimestamp__c.date().addDays(14), conversation.RetentionExpiryDate__c, 'RetentionExpiryDate__c should be calculated from the close date using the Agent\'s retention days.');
            Assert.areEqual(AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CLOSED_DATE, conversation.RetentionCalculationBasis__c, 'RetentionCalculationBasis__c should reflect the Closed Date trigger.');
        }
    }
}