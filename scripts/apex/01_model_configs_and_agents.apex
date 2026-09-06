// Run with: SFDX: Execute Anonymous Apex with Editor Contents
// Creates AI Model Configurations and AI Agents. Run this first - later scripts depend on the Agents it creates.

List<AIModelConfiguration__c> modelConfigs = new List<AIModelConfiguration__c>{
    new AIModelConfiguration__c(
        Name = 'Claude Sonnet - Default',
        AIProvider__c = 'Anthropic',
        ModelIdentifier__c = 'claude-sonnet-5',
        Temperature__c = 0.7,
        MaximumOutputTokens__c = 4096,
        SystemTimeoutSeconds__c = 30,
        IsActive__c = true
    ),
    new AIModelConfiguration__c(
        Name = 'GPT - Fallback',
        AIProvider__c = 'Open AI',
        ModelIdentifier__c = 'gpt-4.1',
        Temperature__c = 0.5,
        MaximumOutputTokens__c = 2048,
        SystemTimeoutSeconds__c = 30,
        IsActive__c = true
    )
};
insert modelConfigs;

List<AIAgent__c> agents = new List<AIAgent__c>{
    new AIAgent__c(
        Name = 'Opportunity Assist Agent',
        ObjectType__c = 'Opportunity',
        AIModelConfiguration__c = modelConfigs[0].Id,
        AIAgentPersona__c = 'A helpful, concise sales assistant.',
        GreetingMessage__c = 'Hi, how can I help with this opportunity?',
        AIFallbackMessage__c = 'Sorry, I could not process that request.',
        IsActive__c = true,
        IsTestModeEnabled__c = false,
        AllowConversationResume__c = true,
        ConversationRetentionDays__c = 30,
        RetentionTrigger__c = 'Conversation Created Date',
        MaxMessagesPerConversation__c = 50,
        MaxTokensPerConversation__c = 20000
    ),
    new AIAgent__c(
        Name = 'Case Assist Agent',
        ObjectType__c = 'Case',
        AIModelConfiguration__c = modelConfigs[1].Id,
        AIAgentPersona__c = 'A patient, thorough support assistant.',
        GreetingMessage__c = 'Hi, how can I help with this case?',
        AIFallbackMessage__c = 'Sorry, I could not process that request.',
        IsActive__c = true,
        IsTestModeEnabled__c = false,
        AllowConversationResume__c = true,
        ConversationRetentionDays__c = 14,
        RetentionTrigger__c = 'Conversation Closed Date',
        MaxMessagesPerConversation__c = 50,
        MaxTokensPerConversation__c = 20000
    )
};
insert agents;

System.debug('Created Model Configs: ' + modelConfigs);
System.debug('Created Agents: ' + agents);
