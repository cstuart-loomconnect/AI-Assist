// Run with: SFDX: Execute Anonymous Apex with Editor Contents
// Creates AI Conversations and AI Conversation Messages. Run 01_model_configs_and_agents.apex
// and 02_prompt_templates_and_violation_rules.apex first.
// Inserting the messages below exercises AIConversationMessageTriggerHandler, which rolls
// each message's TokenCount__c up onto its parent Conversation's ConversationTokenUsage__c.
// Updating a conversation's Status__c to Closed further down exercises
// AIConversationTriggerHandler's Retention Expiry Date calculation from the close.

Map<String, AIAgent__c> agentsByName = new Map<String, AIAgent__c>();
for (AIAgent__c agent : [SELECT Id, Name FROM AIAgent__c WHERE Name IN ('Opportunity Assist Agent', 'Case Assist Agent')]) {
    agentsByName.put(agent.Name, agent);
}

Map<String, AIPromptTemplate__c> promptTemplatesByName = new Map<String, AIPromptTemplate__c>();
for (AIPromptTemplate__c template : [SELECT Id, Name FROM AIPromptTemplate__c WHERE Name IN ('Elevated Risk Opportunity', 'Standard Case Triage')]) {
    promptTemplatesByName.put(template.Name, template);
}

if (agentsByName.size() < 2) {
    System.debug('Missing Agents - run 01_model_configs_and_agents.apex first.');
} else {

    List<AIConversation__c> conversations = new List<AIConversation__c>{
        new AIConversation__c(
            AIAgent__c = agentsByName.get('Opportunity Assist Agent').Id,
            AIPromptTemplate__c = promptTemplatesByName.get('Elevated Risk Opportunity')?.Id,
            Channel__c = 'Record Page Chat',
            RelatedObjectAPIName__c = 'Opportunity',
            Status__c = 'Active'
        ),
        new AIConversation__c(
            AIAgent__c = agentsByName.get('Case Assist Agent').Id,
            AIPromptTemplate__c = promptTemplatesByName.get('Standard Case Triage')?.Id,
            Channel__c = 'Utility Bar',
            RelatedObjectAPIName__c = 'Case',
            Status__c = 'Active'
        )
    };
    insert conversations; // Before Insert calculates RetentionExpiryDate__c for the Agent whose Retention Trigger is Conversation Created Date.

    List<AIConversationMessage__c> messages = new List<AIConversationMessage__c>{
        new AIConversationMessage__c(AIConversation__c = conversations[0].Id, Sender__c = 'User', MessageBody__c = 'Is this opportunity at risk?', TokenCount__c = 12),
        new AIConversationMessage__c(AIConversation__c = conversations[0].Id, Sender__c = 'AI Agent', MessageBody__c = 'It shows two signs of elevated risk: no activity in 30 days and a slipped close date.', TokenCount__c = 28),
        new AIConversationMessage__c(AIConversation__c = conversations[1].Id, Sender__c = 'User', MessageBody__c = 'Summarize this case for me.', TokenCount__c = 10),
        new AIConversationMessage__c(AIConversation__c = conversations[1].Id, Sender__c = 'AI Agent', MessageBody__c = 'This case is a High priority billing issue, opened 2 days ago, currently unassigned.', TokenCount__c = 24)
    };
    insert messages; // After Insert rolls TokenCount__c up onto ConversationTokenUsage__c on each parent Conversation.

    // Close the second conversation to exercise the Conversation Closed Date retention path.
    AIConversation__c conversationToClose = new AIConversation__c(
        Id = conversations[1].Id,
        Status__c = 'Closed',
        ConversationCloseReason__c = 'User Closed'
    );
    update conversationToClose;

    System.debug('Created Conversations: ' + conversations);
    System.debug('Created Messages: ' + messages);

    for (AIConversation__c updated : [SELECT Id, Status__c, ConversationTokenUsage__c, RetentionExpiryDate__c, RetentionCalculationBasis__c FROM AIConversation__c WHERE Id IN :conversations]) {
        System.debug(updated);
    }
}
