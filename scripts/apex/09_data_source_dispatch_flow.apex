// Manual walkthrough of the AI Data Source flow: AiDataSourceDispatcher -> AiSoqlTemplateRunner / IAIDataSourceExecutor -> AiDataSourceResultProcessor.

System.debug('=== STEP 0: Setup ===');

AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
settings.IsApplicationActive__c = true;
settings.IsExceptionLoggingEnabled__c = true;
settings.IsPlatformLoggingEnabled__c = true;
upsert settings;

Account testAccount = new Account(Name = 'Manual Test Account ' + DateTime.now().getTime());
insert testAccount;
System.debug('Created test Account: ' + testAccount.Id + ' / ' + testAccount.Name);

AIAgent__c agent = new AIAgent__c(Name = 'Manual Test Agent ' + DateTime.now().getTime());
insert agent;
AIConversation__c conversation = new AIConversation__c(AIAgent__c = agent.Id, Status__c = 'Active', Channel__c = 'Utility Bar');
insert conversation;
System.debug('Created AIConversation__c: ' + conversation.Id);

System.debug('=== STEP 1: Bound SOQL Data Source (recordId supplied) ===');

AIDataSource__c boundSource = new AIDataSource__c(
    SourceType__c = 'SOQL',
    SOQLTemplate__c = 'SELECT Id, Name FROM Account WHERE Id = :recordId',
    IsActive__c = true,
    DeveloperName__c = 'ManualTestBoundSource'
);
insert boundSource;
System.debug('Created Bound AIDataSource__c: ' + boundSource.Id);

try {
    List<Object> boundResults = AiDataSourceDispatcher.execute(boundSource.Id, testAccount.Id, null, null, conversation.Id);
    System.debug('Bound SOQL result: ' + JSON.serializePretty(boundResults));
} catch (Exception ex) {
    System.debug('Bound SOQL FAILED: ' + ex.getMessage());
}

System.debug('=== STEP 2: Unbound SOQL Data Source (no recordId, uses inputParameters) ===');

AIDataSource__c unboundSource = new AIDataSource__c(
    SourceType__c = 'SOQL',
    SOQLTemplate__c = 'SELECT Id, Name FROM Account WHERE Name = :accountName',
    IsActive__c = true,
    DeveloperName__c = 'ManualTestUnboundSource'
);
insert unboundSource;
System.debug('Created Unbound AIDataSource__c: ' + unboundSource.Id);

try {
    List<Object> unboundResults = AiDataSourceDispatcher.execute(unboundSource.Id, null, new Map<String, Object>{ 'accountName' => testAccount.Name }, null, conversation.Id);
    System.debug('Unbound SOQL result: ' + JSON.serializePretty(unboundResults));
} catch (Exception ex) {
    System.debug('Unbound SOQL FAILED: ' + ex.getMessage());
}

System.debug('=== STEP 3: Apex Data Source path - skipped in this script. AiDataSourceDispatcherTest.TestExecutor is an @IsTest class and cannot be instantiated via Type.forName() outside test context. This path is exercised by AiDataSourceDispatcherTest.testScenario2 instead. ===');

System.debug('=== STEP 4: Error path - inactive Data Source ===');

AIDataSource__c inactiveSource = new AIDataSource__c(
    SourceType__c = 'SOQL',
    SOQLTemplate__c = 'SELECT Id FROM Account',
    IsActive__c = false,
    DeveloperName__c = 'ManualTestInactiveSource'
);
insert inactiveSource;

try {
    AiDataSourceDispatcher.execute(inactiveSource.Id, null, null, null, conversation.Id);
    System.debug('UNEXPECTED: inactive Data Source did not throw');
} catch (Exception ex) {
    System.debug('Expected failure for inactive Data Source: ' + ex.getMessage());
}

System.debug('=== DONE ===');
