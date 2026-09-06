// Run with: SFDX: Execute Anonymous Apex with Editor Contents
// Creates AI Data Sources and AI Workflow Actions using SOQL / Flow (not Apex), so the
// Apex-class validation on AIDataSourceTriggerHandler / AIWorkflowActionTriggerHandler
// isn't exercised here - there's no sample class implementing IAIDataSourceExecutor or
// IAIWorkflowActionExecutor in the org yet.

List<AIDataSource__c> dataSources = new List<AIDataSource__c>{
    new AIDataSource__c(
        Description__c = 'Open Opportunities By Account - returns the open Opportunities for the Account the conversation is running against.',
        SourceType__c = 'SOQL',
        BindingType__c = 'Bound',
        TargetObject__c = 'Opportunity',
        SOQLTemplate__c = 'SELECT Id, Name, StageName, Amount, CloseDate FROM Opportunity WHERE AccountId = :recordId AND IsClosed = false',
        OutputDescription__c = 'Returns the open Opportunities for the Account the conversation is running against.',
        IsActive__c = true
    ),
    new AIDataSource__c(
        Description__c = 'Recent High Priority Cases - returns the 10 most recently created High priority Cases across the org.',
        SourceType__c = 'SOQL',
        BindingType__c = 'Unbound',
        TargetObject__c = 'Case',
        SOQLTemplate__c = 'SELECT Id, CaseNumber, Subject, Status FROM Case WHERE Priority = \'High\' ORDER BY CreatedDate DESC LIMIT 10',
        OutputDescription__c = 'Returns the 10 most recently created High priority Cases across the org.',
        IsActive__c = true
    )
};
insert dataSources;

List<AIWorkflowAction__c> workflowActions = new List<AIWorkflowAction__c>{
    new AIWorkflowAction__c(
        ActionName__c = 'Escalate Case',
        ActionType__c = 'Flow',
        FlowAPIName__c = 'Escalate_Case_Flow',
        TargetObject__c = 'Case',
        ExecutionType__c = 'Write',
        RequiresConfirmation__c = true,
        ConfirmationMessage__c = 'This will escalate the case and notify the case owner. Continue?',
        OutputDescription__c = 'Escalates the case and returns the new status.',
        IsActive__c = true
    ),
    new AIWorkflowAction__c(
        ActionName__c = 'Summarize Opportunity History',
        ActionType__c = 'Flow',
        FlowAPIName__c = 'Summarize_Opportunity_History_Flow',
        TargetObject__c = 'Opportunity',
        ExecutionType__c = 'Read Only',
        RequiresConfirmation__c = false,
        OutputDescription__c = 'Returns a plain-language summary of the Opportunity\'s stage history.',
        IsActive__c = true
    )
};
insert workflowActions;

System.debug('Created Data Sources: ' + dataSources);
System.debug('Created Workflow Actions: ' + workflowActions);
