/*
Class Name: AIConversationTriggerHandler

=================================================================
=================================================================

Description: Handler for managing AI Conversation events related to AI Assist,
performing the business logic that runs on the AI Conversation trigger.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIConversationTriggerHandler {

    private static Boolean isBeforeInsertHandlerRunning = false;
    private static Boolean isBeforeUpdateHandlerRunning = false;

    public static void handleBeforeInsert(List<AIConversation__c> newConversations) {
        try {

            if (!isBeforeInsertHandlerRunning) {

                isBeforeInsertHandlerRunning = true;

                AIAssistGlobalUtility.generatePublicId(newConversations);
                calculateRetentionExpiryDate(newConversations);

            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIConversationTriggerHandler', 'handleBeforeInsert');
        }
    }

    public static void handleBeforeUpdate(Map<Id, AIConversation__c> oldConversationsById, Map<Id, AIConversation__c> newConversationsById) {
        try {

            if (!isBeforeUpdateHandlerRunning) {

                isBeforeUpdateHandlerRunning = true;

                if (newConversationsById == null || newConversationsById.isEmpty() || oldConversationsById == null) return;

                List<AIConversation__c> conversationsNewlyClosed = new List<AIConversation__c>(); // Conversations whose Status__c just changed to Closed and need Retention Expiry Date calculated from the close.

                for (AIConversation__c newConversation : newConversationsById.values()) {

                    AIConversation__c oldConversation = oldConversationsById.get(newConversation.Id);
                    if (oldConversation == null) continue;

                    Boolean wasAlreadyClosed = oldConversation.Status__c == AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED;
                    Boolean isNowClosed = newConversation.Status__c == AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED;

                    if (wasAlreadyClosed || !isNowClosed) continue; // Only act the moment a conversation newly closes.

                    if (newConversation.ConversationClosedTimestamp__c == null) { newConversation.ConversationClosedTimestamp__c = Datetime.now(); }

                    conversationsNewlyClosed.add(newConversation);

                }

                if (!conversationsNewlyClosed.isEmpty()) { calculateRetentionExpiryDate(conversationsNewlyClosed); }

            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIConversationTriggerHandler', 'handleBeforeUpdate');
        }
    }

    // Sets RetentionExpiryDate__c from the related Agent's Conversation Retention Days. Resolves which basis applies per record: a not-yet-inserted conversation (no Id yet) uses Conversation Created Date; one with ConversationClosedTimestamp__c set (passed in only once it's just closed) uses Conversation Closed Date. The remaining Retention Trigger value, Last Message Date, has no event to calculate from here yet.
    private static void calculateRetentionExpiryDate(List<AIConversation__c> conversations) {
        try {

            Set<Id> agentIds = new Set<Id>();

            for (AIConversation__c conversation : conversations) {
                if (conversation.AIAgent__c != null) { agentIds.add(conversation.AIAgent__c); }
            }

            if (agentIds.isEmpty()) return;

            Map<Id, AIAgent__c> agentsById = new Map<Id, AIAgent__c>([SELECT Id, ConversationRetentionDays__c, RetentionTrigger__c FROM AIAgent__c WHERE Id IN :agentIds]);

            for (AIConversation__c conversation : conversations) {

                AIAgent__c agent = conversation.AIAgent__c == null ? null : agentsById.get(conversation.AIAgent__c);
                if (agent == null) continue;
                if (agent.ConversationRetentionDays__c == null) continue; // Blank means retain indefinitely.

                Integer retentionDays = Integer.valueOf(agent.ConversationRetentionDays__c);

                if (agent.RetentionTrigger__c == AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE && conversation.Id == null) {
                    conversation.RetentionExpiryDate__c = Date.today().addDays(retentionDays);
                    conversation.RetentionCalculationBasis__c = AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE;
                } else if (agent.RetentionTrigger__c == AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CLOSED_DATE && conversation.ConversationClosedTimestamp__c != null) {
                    conversation.RetentionExpiryDate__c = conversation.ConversationClosedTimestamp__c.date().addDays(retentionDays);
                    conversation.RetentionCalculationBasis__c = AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CLOSED_DATE;
                }

            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIConversationTriggerHandler', 'calculateRetentionExpiryDate');
        }
    }
}