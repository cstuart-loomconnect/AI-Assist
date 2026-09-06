/*
Class Name: AIConversationIdleTimeoutBatch

=================================================================
=================================================================

Description: Batchable and Schedulable job that closes AI Conversations that have sat idle
longer than their Agent's IdleTimeoutMinutes__c. Idle time is measured from the most recent
AIConversationMessage__c on the conversation, or its own CreatedDate if it has no messages yet.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIConversationIdleTimeoutBatch implements Database.Batchable<SObject>, Schedulable {

    public void execute(SchedulableContext context) {
        Database.executeBatch(new AIConversationIdleTimeoutBatch());
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            SELECT Id, AIAgent__c, CreatedDate
            FROM AIConversation__c
            WHERE Status__c = :AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE
            AND AIAgent__c != null
        ]);
    }

    public void execute(Database.BatchableContext context, List<AIConversation__c> scope) {
        try {

            Set<Id> agentIds = new Set<Id>();
            for (AIConversation__c conversation : scope) { agentIds.add(conversation.AIAgent__c); }

            Map<Id, AIAgent__c> agentsById = new Map<Id, AIAgent__c>([SELECT Id, IdleTimeoutMinutes__c FROM AIAgent__c WHERE Id IN :agentIds]);

            Map<Id, Datetime> lastMessageDateByConversationId = new Map<Id, Datetime>();

            for (AggregateResult result : [SELECT AIConversation__c convId, MAX(CreatedDate) lastMessageDate FROM AIConversationMessage__c WHERE AIConversation__c IN :scope GROUP BY AIConversation__c]) {
                lastMessageDateByConversationId.put((Id) result.get('convId'), (Datetime) result.get('lastMessageDate'));
            }

            List<AIConversation__c> conversationsToClose = new List<AIConversation__c>();

            for (AIConversation__c conversation : scope) {

                AIAgent__c agent = agentsById.get(conversation.AIAgent__c);
                if (agent == null || agent.IdleTimeoutMinutes__c == null) continue; // Blank means no idle timeout is enforced.

                Datetime lastActivity = lastMessageDateByConversationId.get(conversation.Id);
                if (lastActivity == null) { lastActivity = conversation.CreatedDate; }

                Long idleMinutes = (Datetime.now().getTime() - lastActivity.getTime()) / (1000 * 60);
                if (idleMinutes < Integer.valueOf(agent.IdleTimeoutMinutes__c)) continue; // Still within the allowed idle window.

                conversationsToClose.add(new AIConversation__c(
                    Id = conversation.Id,
                    Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED,
                    ConversationCloseReason__c = AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_IDLE_TIMEOUT
                ));

            }

            if (!conversationsToClose.isEmpty()) {
                Database.SaveResult[] updateResults = Database.update(conversationsToClose, false);
                AIPlatformLogManager.logExceptions(updateResults, 'AIConversationIdleTimeoutBatch', 'execute');
            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIConversationIdleTimeoutBatch', 'execute');
        }
    }

    public void finish(Database.BatchableContext context) {
        // No follow-up action needed.
    }
}