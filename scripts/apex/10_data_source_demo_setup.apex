// Creates persistent demo data for the AI Data Source flow so it can be browsed in the UI
// (App Launcher -> AI Agent / AI Data Source / AI Conversation tabs) rather than only seen
// in a debug log. Safe to re-run - it deletes its own previous demo records first.

System.debug('=== Cleaning up any previous demo data ===');

delete [SELECT Id FROM AIAgentDataSource__c WHERE DeveloperName__c LIKE 'Demo%'];
delete [SELECT Id FROM AIDataSource__c WHERE DeveloperName__c LIKE 'Demo%'];
delete [SELECT Id FROM AIConversation__c WHERE AIAgent__r.Name = 'AI Data Source Demo Agent'];
delete [SELECT Id FROM AIAgent__c WHERE Name = 'AI Data Source Demo Agent'];
delete [SELECT Id FROM Account WHERE Name LIKE 'Demo Data Source Account%'];
delete [SELECT Id FROM AIPIIFieldMetadata__c WHERE PIIRegistry__r.DeveloperName__c = 'DemoAccountPiiRegistry'];
delete [SELECT Id FROM AIPIIRegistry__c WHERE DeveloperName__c = 'DemoAccountPiiRegistry'];

System.debug('=== Registering Account.Name as PII - AIPiiDataMaskingRule__mdt "Demo Name Substitute" and AIPiiFieldType__mdt "Demo Name Field Type" must already be deployed (force-app/main/default/customMetadata) for masking to actually fire. ===');

AIPIIRegistry__c piiRegistry = new AIPIIRegistry__c(DeveloperName__c = 'DemoAccountPiiRegistry', ObjectAPIName__c = 'Account', Active__c = true);
insert piiRegistry;

insert new AIPIIFieldMetadata__c(
    PIIRegistry__c = piiRegistry.Id,
    FieldAPIName__c = 'Name',
    FieldLabel__c = 'Account Name',
    IsPII__c = true,
    PIIFieldType__c = 'Name' // Matches AIAssistApplicationConstants.PII_FIELD_TYPE_NAME and AIPiiFieldType__mdt "Demo Name Field Type".PIIFieldType__c.
);
System.debug('Registered Account.Name as PII field type "Name".');

System.debug('=== Activating the application ===');

AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
settings.IsApplicationActive__c = true;
settings.IsExceptionLoggingEnabled__c = true;
settings.IsPlatformLoggingEnabled__c = true;
upsert settings;

System.debug('=== Creating demo Accounts to query against ===');

List<Account> demoAccounts = new List<Account>{
    new Account(Name = 'Demo Data Source Account - Acme Corp'),
    new Account(Name = 'Demo Data Source Account - Globex Inc'),
    new Account(Name = 'Demo Data Source Account - Initech LLC')
};
insert demoAccounts;
for (Account a : demoAccounts) { System.debug('Account: ' + a.Id + ' / ' + a.Name); }

System.debug('=== Creating demo AI Agent ===');

AIAgent__c agent = new AIAgent__c(Name = 'AI Data Source Demo Agent');
insert agent;
System.debug('Agent: ' + agent.Id);

System.debug('=== Creating demo AI Conversation ===');

AIConversation__c conversation = new AIConversation__c(AIAgent__c = agent.Id, Status__c = 'Active', Channel__c = 'Utility Bar');
insert conversation;
System.debug('Conversation: ' + conversation.Id);

System.debug('=== Creating three demo AI Data Sources (Bound SOQL, Unbound SOQL, Apex) ===');

AIDataSource__c boundSoqlSource = new AIDataSource__c(
    DeveloperName__c = 'DemoBoundSoqlSource',
    Description__c = 'Demo: looks up one Account by its Id (Bound).',
    SourceType__c = 'SOQL',
    SOQLTemplate__c = 'SELECT Id, Name FROM Account WHERE Id = :recordId',
    TargetObject__c = 'Account',
    BindingType__c = 'Bound',
    IsActive__c = true
);

AIDataSource__c unboundSoqlSource = new AIDataSource__c(
    DeveloperName__c = 'DemoUnboundSoqlSource',
    Description__c = 'Demo: searches Accounts by Name (Unbound) - pass accountName in inputParameters.',
    SourceType__c = 'SOQL',
    SOQLTemplate__c = 'SELECT Id, Name FROM Account WHERE Name = :accountName',
    TargetObject__c = 'Account',
    BindingType__c = 'Unbound',
    IsActive__c = true
);

AIDataSource__c apexSource = new AIDataSource__c(
    DeveloperName__c = 'DemoApexSource',
    Description__c = 'Demo: runs AiDataSourceDemoExecutor - Account by Id if bound, or a Name LIKE search via accountName if unbound.',
    SourceType__c = 'Apex',
    ApexClassName__c = 'AiDataSourceDemoExecutor',
    TargetObject__c = 'Account',
    BindingType__c = 'Unbound',
    IsActive__c = true
);

insert new List<AIDataSource__c>{ boundSoqlSource, unboundSoqlSource, apexSource };

System.debug('Bound SOQL Data Source: ' + boundSoqlSource.Id);
System.debug('Unbound SOQL Data Source: ' + unboundSoqlSource.Id);
System.debug('Apex Data Source: ' + apexSource.Id);

System.debug('=== Linking each Data Source to the demo Agent ===');

insert new List<AIAgentDataSource__c>{
    new AIAgentDataSource__c(DeveloperName__c = 'DemoBoundSoqlLink', AIAgent__c = agent.Id, AIDataSource__c = boundSoqlSource.Id, IsActive__c = true),
    new AIAgentDataSource__c(DeveloperName__c = 'DemoUnboundSoqlLink', AIAgent__c = agent.Id, AIDataSource__c = unboundSoqlSource.Id, IsActive__c = true),
    new AIAgentDataSource__c(DeveloperName__c = 'DemoApexLink', AIAgent__c = agent.Id, AIDataSource__c = apexSource.Id, IsActive__c = true)
};

System.debug('=== Running each Data Source once, right now, so you can see live output - Account.Name is registered as PII, so watch it come back masked ===');

System.debug('--- Bound SOQL, recordId = ' + demoAccounts[0].Id + ', real Name = "' + demoAccounts[0].Name + '" ---');
System.debug(JSON.serializePretty(AiDataSourceDispatcher.execute(boundSoqlSource.Id, demoAccounts[0].Id, null, null, conversation.Id)));

System.debug('--- Unbound SOQL, accountName = "' + demoAccounts[1].Name + '" (real Name) ---');
System.debug(JSON.serializePretty(AiDataSourceDispatcher.execute(unboundSoqlSource.Id, null, new Map<String, Object>{ 'accountName' => demoAccounts[1].Name }, null, conversation.Id)));

System.debug('--- Apex, unbound, accountName LIKE "Initech", real Name = "' + demoAccounts[2].Name + '" ---');
System.debug(JSON.serializePretty(AiDataSourceDispatcher.execute(apexSource.Id, null, new Map<String, Object>{ 'accountName' => 'Initech' }, null, conversation.Id)));

System.debug('=== PII mappings recorded against this conversation (proof masking actually fired) ===');
for (AIPIIMapping__c mapping : [SELECT Id, AIConversation__c FROM AIPIIMapping__c WHERE AIConversation__c = :conversation.Id]) {
    System.debug('AIPIIMapping__c: ' + mapping.Id + ' (the real<->fake pairs are stored as JSON inside it, not queried here to avoid printing real PII to the log)');
}

System.debug('=== DONE - browse the records in the UI: ===');
System.debug('AI Agent:          /' + agent.Id);
System.debug('AI Conversation:   /' + conversation.Id);
System.debug('Bound Data Source: /' + boundSoqlSource.Id);
System.debug('Unbound Data Src:  /' + unboundSoqlSource.Id);
System.debug('Apex Data Source:  /' + apexSource.Id);
