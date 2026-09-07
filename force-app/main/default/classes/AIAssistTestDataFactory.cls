/*
Class Name: AIAssistTestDataFactory

=================================================================
=================================================================

Description: A collection of methods that build (and optionally insert) records used across the
AI Assist test suite.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-06     Chandler Stuart          Initial development
*/

@IsTest public class AIAssistTestDataFactory {

    public static List<User> createStandardUsers(String userType, Integer numberOfUsers, Boolean shouldDoInsert) {

        List<User> users = new List<User>();
        Id standardProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id;

        for (Integer i = 0; i < numberOfUsers; i++) {

            String uniqueName = 'aiassist' + DateTime.now().getTime() + i + Math.abs(Crypto.getRandomInteger());

            users.add(new User(
                FirstName = 'AI',
                LastName = 'Assist Tester',
                Email = uniqueName + '@example.com',
                Username = uniqueName + '@example.com.aiassisttest',
                Alias = 'aiat' + Math.mod(i, 10000),
                TimeZoneSidKey = 'GMT',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                ProfileId = standardProfileId,
                AIAssistUserType__c = userType
            ));
        }

        if (shouldDoInsert && !users.isEmpty()) {
            System.runAs(new User(Id = UserInfo.getUserId())) { insert users; }
        }

        return users;
    }

    public static List<AIAgent__c> createAIAgents(Integer numberOfAgents, Boolean shouldDoInsert) {

        List<AIAgent__c> agents = new List<AIAgent__c>();

        for (Integer i = 0; i < numberOfAgents; i++) {
            agents.add(
                new AIAgent__c(
                    Name = 'AI Assist Test Agent ' + DateTime.now().getTime() + i
                )
            );
        }

        if (shouldDoInsert && !agents.isEmpty()) { insert agents; }

        return agents;
    }

    public static List<AIConversation__c> createAIConversations(Id agentId, Integer numberOfConversations, Boolean shouldDoInsert) {

        List<AIConversation__c> conversations = new List<AIConversation__c>();

        for (Integer i = 0; i < numberOfConversations; i++) {
            conversations.add(new AIConversation__c(
                AIAgent__c = agentId,
                Status__c = 'Active',
                Channel__c = 'Utility Bar'
            ));
        }

        if (shouldDoInsert && !conversations.isEmpty()) { insert conversations; }

        return conversations;
    }

    public static List<AIConversationMessage__c> createAIConversationMessages(Id conversationId, Decimal tokenCount, Integer numberOfMessages, Boolean shouldDoInsert) {

        List<AIConversationMessage__c> messages = new List<AIConversationMessage__c>();

        for (Integer i = 0; i < numberOfMessages; i++) {
            messages.add(new AIConversationMessage__c(
                AIConversation__c = conversationId,
                Sender__c = 'User',
                MessageBody__c = 'Test message ' + i,
                TokenCount__c = tokenCount
            ));
        }

        if (shouldDoInsert && !messages.isEmpty()) { insert messages; }

        return messages;
    }
}