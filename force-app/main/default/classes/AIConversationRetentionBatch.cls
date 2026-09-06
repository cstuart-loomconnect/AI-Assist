/*
Class Name: AIConversationRetentionBatch

=================================================================
=================================================================

Description: Batchable and Schedulable job that applies each Agent's RetentionAction__c
(Archive or Anonymize) to AI Conversations that have passed their RetentionExpiryDate__c.
Archive marks the conversation archived as-is. Anonymize additionally redacts message
content and clears record-level identifiers before marking it archived.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIConversationRetentionBatch implements Database.Batchable<SObject>, Schedulable {

    private static final String REDACTED_MESSAGE_BODY = '[Redacted - Anonymized per retention policy]';

    public void execute(SchedulableContext context) {
        Database.executeBatch(new AIConversationRetentionBatch());
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            SELECT Id, AIAgent__c
            FROM AIConversation__c
            WHERE RetentionExpiryDate__c != null
            AND RetentionExpiryDate__c <= TODAY
            AND IsArchived__c = false
        ]);
    }

    public void execute(Database.BatchableContext context, List<AIConversation__c> scope) {
        try {

            Set<Id> agentIds = new Set<Id>();
            for (AIConversation__c conversation : scope) {
                if (conversation.AIAgent__c != null) { agentIds.add(conversation.AIAgent__c); }
            }

            Map<Id, AIAgent__c> agentsById = new Map<Id, AIAgent__c>([SELECT Id, RetentionAction__c FROM AIAgent__c WHERE Id IN :agentIds]);

            List<AIConversation__c> conversationsToArchive = new List<AIConversation__c>();
            Set<Id> conversationIdsToAnonymize = new Set<Id>();

            for (AIConversation__c conversation : scope) {

                AIAgent__c agent = conversation.AIAgent__c == null ? null : agentsById.get(conversation.AIAgent__c);
                String retentionAction = agent == null ? AIAssistApplicationConstants.RETENTION_ACTION_ARCHIVE : agent.RetentionAction__c; // Default to Archive when the Agent has no explicit setting.

                Boolean isAnonymize = retentionAction == AIAssistApplicationConstants.RETENTION_ACTION_ANONYMIZE;
                if (isAnonymize) { conversationIdsToAnonymize.add(conversation.Id); }

                AIConversation__c conversationUpdate = new AIConversation__c(
                    Id = conversation.Id,
                    Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_ARCHIVED,
                    IsArchived__c = true
                );

                if (isAnonymize) {
                    conversationUpdate.ExternalReference__c = null;
                    conversationUpdate.RelatedRecordId__c = null;
                }

                conversationsToArchive.add(conversationUpdate);

            }

            if (!conversationIdsToAnonymize.isEmpty()) { anonymizeMessages(conversationIdsToAnonymize); }

            if (!conversationsToArchive.isEmpty()) {
                Database.SaveResult[] updateResults = Database.update(conversationsToArchive, false);
                AIPlatformLogManager.logExceptions(updateResults, 'AIConversationRetentionBatch', 'execute');
            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIConversationRetentionBatch', 'execute');
        }
    }

    // Redacts message content on every message under the given conversations.
    private static void anonymizeMessages(Set<Id> conversationIds) {
        try {

            List<AIConversationMessage__c> messagesToRedact = new List<AIConversationMessage__c>();

            for (AIConversationMessage__c message : [SELECT Id FROM AIConversationMessage__c WHERE AIConversation__c IN :conversationIds]) {
                messagesToRedact.add(new AIConversationMessage__c(Id = message.Id, MessageBody__c = REDACTED_MESSAGE_BODY));
            }

            if (!messagesToRedact.isEmpty()) {
                Database.SaveResult[] updateResults = Database.update(messagesToRedact, false);
                AIPlatformLogManager.logExceptions(updateResults, 'AIConversationRetentionBatch', 'anonymizeMessages');
            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIConversationRetentionBatch', 'anonymizeMessages');
        }
    }

    public void finish(Database.BatchableContext context) {
        // No follow-up action needed.
    }
}