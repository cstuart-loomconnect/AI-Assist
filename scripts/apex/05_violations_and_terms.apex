// Run with: SFDX: Execute Anonymous Apex with Editor Contents
// Creates AI Violations (exercises AIViolationTriggerHandler, which increments TriggerCount__c
// and sets LastTriggeredDate__c on the related Rule) and an AI Terms Acknowledgment for the
// running user (exercises AITermsAcknowledgmentTriggerHandler, which syncs AIUserSettings__c).
// Run 01, 02 and 04 first.

Id currentUserId = UserInfo.getUserId();

Map<String, AIViolationRule__c> rulesByName = new Map<String, AIViolationRule__c>();
for (AIViolationRule__c rule : [SELECT Id, Name FROM AIViolationRule__c WHERE Name IN ('Bulk Export Attempt', 'Unauthorised Field Access')]) {
    rulesByName.put(rule.Name, rule);
}

Map<String, AIConversation__c> conversationsByAgentObjectType = new Map<String, AIConversation__c>();
for (AIConversation__c conversation : [SELECT Id, RelatedObjectAPIName__c FROM AIConversation__c WHERE RelatedObjectAPIName__c IN ('Opportunity', 'Case') ORDER BY CreatedDate DESC LIMIT 2]) {
    conversationsByAgentObjectType.put(conversation.RelatedObjectAPIName__c, conversation);
}

if (rulesByName.size() < 2) {
    System.debug('Missing Violation Rules - run 02_prompt_templates_and_violation_rules.apex first.');
} else {

    List<AIViolation__c> violations = new List<AIViolation__c>{
        new AIViolation__c(
            AIViolationRule__c = rulesByName.get('Bulk Export Attempt').Id,
            AIConversation__c = conversationsByAgentObjectType.get('Opportunity')?.Id,
            User__c = currentUserId,
            ViolationType__c = 'Unauthorised Data Access',
            Severity__c = 'High',
            Detail__c = 'User asked the AI to list every Opportunity across all Accounts.',
            RequestBlocked__c = true
        ),
        new AIViolation__c(
            AIViolationRule__c = rulesByName.get('Unauthorised Field Access').Id,
            AIConversation__c = conversationsByAgentObjectType.get('Case')?.Id,
            User__c = currentUserId,
            ViolationType__c = 'PII Masking Failure',
            Severity__c = 'Medium',
            Detail__c = 'User asked for a contact\'s SSN field, which is outside their permitted scope.',
            RequestBlocked__c = true
        )
    };
    insert violations; // After Insert increments TriggerCount__c and sets LastTriggeredDate__c on each related Rule.

    for (AIViolationRule__c updated : [SELECT Id, Name, TriggerCount__c, LastTriggeredDate__c FROM AIViolationRule__c WHERE Id IN :rulesByName.values()]) {
        System.debug(updated);
    }
}

AITermsAcknowledgment__c acknowledgment = new AITermsAcknowledgment__c(
    User__c = currentUserId,
    TermsVersion__c = '2026.1',
    AcknowledgedDate__c = Datetime.now(),
    SignatureText__c = UserInfo.getName()
);
insert acknowledgment; // After Insert syncs AIUserSettings__c.TermsAcknowledged__c / TermsVersionAcknowledged__c / TermsAcknowledgedDate__c for this user.

List<AIUserSettings__c> mySettings = [SELECT Id, TermsAcknowledged__c, TermsVersionAcknowledged__c, TermsAcknowledgedDate__c FROM AIUserSettings__c WHERE User__c = :currentUserId LIMIT 1];

if (mySettings.isEmpty()) {
    System.debug('No AIUserSettings__c exists for the running user yet - it is only auto-created when AIAssistUserType__c is set on the User record. Set that field on your user first if you want to see this sync.');
} else {
    System.debug(mySettings[0]);
}
