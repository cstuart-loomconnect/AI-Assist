// Real-world-shaped run of the Data Source flow: realistic Accounts/Contacts (not placeholder
// "Demo" names), realistic Agent tool-call scenarios (single-record lookup, filtered search,
// and a parent-with-child-subquery pull), and PII masking actually engaged on Name/Email/Phone
// so you can see real values go in and masked ones come out. No LLM callout is involved -
// there's no such component in this codebase yet; this calls AiDataSourceDispatcher exactly
// the way an Agent's tool-calling layer would.
//
// Safe to re-run - deletes its own previous "RealWorld" records first.

System.debug('=== Cleaning up any previous run ===');

delete [SELECT Id FROM AIAgentDataSource__c WHERE DeveloperName__c LIKE 'RealWorld%'];
delete [SELECT Id FROM AIDataSource__c WHERE DeveloperName__c LIKE 'RealWorld%'];
delete [SELECT Id FROM AIConversation__c WHERE AIAgent__r.Name = 'Real World Scenario Agent'];
delete [SELECT Id FROM AIAgent__c WHERE Name = 'Real World Scenario Agent'];
delete [SELECT Id FROM Contact WHERE Account.Name IN ('Meridian Health Partners', 'Blackstone & Voss LLP', 'Cascade Robotics Inc.')];
delete [SELECT Id FROM Account WHERE Name IN ('Meridian Health Partners', 'Blackstone & Voss LLP', 'Cascade Robotics Inc.')];
delete [SELECT Id FROM AIPIIFieldMetadata__c WHERE PIIRegistry__r.DeveloperName__c LIKE 'RealWorld%'];
delete [SELECT Id FROM AIPIIRegistry__c WHERE DeveloperName__c LIKE 'RealWorld%'];

System.debug('=== Activating the application ===');

AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
settings.IsApplicationActive__c = true;
settings.IsExceptionLoggingEnabled__c = true;
settings.IsPlatformLoggingEnabled__c = true;
upsert settings;

System.debug('=== Registering PII fields - Account.Name and Contact.Name/Email/Phone ===');
System.debug('Name uses the AIPiiFieldType__mdt "Name" -> "Substitute_First_Names" rule (real substitution). Email/Phone use "Mask_Digits", which falls through to the safe REDACTED fallback - that is expected, not a bug, since Mask_Digits\' strategy is not one AIPiiPseudonymizationService trusts.');

AIPIIRegistry__c accountPiiRegistry = new AIPIIRegistry__c(DeveloperName__c = 'RealWorldAccountPii', ObjectAPIName__c = 'Account', Active__c = true);
AIPIIRegistry__c contactPiiRegistry = new AIPIIRegistry__c(DeveloperName__c = 'RealWorldContactPii', ObjectAPIName__c = 'Contact', Active__c = true);
insert new List<AIPIIRegistry__c>{ accountPiiRegistry, contactPiiRegistry };

insert new List<AIPIIFieldMetadata__c>{
    new AIPIIFieldMetadata__c(PIIRegistry__c = accountPiiRegistry.Id, FieldAPIName__c = 'Name', FieldLabel__c = 'Account Name', IsPII__c = true, PIIFieldType__c = 'Name'),
    new AIPIIFieldMetadata__c(PIIRegistry__c = contactPiiRegistry.Id, FieldAPIName__c = 'Name', FieldLabel__c = 'Contact Name', IsPII__c = true, PIIFieldType__c = 'Name'),
    new AIPIIFieldMetadata__c(PIIRegistry__c = contactPiiRegistry.Id, FieldAPIName__c = 'Email', FieldLabel__c = 'Email', IsPII__c = true, PIIFieldType__c = 'Email'),
    new AIPIIFieldMetadata__c(PIIRegistry__c = contactPiiRegistry.Id, FieldAPIName__c = 'Phone', FieldLabel__c = 'Phone', IsPII__c = true, PIIFieldType__c = 'Phone')
};

System.debug('=== Creating realistic Accounts and Contacts ===');

List<Account> accounts = new List<Account>{
    new Account(Name = 'Meridian Health Partners', Industry = 'Healthcare'),
    new Account(Name = 'Blackstone & Voss LLP', Industry = 'Finance'),
    new Account(Name = 'Cascade Robotics Inc.', Industry = 'Technology')
};
insert accounts;

List<Contact> contacts = new List<Contact>{
    new Contact(AccountId = accounts[0].Id, FirstName = 'Elena', LastName = 'Whitfield', Email = 'elena.whitfield@meridianhealth.example', Phone = '415-555-0142'),
    new Contact(AccountId = accounts[0].Id, FirstName = 'Marcus', LastName = 'Chen', Email = 'marcus.chen@meridianhealth.example', Phone = '415-555-0177'),
    new Contact(AccountId = accounts[1].Id, FirstName = 'Priya', LastName = 'Nair', Email = 'priya.nair@blackstonevoss.example', Phone = '212-555-0193'),
    new Contact(AccountId = accounts[2].Id, FirstName = 'Owen', LastName = 'Marsh', Email = 'owen.marsh@cascaderobotics.example', Phone = '206-555-0164')
};
insert contacts;

for (Account a : accounts) { System.debug('Account: ' + a.Id + ' / ' + a.Name + ' (' + a.Industry + ')'); }
for (Contact c : contacts) { System.debug('Contact: ' + c.Id + ' / ' + c.FirstName + ' ' + c.LastName + ' / ' + c.Email + ' / ' + c.Phone); }

System.debug('=== Creating Agent and Conversation ===');

AIAgent__c agent = new AIAgent__c(Name = 'Real World Scenario Agent');
insert agent;

AIConversation__c conversation = new AIConversation__c(AIAgent__c = agent.Id, Status__c = 'Active', Channel__c = 'Utility Bar');
insert conversation;
System.debug('Agent: ' + agent.Id + ' / Conversation: ' + conversation.Id);

System.debug('=== Creating four realistic Data Sources ===');

AIDataSource__c accountLookup = new AIDataSource__c(
    DeveloperName__c = 'RealWorldAccountLookup',
    Description__c = 'Real world: "look up this account" - Bound SOQL by Id.',
    SourceType__c = 'SOQL',
    SOQLTemplate__c = 'SELECT Id, Name, Industry FROM Account WHERE Id = :recordId',
    TargetObject__c = 'Account',
    BindingType__c = 'Bound',
    IsActive__c = true
);

AIDataSource__c accountSearch = new AIDataSource__c(
    DeveloperName__c = 'RealWorldAccountSearch',
    Description__c = 'Real world: "find accounts in this industry" - Unbound SOQL filtered search.',
    SourceType__c = 'SOQL',
    SOQLTemplate__c = 'SELECT Id, Name, Industry FROM Account WHERE Industry = :industry',
    TargetObject__c = 'Account',
    BindingType__c = 'Unbound',
    IsActive__c = true
);

AIDataSource__c accountWithContacts = new AIDataSource__c(
    DeveloperName__c = 'RealWorldAccountContacts',
    Description__c = 'Real world: "who are the contacts at this account" - Bound SOQL with a child subquery, proving PII masking reaches nested records too.',
    SourceType__c = 'SOQL',
    SOQLTemplate__c = 'SELECT Id, Name, (SELECT Id, Name, Email, Phone FROM Contacts) FROM Account WHERE Id = :recordId',
    TargetObject__c = 'Account',
    BindingType__c = 'Bound',
    IsActive__c = true
);

AIDataSource__c apexAccountLookup = new AIDataSource__c(
    DeveloperName__c = 'RealWorldApexAccountLookup',
    Description__c = 'Real world: same single-account lookup as RealWorldAccountLookup, but via an Apex executor instead of a SOQL template - proves both retrieval paths mask identically.',
    SourceType__c = 'Apex',
    ApexClassName__c = 'AiDataSourceDemoExecutor',
    TargetObject__c = 'Account',
    BindingType__c = 'Bound',
    IsActive__c = true
);

insert new List<AIDataSource__c>{ accountLookup, accountSearch, accountWithContacts, apexAccountLookup };

insert new List<AIAgentDataSource__c>{
    new AIAgentDataSource__c(DeveloperName__c = 'RealWorldAccountLookupLink', AIAgent__c = agent.Id, AIDataSource__c = accountLookup.Id, IsActive__c = true),
    new AIAgentDataSource__c(DeveloperName__c = 'RealWorldAccountSearchLink', AIAgent__c = agent.Id, AIDataSource__c = accountSearch.Id, IsActive__c = true),
    new AIAgentDataSource__c(DeveloperName__c = 'RealWorldAccountContactsLink', AIAgent__c = agent.Id, AIDataSource__c = accountWithContacts.Id, IsActive__c = true),
    new AIAgentDataSource__c(DeveloperName__c = 'RealWorldApexAccountLookupLink', AIAgent__c = agent.Id, AIDataSource__c = apexAccountLookup.Id, IsActive__c = true)
};

System.debug('=== Scenario 1: Bound SOQL account lookup ===');
System.debug('Real Name going in: "' + accounts[0].Name + '"');
List<Object> lookupResult = AiDataSourceDispatcher.execute(accountLookup.Id, accounts[0].Id, null, null, conversation.Id);
System.debug('Result: ' + JSON.serializePretty(lookupResult));
Map<String, Object> lookupRecord = (Map<String, Object>) lookupResult[0];
System.debug((lookupRecord.get('Name') != accounts[0].Name ? 'PASS' : 'FAIL') + ': Name came back masked (real "' + accounts[0].Name + '" -> masked "' + lookupRecord.get('Name') + '").');

System.debug('=== Recording the conversation turn behind Scenario 1 ===');

List<AIConversationMessage__c> messages = new List<AIConversationMessage__c>();
messages.add(new AIConversationMessage__c(AIConversation__c = conversation.Id, Sender__c = 'User', MessageBody__c = 'Can you pull up the account for our healthcare client and tell me what industry they\'re in?', TokenCount__c = 22));
messages.add(new AIConversationMessage__c(AIConversation__c = conversation.Id, Sender__c = 'System', MessageBody__c = 'Invoked Data Source "RealWorldAccountLookup" (recordId=' + accounts[0].Id + ').', TokenCount__c = 10));
messages.add(new AIConversationMessage__c(AIConversation__c = conversation.Id, Sender__c = 'AI Agent', MessageBody__c = 'I found the account - "' + lookupRecord.get('Name') + '" is in the ' + lookupRecord.get('Industry') + ' industry.', TokenCount__c = 20));
insert messages;

System.debug('=== Scenario 2: Unbound SOQL account search by Industry = "Technology" ===');
List<Object> searchResult = AiDataSourceDispatcher.execute(accountSearch.Id, null, new Map<String, Object>{ 'industry' => 'Technology' }, null, conversation.Id);
System.debug('Result: ' + JSON.serializePretty(searchResult));
System.debug((searchResult.size() == 1 ? 'PASS' : 'FAIL') + ': Found exactly 1 Technology account (Cascade Robotics Inc., masked).');

System.debug('=== Scenario 3: Bound SOQL account + child Contacts subquery, PII masked at both levels ===');
System.debug('Real Contacts going in: ' + contacts[0].FirstName + ' ' + contacts[0].LastName + ' (' + contacts[0].Email + ', ' + contacts[0].Phone + '), ' + contacts[1].FirstName + ' ' + contacts[1].LastName + ' (' + contacts[1].Email + ', ' + contacts[1].Phone + ')');
List<Object> withContactsResult = AiDataSourceDispatcher.execute(accountWithContacts.Id, accounts[0].Id, null, null, conversation.Id);
System.debug('Result: ' + JSON.serializePretty(withContactsResult));
Map<String, Object> withContactsRecord = (Map<String, Object>) withContactsResult[0];
List<Object> flattenedContacts = (List<Object>) withContactsRecord.get('Contacts');
System.debug((flattenedContacts != null && flattenedContacts.size() == 2 ? 'PASS' : 'FAIL') + ': Both Contacts for the account came back nested under "Contacts".');
for (Object contactObj : flattenedContacts) {
    Map<String, Object> flattenedContact = (Map<String, Object>) contactObj;
    System.debug('  Nested Contact - Name: ' + flattenedContact.get('Name') + ', Email: ' + flattenedContact.get('Email') + ', Phone: ' + flattenedContact.get('Phone'));
}

System.debug('=== Recording the conversation turn behind Scenario 3 ===');

Map<String, Object> firstFlattenedContact = (Map<String, Object>) flattenedContacts[0];
Map<String, Object> secondFlattenedContact = (Map<String, Object>) flattenedContacts[1];

List<AIConversationMessage__c> contactMessages = new List<AIConversationMessage__c>();
contactMessages.add(new AIConversationMessage__c(AIConversation__c = conversation.Id, Sender__c = 'User', MessageBody__c = 'Who are the contacts there, and what\'s the best way to reach them?', TokenCount__c = 15));
contactMessages.add(new AIConversationMessage__c(AIConversation__c = conversation.Id, Sender__c = 'System', MessageBody__c = 'Invoked Data Source "RealWorldAccountContacts" (recordId=' + accounts[0].Id + ').', TokenCount__c = 10));
contactMessages.add(new AIConversationMessage__c(
    AIConversation__c = conversation.Id,
    Sender__c = 'AI Agent',
    MessageBody__c = 'There are two contacts on file: ' + firstFlattenedContact.get('Name') + ' (' + firstFlattenedContact.get('Email') + ', ' + firstFlattenedContact.get('Phone') + ') and ' + secondFlattenedContact.get('Name') + ' (' + secondFlattenedContact.get('Email') + ', ' + secondFlattenedContact.get('Phone') + ').',
    TokenCount__c = 38
));
insert contactMessages;

System.debug('=== Scenario 4: Apex executor, same account, proving both retrieval paths mask identically ===');
List<Object> apexResult = AiDataSourceDispatcher.execute(apexAccountLookup.Id, accounts[0].Id, null, null, conversation.Id);
System.debug('Result: ' + JSON.serializePretty(apexResult));
Map<String, Object> apexRecord = (Map<String, Object>) apexResult[0];
System.debug((apexRecord.get('Name') == lookupRecord.get('Name') ? 'PASS' : 'FAIL') + ': SOQL path and Apex path masked the same real value to the same fake value within this conversation (' + apexRecord.get('Name') + ').');

System.debug('=== PII mappings recorded against this conversation ===');
Integer mappingCount = [SELECT COUNT() FROM AIPIIMapping__c WHERE AIConversation__c = :conversation.Id];
System.debug((mappingCount > 0 ? 'PASS' : 'FAIL') + ': ' + mappingCount + ' AIPIIMapping__c record(s) exist for this conversation.');

Integer messageCount = [SELECT COUNT() FROM AIConversationMessage__c WHERE AIConversation__c = :conversation.Id];
System.debug((messageCount == 6 ? 'PASS' : 'FAIL') + ': ' + messageCount + ' AIConversationMessage__c record(s) recorded against this conversation (expected 6 - two User/System/AI Agent turns).');

System.debug('=== DONE - browse the records in the UI: ===');
System.debug('AI Agent:            /' + agent.Id);
System.debug('AI Conversation:     /' + conversation.Id + ' (open this to see the message thread)');
System.debug('Account Lookup:      /' + accountLookup.Id);
System.debug('Account Search:      /' + accountSearch.Id);
System.debug('Account + Contacts:  /' + accountWithContacts.Id);
System.debug('Apex Account Lookup: /' + apexAccountLookup.Id);
