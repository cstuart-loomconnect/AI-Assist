/*
Class Name: AIConversationLockService

=================================================================
=================================================================

Description: Makes sure only one message per conversation is processed at a time. The lock is
the AIConversation__c.ProcessingLockedUntil__c field: while it holds a time in the future, the
conversation is locked. When it's blank or in the past, the conversation is free.

Why: if two AiMessageProcessingQueueable jobs ran on the same conversation at once, each would
build its own history (so replies arrive out of order), both would try to create the
conversation's AIPIIMapping__c, and both would try to update ConversationTokenUsage__c.

How it works:
[1] sendMessage calls lockConversation. If the conversation is free, it's locked and a job is
    enqueued. If it's already locked, the new message is saved but no job is enqueued - it waits.
[2] When a job ends, AiMessageProcessingFinalizer calls releaseLockOrGetNextMessage. If the user
    sent a newer message while the job ran, the lock is kept and that message's Id is returned so
    the finalizer can start it. Otherwise the lock is released.
[3] When a retry is scheduled, the finalizer calls extendLock so new messages keep waiting behind it.

The lock can never get stuck: it's an expiry time, not a checkbox. If a job and its finalizer both
fail without releasing it, it expires after AIAssistSettings__c.ProcessingLockMinutes__c and the
next message the user sends takes it over.

Every method reads the conversation with SELECT ... FOR UPDATE, which holds the record until the
transaction ends. That means lockConversation and releaseLockOrGetNextMessage can't run at the same
time on the same conversation - a message sent just as a job finishes is either seen by the
finalizer or finds the lock already released.

Throws without logging - the caller (sendMessage or the finalizer) logs the failure once.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-27     Chandler Stuart          Initial development
1.1          2026-09-27     Chandler Stuart          extendLock no longer takes a retry delay - retries are enqueued immediately.
*/

public without sharing class AIConversationLockService {

    public class AIConversationLockServiceException extends Exception {}

    // Locks the conversation if it's free. Returns true when the caller now holds the lock and should start processing; false when another message is already being processed.
    public static Boolean lockConversation(Id conversationId) {
        try {

            AIConversation__c conversation = selectConversationForUpdate(conversationId);
            if (conversation == null) throw new AIConversationLockServiceException('AI Conversation not found for Id: ' + conversationId);

            Boolean isAlreadyLocked = conversation.ProcessingLockedUntil__c != null && conversation.ProcessingLockedUntil__c > System.now();
            if (isAlreadyLocked) return false;

            Datetime lockExpiresAt = System.now().addMinutes(AIAssistSettingsService.getProcessingLockMinutes());
            setProcessingLockedUntil(conversationId, lockExpiresAt);
            return true;

        } catch (Exception ex) {
            throw ex instanceof AIConversationLockServiceException ? ex : new AIConversationLockServiceException('Failed to lock the conversation: ' + ex.getMessage(), ex);
        }
    }

    // Keeps the conversation locked for a retry - resets the lock to the usual lock time, so it can't expire before the retry has run.
    public static void extendLock(Id conversationId) {
        try {

            AIConversation__c conversation = selectConversationForUpdate(conversationId);
            if (conversation == null) return; // Conversation was deleted - nothing to lock.

            Datetime lockExpiresAt = System.now().addMinutes(AIAssistSettingsService.getProcessingLockMinutes());
            setProcessingLockedUntil(conversationId, lockExpiresAt);

        } catch (Exception ex) {
            throw ex instanceof AIConversationLockServiceException ? ex : new AIConversationLockServiceException('Failed to extend the conversation lock: ' + ex.getMessage(), ex);
        }
    }

    // Called once a message has finished processing. If the user has sent a newer message since, keeps the lock and returns that message's Id so the caller can process it next. Otherwise releases the lock and returns null.
    public static Id releaseLockOrGetNextMessage(Id conversationId, Id processedMessageId) {
        try {

            AIConversation__c conversation = selectConversationForUpdate(conversationId);
            if (conversation == null) return null; // Conversation was deleted - nothing to release.

            // The newest message the user has sent. If it isn't the one just processed, it arrived while this one was running and is still waiting.
            List<AIConversationMessage__c> newestUserMessages = [ SELECT Id
                                                                  FROM AIConversationMessage__c
                                                                  WHERE AIConversation__c =:conversationId
                                                                  AND Sender__c =:AIAssistApplicationConstants.SENDER_USER
                                                                  ORDER BY CreatedDate DESC, Id DESC
                                                                  LIMIT 1 ];

            Boolean hasWaitingMessage = !newestUserMessages.isEmpty() && newestUserMessages[0].Id != processedMessageId;

            if (hasWaitingMessage) {
                Datetime lockExpiresAt = System.now().addMinutes(AIAssistSettingsService.getProcessingLockMinutes());
                setProcessingLockedUntil(conversationId, lockExpiresAt);
                return newestUserMessages[0].Id;
            }

            setProcessingLockedUntil(conversationId, null); // Blank = unlocked.
            return null;

        } catch (Exception ex) {
            throw ex instanceof AIConversationLockServiceException ? ex : new AIConversationLockServiceException('Failed to release the conversation lock: ' + ex.getMessage(), ex);
        }
    }

    // FOR UPDATE holds this record until the transaction ends, so no other transaction can read and change the lock at the same time.
    // Returns null if the Id is blank, isn't a conversation Id, or the conversation doesn't exist.
    private static AIConversation__c selectConversationForUpdate(Id conversationId) {
        try {

            if (conversationId == null || conversationId.getSobjectType() != AIConversation__c.SObjectType) return null;

            List<AIConversation__c> conversations = [ SELECT Id, ProcessingLockedUntil__c FROM AIConversation__c WHERE Id = :conversationId LIMIT 1 FOR UPDATE ];
            return conversations.isEmpty() ? null : conversations[0];

        } catch (Exception ex) {
            throw new AIConversationLockServiceException('Failed to read the conversation for update: ' + ex.getMessage(), ex);
        }
    }

    // Saves the lock's expiry time. Pass null to unlock the conversation.
    private static void setProcessingLockedUntil(Id conversationId, Datetime lockExpiresAt) {
        try {

            AIConversation__c conversationToUpdate = new AIConversation__c(Id = conversationId, ProcessingLockedUntil__c = lockExpiresAt);

            Database.SaveResult saveResult = Database.update(conversationToUpdate, false);
            if (!saveResult.isSuccess()) throw new AIConversationLockServiceException('Failed to update the conversation lock: ' + saveResult.getErrors()[0].getMessage());

        } catch (Exception ex) {
            throw ex instanceof AIConversationLockServiceException ? ex : new AIConversationLockServiceException('Failed to update the conversation lock: ' + ex.getMessage(), ex);
        }
    }
}