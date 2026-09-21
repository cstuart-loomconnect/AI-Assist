/*
Class Name: AIAssistTestDataFactory

=================================================================
=================================================================

Description: A collection of methods that build (and optionally insert) records used across the
AI Assist test suite.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-06     Chandler Stuart          Initial development
*/

@IsTest public class AIAssistTestDataFactory {

    private static Integer fakeMetadataIdSequence = 0;

    // Custom Metadata records can't be inserted via DML, so tests that need AIPiiFieldType__mdt / AIPiiComplianceGroup__mdt
    // records build them in memory with a fake Id and inject them into AIPiiFieldTypeClassifier's test-only seams.
    private static Id generateFakeMetadataId(Schema.SObjectType sObjType) {
        fakeMetadataIdSequence++;
        String keyPrefix = sObjType.getDescribe().getKeyPrefix();
        return Id.valueOf(keyPrefix + String.valueOf(fakeMetadataIdSequence).leftPad(12, '0'));
    }

    public static AIPiiComplianceGroup__mdt createAIPiiComplianceGroup(String masterLabel, Boolean isActive) {
        return new AIPiiComplianceGroup__mdt(
            Id = generateFakeMetadataId(AIPiiComplianceGroup__mdt.SObjectType),
            MasterLabel = masterLabel,
            Active__c = isActive
        );
    }

    public static AIPiiFieldType__mdt createAIPiiFieldType(String keyword, String matchField, String piiFieldType, Id complianceGroupId, Boolean isComplianceGroupFallback, Decimal displayOrder) {
        return new AIPiiFieldType__mdt(
            Keyword__c = keyword,
            MatchField__c = matchField,
            PIIFieldType__c = piiFieldType,
            ComplianceGroup__c = complianceGroupId,
            IsComplianceGroupFallback__c = isComplianceGroupFallback,
            DisplayOrder__c = displayOrder
        );
    }

    public static List<User> createStandardUsers(String userType, Integer numberOfUsers, Boolean shouldDoInsert) {

        List<User> users = new List<User>();
        Id standardProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id;

        for (Integer i = 0; i < numberOfUsers; i++) {

            String uniqueName = 'aiassist' + DateTime.now().getTime() + i + Math.abs(Crypto.getRandomInteger());

            users.add(new User(
                FirstName = 'AI',
                LastName = 'Assist Tester',
                Email = uniqueName + '@example.com',
                Username = uniqueName + '@example.com.aiassisttest',
                Alias = 'aiat' + Math.mod(i, 10000),
                TimeZoneSidKey = 'GMT',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                ProfileId = standardProfileId,
                AIAssistUserType__c = userType
            ));
        }

        if (shouldDoInsert && !users.isEmpty()) {
            System.runAs(new User(Id = UserInfo.getUserId())) { insert users; }
        }

        return users;
    }

    public static List<AIAgent__c> createAIAgents(Integer numberOfAgents, Boolean shouldDoInsert) {

        List<AIAgent__c> agents = new List<AIAgent__c>();

        for (Integer i = 0; i < numberOfAgents; i++) {
            agents.add(
                new AIAgent__c(
                    Name = 'AI Assist Test Agent ' + DateTime.now().getTime() + i
                )
            );
        }

        if (shouldDoInsert && !agents.isEmpty()) { insert agents; }

        return agents;
    }

    public static List<AIAgent__c> createAIAgents(Integer numberOfAgents, Decimal idleTimeoutMinutes, Boolean shouldDoInsert) {

        List<AIAgent__c> agents = createAIAgents(numberOfAgents, false);

        for (AIAgent__c agent : agents) {
            agent.IdleTimeoutMinutes__c = idleTimeoutMinutes;
        }

        if (shouldDoInsert && !agents.isEmpty()) { insert agents; }

        return agents;
    }

    public static List<AIConversation__c> createAIConversations(Id agentId, Integer numberOfConversations, Boolean shouldDoInsert) {

        List<AIConversation__c> conversations = new List<AIConversation__c>();

        for (Integer i = 0; i < numberOfConversations; i++) {
            conversations.add(new AIConversation__c(
                AIAgent__c = agentId,
                Status__c = 'Active',
                Channel__c = 'Utility Bar'
            ));
        }

        if (shouldDoInsert && !conversations.isEmpty()) { insert conversations; }

        return conversations;
    }

    public static List<AIConversation__c> createAIConversations(Id agentId, Integer numberOfConversations, Date retentionExpiryDate, Boolean shouldDoInsert) {

        List<AIConversation__c> conversations = createAIConversations(agentId, numberOfConversations, false);

        for (AIConversation__c conversation : conversations) {
            conversation.RetentionExpiryDate__c = retentionExpiryDate;
        }

        if (shouldDoInsert && !conversations.isEmpty()) { insert conversations; }

        return conversations;
    }

    public static List<AIConversationMessage__c> createAIConversationMessages(Id conversationId, Decimal tokenCount, Integer numberOfMessages, Boolean shouldDoInsert) {

        List<AIConversationMessage__c> messages = new List<AIConversationMessage__c>();

        for (Integer i = 0; i < numberOfMessages; i++) {
            messages.add(new AIConversationMessage__c(
                AIConversation__c = conversationId,
                Sender__c = 'User',
                MessageBody__c = 'Test message ' + i,
                TokenCount__c = tokenCount
            ));
        }

        if (shouldDoInsert && !messages.isEmpty()) { insert messages; }

        return messages;
    }

    // sourceValue is the Apex Class Name when sourceType is Apex, or the SOQL Template when sourceType is SOQL.
    public static List<Account> createAccounts(Integer numberOfAccounts, Boolean shouldDoInsert) {

        List<Account> accounts = new List<Account>();

        for (Integer i = 0; i < numberOfAccounts; i++) {
            accounts.add(new Account(Name = 'AI Assist Test Account ' + DateTime.now().getTime() + i));
        }

        if (shouldDoInsert && !accounts.isEmpty()) { insert accounts; }

        return accounts;
    }

    public static List<AIDataSource__c> createAIDataSources(Integer numberOfDataSources, String sourceType, String sourceValue, Boolean shouldDoInsert) {

        List<AIDataSource__c> dataSources = new List<AIDataSource__c>();

        for (Integer i = 0; i < numberOfDataSources; i++) {

            AIDataSource__c dataSource = new AIDataSource__c(SourceType__c = sourceType);

            if (sourceType == AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX) {
                dataSource.ApexClassName__c = sourceValue;
            } else if (sourceType == AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL) {
                dataSource.SOQLTemplate__c = sourceValue;
            }

            dataSources.add(dataSource);
        }

        if (shouldDoInsert && !dataSources.isEmpty()) { insert dataSources; }

        return dataSources;
    }

    public static List<AIModelConfiguration__c> createAIModelConfigurations(Integer numberOfConfigurations, Boolean shouldDoInsert) {

        List<AIModelConfiguration__c> configurations = new List<AIModelConfiguration__c>();

        for (Integer i = 0; i < numberOfConfigurations; i++) {
            configurations.add(new AIModelConfiguration__c(
                Name = 'AI Assist Test Model Configuration ' + DateTime.now().getTime() + i
            ));
        }

        if (shouldDoInsert && !configurations.isEmpty()) { insert configurations; }

        return configurations;
    }

    public static List<AIPromptTemplate__c> createAIPromptTemplates(Integer numberOfTemplates, Boolean shouldDoInsert) {

        List<AIPromptTemplate__c> templates = new List<AIPromptTemplate__c>();

        for (Integer i = 0; i < numberOfTemplates; i++) {
            templates.add(new AIPromptTemplate__c(
                Name = 'AI Assist Test Prompt Template ' + DateTime.now().getTime() + i
            ));
        }

        if (shouldDoInsert && !templates.isEmpty()) { insert templates; }

        return templates;
    }

    public static List<AIPIIRegistry__c> createAIPIIRegistries(Integer numberOfRegistries, String objectAPIName, Boolean shouldDoInsert) {

        List<AIPIIRegistry__c> registries = new List<AIPIIRegistry__c>();

        for (Integer i = 0; i < numberOfRegistries; i++) {
            registries.add(new AIPIIRegistry__c(
                Name = 'AI Assist Test PII Registry ' + DateTime.now().getTime() + i,
                ObjectAPIName__c = objectAPIName
            ));
        }

        if (shouldDoInsert && !registries.isEmpty()) { insert registries; }

        return registries;
    }

    public static AIPIIFieldMetadata__c createAIPIIFieldMetadata(Id registryId, String objectAPIName, String fieldAPIName, String fieldLabel, Boolean isPII, String piiFieldType, Boolean shouldDoInsert) {

        AIPIIFieldMetadata__c fieldMetadata = new AIPIIFieldMetadata__c(
            PIIRegistry__c = registryId,
            FieldKey__c = objectAPIName + '.' + fieldAPIName,
            FieldAPIName__c = fieldAPIName,
            FieldLabel__c = fieldLabel,
            IsPII__c = isPII,
            PIIFieldType__c = piiFieldType
        );

        if (shouldDoInsert) { insert fieldMetadata; }

        return fieldMetadata;
    }

    public static AIPIIMapping__c createAIPIIMapping(Id conversationId, Map<String, String> mappingPairs, Boolean shouldDoInsert) {

        AIPIIMapping__c mapping = new AIPIIMapping__c(
            AIConversation__c = conversationId,
            MappingJson__c = JSON.serialize(mappingPairs == null ? new Map<String, String>() : mappingPairs)
        );

        if (shouldDoInsert) { insert mapping; }

        return mapping;
    }

    public static AIUserSettings__c createAIUserSettings(Id userId, Boolean shouldDoInsert) {

        AIUserSettings__c settings = new AIUserSettings__c(User__c = userId);

        if (shouldDoInsert) { insert settings; }

        return settings;
    }

    public static List<AITermsAcknowledgment__c> createAITermsAcknowledgments(Id userId, Date acknowledgedDate, Integer numberOfAcknowledgments, Boolean shouldDoInsert) {

        List<AITermsAcknowledgment__c> acknowledgments = new List<AITermsAcknowledgment__c>();

        for (Integer i = 0; i < numberOfAcknowledgments; i++) {
            acknowledgments.add(new AITermsAcknowledgment__c(
                User__c = userId,
                AcknowledgedDate__c = acknowledgedDate,
                TermsVersion__c = '1.0'
            ));
        }

        if (shouldDoInsert && !acknowledgments.isEmpty()) { insert acknowledgments; }

        return acknowledgments;
    }

    public static List<AIViolationRule__c> createAIViolationRules(Id agentId, Integer numberOfRules, String signalTagPrefix, Boolean shouldDoInsert) {

        List<AIViolationRule__c> rules = new List<AIViolationRule__c>();

        for (Integer i = 0; i < numberOfRules; i++) {
            rules.add(new AIViolationRule__c(
                Agent__c = agentId,
                Name = 'AI Assist Test Violation Rule ' + DateTime.now().getTime() + i,
                SignalTag__c = signalTagPrefix + i
            ));
        }

        if (shouldDoInsert && !rules.isEmpty()) { insert rules; }

        return rules;
    }

    public static List<AIViolation__c> createAIViolations(Id ruleId, Integer numberOfViolations, Boolean shouldDoInsert) {

        List<AIViolation__c> violations = new List<AIViolation__c>();

        for (Integer i = 0; i < numberOfViolations; i++) {
            violations.add(new AIViolation__c(AIViolationRule__c = ruleId));
        }

        if (shouldDoInsert && !violations.isEmpty()) { insert violations; }

        return violations;
    }

    // sourceValue is the Apex Class Name when actionType is Apex, or the Flow API Name when actionType is Flow.
    public static List<AIWorkflowAction__c> createAIWorkflowActions(Integer numberOfActions, String actionType, String sourceValue, Boolean shouldDoInsert) {

        List<AIWorkflowAction__c> actions = new List<AIWorkflowAction__c>();

        for (Integer i = 0; i < numberOfActions; i++) {

            AIWorkflowAction__c action = new AIWorkflowAction__c(ActionType__c = actionType);

            if (actionType == AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX) {
                action.ApexClassName__c = sourceValue;
            } else if (actionType == AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW) {
                action.FlowAPIName__c = sourceValue;
            }

            actions.add(action);
        }

        if (shouldDoInsert && !actions.isEmpty()) { insert actions; }

        return actions;
    }
}