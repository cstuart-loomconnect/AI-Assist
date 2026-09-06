// Run with: SFDX: Execute Anonymous Apex with Editor Contents
// Creates AI Prompt Templates and AI Violation Rules. Run 01_model_configs_and_agents.apex first.

Map<String, AIAgent__c> agentsByName = new Map<String, AIAgent__c>();
for (AIAgent__c agent : [SELECT Id, Name FROM AIAgent__c WHERE Name IN ('Opportunity Assist Agent', 'Case Assist Agent')]) {
    agentsByName.put(agent.Name, agent);
}

if (agentsByName.size() < 2) {
    System.debug('Missing Agents - run 01_model_configs_and_agents.apex first.');
} else {

    List<AIPromptTemplate__c> promptTemplates = new List<AIPromptTemplate__c>{
        new AIPromptTemplate__c(
            Name = 'Elevated Risk Opportunity',
            AIAgent__c = agentsByName.get('Opportunity Assist Agent').Id,
            AIPrompt__c = 'Flag any opportunity showing signs of elevated risk and explain why.',
            AISystemContext__c = 'You are assisting a sales rep reviewing a specific Opportunity record.',
            AITone__c = 'Professional',
            MaxResponseLength__c = 500,
            IsActive__c = true
        ),
        new AIPromptTemplate__c(
            Name = 'Standard Case Triage',
            AIAgent__c = agentsByName.get('Case Assist Agent').Id,
            AIPrompt__c = 'Summarize the case and suggest a next best action.',
            AISystemContext__c = 'You are assisting a support agent reviewing a specific Case record.',
            AITone__c = 'Friendly',
            MaxResponseLength__c = 500,
            IsActive__c = true
        )
    };
    insert promptTemplates;

    List<AIViolationRule__c> violationRules = new List<AIViolationRule__c>{
        new AIViolationRule__c(
            Name = 'Bulk Export Attempt',
            Agent__c = agentsByName.get('Opportunity Assist Agent').Id,
            SignalTag__c = 'VIOLATION_BULK_EXPORT_ATTEMPT',
            DetectionMethod__c = 'AI_Evaluated',
            AIDetectionInstruction__c = 'Flag if the user asks the AI to export or list all records in bulk.',
            ViolationTypeProduced__c = 'Unauthorized_Data_Access',
            BlockRequest__c = true,
            Active__c = true
        ),
        new AIViolationRule__c(
            Name = 'Unauthorised Field Access',
            Agent__c = agentsByName.get('Case Assist Agent').Id,
            SignalTag__c = 'VIOLATION_UNAUTHORISED_FIELD_ACCESS',
            DetectionMethod__c = 'AI_Evaluated',
            AIDetectionInstruction__c = 'Flag if the user asks for a field outside their permitted scope.',
            ViolationTypeProduced__c = 'PII_Masking_Failure',
            BlockRequest__c = true,
            Active__c = true
        )
    };
    insert violationRules;

    System.debug('Created Prompt Templates: ' + promptTemplates);
    System.debug('Created Violation Rules: ' + violationRules);
}
