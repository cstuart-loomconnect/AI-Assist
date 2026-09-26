/*
Class Name: AiMessageProcessingQueueableTest

=================================================================
=================================================================

Description: Testing utility for AiMessageProcessingQueueable.

=================================================================
=================================================================
Applicable Classes:

AiMessageProcessingQueueable: Coverage 100%

Version      Date               Author                   Description
1.0          2026-09-22         Chandler Stuart          Initial development
1.1          2026-09-26         Chandler Stuart          testScenario4 now expects a single log entry, from execute() - required loaders rethrow unlogged instead of cascading.
*/

@IsTest private class AiMessageProcessingQueueableTest {

    // testScenario1: A minimally-configured Agent/Conversation/Message (no Prompt Template, no Data Sources, no Workflow Actions) still loads cleanly all the way to AIAgentManager, which fails closed on the missing Named Credential - caught and logged rather than thrown, with no reply message inserted.
    // testScenario2: The same flow with an active Prompt Template, an active Data Source link, an active Workflow Action link, and prior message history all present - proving those loader branches populate without error before hitting the same Named Credential failure.
    // testScenario3: A null triggering message Id, and a message Id that no longer resolves to a record (deleted after being enqueued), both return quietly with no error logged and no reply inserted.
    // testScenario4: An Agent with no AI Model Configuration assigned throws inside loadModelConfiguration, is rethrown unlogged and logged exactly once by execute(), and the turn stops before ever reaching AIAgentManager.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = true;
        settings.DisableExceptionLogging__c = false;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        AIModelConfiguration__c modelConfiguration = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
        modelConfiguration.AIProvider__c = 'Anthropic';
        modelConfiguration.ModelIdentifier__c = 'claude-sonnet-5';
        modelConfiguration.IsActive__c = true;
        insert modelConfiguration; // NamedCredential__c deliberately left blank - see class header.

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, false)[0];
        agent.IsActive__c = true;
        agent.AIModelConfiguration__c = modelConfiguration.Id;
        insert agent;

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, 1, true)[0];
        AIConversationMessage__c triggeringMessage = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, 3, 1, true)[0];

        Test.startTest();
            new AiMessageProcessingQueueable(triggeringMessage.Id).execute(null);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM AIConversationMessage__c WHERE AIConversation__c = :conversation.Id AND Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT], 'No reply should have been inserted once the callout failed.');
        Assert.areEqual(1, [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'AIAgentManager' AND MethodName__c = 'executeAiMessage'], 'AIAgentManager should have caught and logged the missing Named Credential itself.');
    }

    @IsTest static void testScenario2() {

        AIModelConfiguration__c modelConfiguration = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
        modelConfiguration.AIProvider__c = 'Anthropic';
        modelConfiguration.ModelIdentifier__c = 'claude-sonnet-5';
        modelConfiguration.IsActive__c = true;
        insert modelConfiguration;

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, false)[0];
        agent.IsActive__c = true;
        agent.AIModelConfiguration__c = modelConfiguration.Id;
        insert agent;

        AIPromptTemplate__c promptTemplate = AIAssistTestDataFactory.createAIPromptTemplates(1, false)[0];
        promptTemplate.AIAgent__c = agent.Id;
        promptTemplate.IsActive__c = true;
        promptTemplate.AISystemContext__c = 'You are a helpful assistant.';
        insert promptTemplate;

        AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id FROM Account', true)[0];
        insert new AIAgentDataSource__c(AIAgent__c = agent.Id, AIDataSource__c = dataSource.Id, IsActive__c = true);

        AIWorkflowAction__c workflowAction = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW, 'Some_Flow', true)[0];
        insert new AIAgentWorkflowAction__c(AIAgent__c = agent.Id, AIWorkflowAction__c = workflowAction.Id, IsActive__c = true);

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, 1, true)[0];
        AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, 3, 2, true); // Prior history before the triggering message.
        AIConversationMessage__c triggeringMessage = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, 3, 1, true)[0];

        Test.startTest();
            new AiMessageProcessingQueueable(triggeringMessage.Id).execute(null);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM AIConversationMessage__c WHERE AIConversation__c = :conversation.Id AND Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT], 'No reply should have been inserted once the callout failed.');
        Assert.areEqual(1, [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'AIAgentManager' AND MethodName__c = 'executeAiMessage'], 'AIAgentManager should still have caught and logged, even with a Prompt Template and tools loaded.');
    }

    @IsTest static void testScenario3() {

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, false)[0];
        agent.IsActive__c = true;
        insert agent;

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, 1, true)[0];
        AIConversationMessage__c messageToDelete = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, 3, 1, true)[0];
        Id deletedMessageId = messageToDelete.Id;
        delete messageToDelete;

        Test.startTest();
            new AiMessageProcessingQueueable(null).execute(null);
            new AiMessageProcessingQueueable(deletedMessageId).execute(null);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM AIPlatformLog__c], 'Neither a null nor a deleted triggering message Id should produce any error.');
        Assert.areEqual(0, [SELECT COUNT() FROM AIConversationMessage__c WHERE AIConversation__c = :conversation.Id], 'No reply should have been inserted - execute() should have returned immediately both times.');
    }

    @IsTest static void testScenario4() {

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, false)[0];
        agent.IsActive__c = true; // AIModelConfiguration__c deliberately left unassigned.
        insert agent;

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, 1, true)[0];
        AIConversationMessage__c triggeringMessage = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, 3, 1, true)[0];

        Test.startTest();
            new AiMessageProcessingQueueable(triggeringMessage.Id).execute(null);
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'AiMessageProcessingQueueable' AND MethodName__c = 'execute' AND ExceptionMessage__c = 'AI Agent has no AI Model Configuration assigned.'], 'The missing AI Model Configuration should be logged once, by execute() - the catch that actually handles it.');
        Assert.areEqual(1, [SELECT COUNT() FROM AIPlatformLog__c], 'One failure should produce exactly one log entry - the failed loader must not log before rethrowing.');
        Assert.areEqual(0, [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'AIAgentManager'], 'The turn should stop at the failed loader rather than cascading into a second error in AIAgentManager.');
        Assert.areEqual(0, [SELECT COUNT() FROM AIConversationMessage__c WHERE AIConversation__c = :conversation.Id AND Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT], 'No reply should have been inserted.');
    }
}