/*
Class Name: AITokenUsageServiceTest

=================================================================
=================================================================

Description: Testing utility for AITokenUsageService.

=================================================================
=================================================================
Applicable Classes:

AITokenUsageService

Version      Date           Author                   Description
1.0          2026-09-27     Chandler Stuart          Initial development
*/

@IsTest private class AITokenUsageServiceTest {

    // testScenario1: getGlobalUsage, getAgentUsage and getUserUsage sum ConversationTokenUsage__c for conversations created within the range, include both end dates, and leave out a conversation created before the range.
    // testScenario2: getConversationUsage returns the conversation's running total, and 0 when it has none.
    // testScenario3: A range with no conversations returns 0, not null.
    // testScenario4: A missing or reversed date range, a wrong-type Id, and a conversation that doesn't exist each throw AITokenUsageServiceException.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        upsert settings;

        List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(2, true);

        List<AIConversation__c> conversations = new List<AIConversation__c>();
        conversations.addAll(AIAssistTestDataFactory.createAIConversations(agents[0].Id, 2, false));
        conversations.addAll(AIAssistTestDataFactory.createAIConversations(agents[1].Id, 2, false));

        conversations[0].ConversationTokenUsage__c = 100;
        conversations[1].ConversationTokenUsage__c = 200;
        conversations[2].ConversationTokenUsage__c = 50;
        conversations[3].ConversationTokenUsage__c = 1000; // Moved to before the test range below.
        insert conversations;

        Test.setCreatedDate(conversations[3].Id, Datetime.now().addDays(-10));
    }

    @IsTest static void testScenario1() {

        AIAgent__c firstAgent = [ SELECT Id FROM AIAgent__c WHERE Id IN (SELECT AIAgent__c FROM AIConversation__c WHERE ConversationTokenUsage__c = 100) ];
        AIAgent__c secondAgent = [ SELECT Id FROM AIAgent__c WHERE Id IN (SELECT AIAgent__c FROM AIConversation__c WHERE ConversationTokenUsage__c = 50) ];

        // A single-day range - today is both the start and the end date, so this also proves both ends are inclusive.
        Date today = Date.today();

        Test.startTest();
            Decimal globalUsage = AITokenUsageService.getGlobalUsage(today, today);
            Decimal firstAgentUsage = AITokenUsageService.getAgentUsage(firstAgent.Id, today, today);
            Decimal secondAgentUsage = AITokenUsageService.getAgentUsage(secondAgent.Id, today, today);
            Decimal userUsage = AITokenUsageService.getUserUsage(UserInfo.getUserId(), today, today);
            Decimal widerGlobalUsage = AITokenUsageService.getGlobalUsage(today.addDays(-30), today);
        Test.stopTest();

        Assert.areEqual(350, globalUsage, 'Global usage should sum every conversation created in the range, leaving out the older one.');
        Assert.areEqual(300, firstAgentUsage, 'Agent usage should only sum that Agent\'s conversations.');
        Assert.areEqual(50, secondAgentUsage, 'Agent usage should leave out that Agent\'s conversation created before the range.');
        Assert.areEqual(350, userUsage, 'User usage should sum the conversations the user owns in the range.');
        Assert.areEqual(1350, widerGlobalUsage, 'A range covering the older conversation should include it.');
    }

    @IsTest static void testScenario2() {

        AIConversation__c conversationWithUsage = [ SELECT Id FROM AIConversation__c WHERE ConversationTokenUsage__c = 200 LIMIT 1 ];

        AIAgent__c agent = [ SELECT Id FROM AIAgent__c LIMIT 1 ];
        AIConversation__c conversationWithoutUsage = AIAssistTestDataFactory.createAIConversations(agent.Id, 1, true)[0];

        Test.startTest();
            Decimal usage = AITokenUsageService.getConversationUsage(conversationWithUsage.Id);
            Decimal noUsage = AITokenUsageService.getConversationUsage(conversationWithoutUsage.Id);
        Test.stopTest();

        Assert.areEqual(200, usage, 'Should return the conversation\'s running total.');
        Assert.areEqual(0, noUsage, 'A conversation with no usage should return 0, not null.');
    }

    @IsTest static void testScenario3() {

        Date longAgo = Date.today().addYears(-5);

        Test.startTest();
            Decimal usage = AITokenUsageService.getGlobalUsage(longAgo, longAgo);
        Test.stopTest();

        Assert.areEqual(0, usage, 'A range with no conversations should return 0, not null.');
    }

    @IsTest static void testScenario4() {

        Date today = Date.today();
        AIAgent__c agent = [ SELECT Id FROM AIAgent__c LIMIT 1 ];
        AIConversation__c conversation = [ SELECT Id FROM AIConversation__c LIMIT 1 ];

        // A real conversation Id, deleted so it no longer resolves.
        AIConversation__c deletedConversation = AIAssistTestDataFactory.createAIConversations(agent.Id, 1, true)[0];
        delete deletedConversation;

        Test.startTest();

            try {
                AITokenUsageService.getGlobalUsage(null, today);
                Assert.fail('A missing start date should have thrown.');
            } catch (AITokenUsageService.AITokenUsageServiceException ex) {
                Assert.isTrue(ex.getMessage().contains('start date and an end date are required'), 'Error should explain the dates are required.');
            }

            try {
                AITokenUsageService.getUserUsage(UserInfo.getUserId(), today, today.addDays(-1));
                Assert.fail('A reversed range should have thrown.');
            } catch (AITokenUsageService.AITokenUsageServiceException ex) {
                Assert.isTrue(ex.getMessage().contains('on or before the end date'), 'Error should explain the range is reversed.');
            }

            try {
                AITokenUsageService.getAgentUsage(conversation.Id, today, today);
                Assert.fail('A conversation Id passed as an Agent Id should have thrown.');
            } catch (AITokenUsageService.AITokenUsageServiceException ex) {
                Assert.isTrue(ex.getMessage().contains('valid AI Agent Id'), 'Error should explain the Agent Id is invalid.');
            }

            try {
                AITokenUsageService.getUserUsage(agent.Id, today, today);
                Assert.fail('An Agent Id passed as a User Id should have thrown.');
            } catch (AITokenUsageService.AITokenUsageServiceException ex) {
                Assert.isTrue(ex.getMessage().contains('valid User Id'), 'Error should explain the User Id is invalid.');
            }

            try {
                AITokenUsageService.getConversationUsage(deletedConversation.Id);
                Assert.fail('A conversation that no longer exists should have thrown.');
            } catch (AITokenUsageService.AITokenUsageServiceException ex) {
                Assert.isTrue(ex.getMessage().contains('not found'), 'Error should explain the conversation was not found.');
            }

        Test.stopTest();
    }
}