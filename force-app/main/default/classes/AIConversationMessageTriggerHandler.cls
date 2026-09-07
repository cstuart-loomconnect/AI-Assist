/*
Class Name: AIConversationMessageTriggerHandler

=================================================================
=================================================================

Description: Handler for managing AI Conversation Message events related to AI Assist,
performing the business logic that runs on the AI Conversation Message trigger.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIConversationMessageTriggerHandler {

    private static Boolean isAfterInsertHandlerRunning = false;

    public static void handleAfterInsert(List<AIConversationMessage__c> newMessages) {
        try {

            if (!isAfterInsertHandlerRunning) {

                isAfterInsertHandlerRunning = true;

                List<AIConversationMessage__c> messagesWithTokenUsage = new List<AIConversationMessage__c>();

                for (AIConversationMessage__c message : newMessages) {
                    if (message.AIConversation__c == null || message.TokenCount__c == null) continue;
                    messagesWithTokenUsage.add(message);
                }

                if (!messagesWithTokenUsage.isEmpty()) { updateConversationTokenUsage(messagesWithTokenUsage); }

            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIConversationMessageTriggerHandler', 'handleAfterInsert');
        }
    }

    // Adds each message's TokenCount__c onto its parent Conversation's ConversationTokenUsage__c running total. MessageCount__c is a native Roll-Up Summary and needs no trigger.
    private static void updateConversationTokenUsage(List<AIConversationMessage__c> messages) {
        try {

            Map<Id, Decimal> tokensAddedByConversationId = new Map<Id, Decimal>();

            for (AIConversationMessage__c message : messages) {

                Decimal tokensAdded = tokensAddedByConversationId.get(message.AIConversation__c);
                tokensAddedByConversationId.put(message.AIConversation__c, (tokensAdded == null ? 0 : tokensAdded) + message.TokenCount__c);

            }

            if (tokensAddedByConversationId.isEmpty()) return;

            List<AIConversation__c> conversationsToUpdate = new List<AIConversation__c>();

            for (AIConversation__c conversation : [SELECT Id, ConversationTokenUsage__c FROM AIConversation__c WHERE Id IN :tokensAddedByConversationId.keySet()]) {
                conversation.ConversationTokenUsage__c = (conversation.ConversationTokenUsage__c == null ? 0 : conversation.ConversationTokenUsage__c) + tokensAddedByConversationId.get(conversation.Id);
                conversationsToUpdate.add(conversation);
            }

            if (!conversationsToUpdate.isEmpty()) {
                Database.SaveResult[] updateResults = Database.update(conversationsToUpdate, false);
                AIPlatformLogManager.logExceptions(updateResults, 'AIConversationMessageTriggerHandler', 'updateConversationTokenUsage');
            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIConversationMessageTriggerHandler', 'updateConversationTokenUsage');
        }
    }
}