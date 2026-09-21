/*
Class Name: AIConversationMessageTriggerTest

=================================================================
=================================================================

Description: Testing utility for the AI Conversation Message Trigger.

=================================================================
=================================================================
Applicable Classes:

AIConversationMessageTrigger: Coverage 100%
AIConversationMessageTriggerHandler: Coverage 85%

Version      Date           Author                   Description
1.0          2026-09-07     Chandler Stuart          Initial development
*/

@IsTest private class AIConversationMessageTriggerTest {

    // testScenario1: Bulk inserting AIConversationMessage__c records across mulSStiple conversations sums each TokenCount__c onto its own parent's ConversationTokenUsage__c, and a message with no TokenCount__c contributes nothing.
    // testScenario2: Bulk inserting additional AIConversationMessage__c records accumulates onto an existing ConversationTokenUsage__c total.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = true;
        settings.DisableExceptionLogging__c = false;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, true)[0];
        List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(agent.Id, 2, true);
        AIConversation__c conversationA = conversations[0];
        AIConversation__c conversationB = conversations[1];

        List<AIConversationMessage__c> messagesToInsert = new List<AIConversationMessage__c>();
        messagesToInsert.addAll(AIAssistTestDataFactory.createAIConversationMessages(conversationA.Id, 100, 3, false));
        messagesToInsert.addAll(AIAssistTestDataFactory.createAIConversationMessages(conversationB.Id, 50, 2, false));
        messagesToInsert.addAll(AIAssistTestDataFactory.createAIConversationMessages(conversationB.Id, null, 1, false));

        Test.startTest();
            insert messagesToInsert;
        Test.stopTest();

        Map<Id, AIConversation__c> updatedById = new Map<Id, AIConversation__c>([SELECT ConversationTokenUsage__c FROM AIConversation__c WHERE Id IN :new Set<Id>{ conversationA.Id, conversationB.Id }]);

        Assert.areEqual(300, updatedById.get(conversationA.Id).ConversationTokenUsage__c, 'Conversation A\'s token usage should be the sum of its own messages\' TokenCount__c.');
        Assert.areEqual(100, updatedById.get(conversationB.Id).ConversationTokenUsage__c, 'Conversation B\'s token usage should exclude the message with no TokenCount__c.');
    }

    @IsTest static void testScenario2() {

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, true)[0];
        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, 1, true)[0];

        conversation.ConversationTokenUsage__c = 300;
        update conversation;

        Test.startTest();
            AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, 25, 4, true);
        Test.stopTest();

        AIConversation__c updated = [SELECT ConversationTokenUsage__c FROM AIConversation__c WHERE Id = :conversation.Id];

        Assert.areEqual(400, updated.ConversationTokenUsage__c, 'Bulk-inserted messages should accumulate onto the existing token usage total.');
    }
}