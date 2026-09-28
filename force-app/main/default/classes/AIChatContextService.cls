/*
Class Name: AIChatContextService

=================================================================
=================================================================

Description: The record the AI Assist chat window is working on, and which Agent it's talking
to. Builds the context bar's labels and its PII-protected badge (a synced AIPIIRegistry__c row
for the object), and orders/picks the Agent offered for that object - object-specific Agents
before the general ones, then agentKey (an AIAgent__c Id or DeveloperName__c) if it names one.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-28     Chandler Stuart          Split out of AIChatController.
*/

public with sharing class AIChatContextService {

    // The record the window is working on - labels for the context bar and whether a synced PII Registry covers its object. A blank or unreadable record is simply no context (e.g. the utility bar on a Home page).
    public static AIChatDataStructure.RecordContext buildRecordContext(String recordId, String objectApiName) {

        AIChatDataStructure.RecordContext record = new AIChatDataStructure.RecordContext();
        if (String.isBlank(recordId)) return record;

        Id typedRecordId;
        try {
            typedRecordId = Id.valueOf(recordId);
        } catch (Exception invalidId) {
            return record;
        }

        Schema.DescribeSObjectResult objectDescribe = typedRecordId.getSobjectType().getDescribe();

        record.recordId = typedRecordId;
        record.objectApiName = String.isNotBlank(objectApiName) ? objectApiName : objectDescribe.getName();
        record.objectLabel = objectDescribe.getLabel();
        record.objectLabelPlural = objectDescribe.getLabelPlural();
        record.recordName = getRecordName(typedRecordId, objectDescribe);
        record.piiProtected = [ SELECT COUNT() FROM AIPIIRegistry__c WHERE ObjectAPIName__c = :record.objectApiName AND Active__c = true AND SyncStatus__c = :AIAssistApplicationConstants.PII_SYNC_STATUS_SYNCED ] > 0;

        return record;
    }

    // The object's name field varies (Name, CaseNumber, Subject...) - found from the describe. Queried as the user, so a record they can't read shows no name.
    private static String getRecordName(Id recordId, Schema.DescribeSObjectResult objectDescribe) {
        try {

            String nameField;
            for (Schema.SObjectField field : objectDescribe.fields.getMap().values()) {
                if (field.getDescribe().isNameField()) { nameField = field.getDescribe().getName(); break; }
            }
            if (nameField == null) return null;

            List<SObject> records = Database.query('SELECT ' + String.escapeSingleQuotes(nameField) + ' FROM ' + String.escapeSingleQuotes(objectDescribe.getName()) + ' WHERE Id = :recordId WITH USER_MODE LIMIT 1');
            return records.isEmpty() ? null : String.valueOf(records[0].get(nameField));

        } catch (Exception ex) {
            return null; // No access, or an object without a queryable name - the context bar shows the object label alone.
        }
    }

    // Active Agents for this object first, then the ones with no object (usable anywhere).
    public static List<AIChatDataStructure.AgentOption> getAvailableAgents(String objectApiName) {

        List<AIChatDataStructure.AgentOption> objectAgents = new List<AIChatDataStructure.AgentOption>();
        List<AIChatDataStructure.AgentOption> generalAgents = new List<AIChatDataStructure.AgentOption>();

        for (AIAgent__c agent : [ SELECT Id, Name, DeveloperName__c, Description__c, GreetingMessage__c, ObjectType__c, ConversationLoadTrigger__c, AllowConversationResume__c
                                  FROM AIAgent__c
                                  WHERE IsActive__c = true AND (ObjectType__c = null OR ObjectType__c = :objectApiName)
                                  ORDER BY Name
                                  LIMIT 50 ]) {

            AIChatDataStructure.AgentOption option = new AIChatDataStructure.AgentOption();
            option.id = agent.Id;
            option.name = agent.Name;
            option.description = agent.Description__c;
            option.greeting = agent.GreetingMessage__c;
            option.objectApiName = agent.ObjectType__c;
            option.loadTrigger = agent.ConversationLoadTrigger__c;
            option.allowResume = agent.AllowConversationResume__c;

            if (String.isNotBlank(agent.ObjectType__c)) objectAgents.add(option); else generalAgents.add(option);
        }

        objectAgents.addAll(generalAgents);
        return objectAgents;
    }

    public static AIChatDataStructure.AgentOption selectAgent(List<AIChatDataStructure.AgentOption> agents, String agentKey) {

        if (agents.isEmpty()) return null;
        if (String.isBlank(agentKey)) return agents[0];

        for (AIChatDataStructure.AgentOption agent : agents) {
            if (String.valueOf(agent.id) == agentKey || String.valueOf(agent.id).left(15) == agentKey.left(15)) return agent;
        }

        // DeveloperName__c isn't on AgentOption - resolved with one query when the key isn't an Id in the list.
        List<AIAgent__c> byDeveloperName = [ SELECT Id FROM AIAgent__c WHERE DeveloperName__c = :agentKey AND IsActive__c = true LIMIT 1 ];
        if (!byDeveloperName.isEmpty()) {
            for (AIChatDataStructure.AgentOption agent : agents) {
                if (agent.id == byDeveloperName[0].Id) return agent;
            }
        }

        return agents[0];
    }
}
