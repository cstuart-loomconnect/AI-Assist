/*
Class Name: AIConversationRetentionBatch

=================================================================
=================================================================

Description: Batchable and Schedulable job that deletes AI Conversations once they've
passed their RetentionExpiryDate__c. Deletion is a soft-delete (Recycle Bin), and since
AIConversationMessage__c is Master-Detail to AIConversation__c, messages cascade-delete
(and cascade-undelete) along with their parent conversation.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-08     Chandler Stuart          Initial development
*/

public without sharing class AIConversationRetentionBatch implements Database.Batchable<SObject>, Schedulable {

    public class AIConversationRetentionBatchException extends Exception {}
    
    @TestVisible private static Boolean isTestCustomExceptionThrown = false;

    public void execute(SchedulableContext context) {
        Database.executeBatch(new AIConversationRetentionBatch());
    }

    // Query Conversations past their retention expiry.
    public Database.QueryLocator start(Database.BatchableContext context) {
        try {
            return Database.getQueryLocator([ SELECT Id FROM AIConversation__c WHERE RetentionExpiryDate__c != NULL AND RetentionExpiryDate__c <= TODAY ]);
        } catch (Exception e){
            AIPlatformLogManager.logException(e, 'AIConversationRetentionBatch', 'execute');
            return null;
        }
    }

    // Deleting expired Conversations.
    public void execute(Database.BatchableContext context, List<AIConversation__c> scope) {
        try {

            if (isTestCustomExceptionThrown) { throw new AIConversationRetentionBatchException('Test exception for AIConversationRetentionBatch.execute'); }

            if (scope == null || scope.isEmpty()) return;

            Database.DeleteResult[] deleteResults = Database.delete(scope, false);
            AIPlatformLogManager.logExceptions(deleteResults, 'AIConversationRetentionBatch', 'execute');
        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIConversationRetentionBatch', 'execute');
        }
    }

    public void finish(Database.BatchableContext context) {
        // No follow-up action needed.
    }
}