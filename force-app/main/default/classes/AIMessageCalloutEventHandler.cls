/*
Class Name: AIMessageCalloutEventHandler

=================================================================
=================================================================

Description: Handles AIMessageCalloutEvent__e after insert. Enqueues one AiMessageProcessingQueueable
per event - the same Queueable a first attempt uses - so a retried attempt gets its own fresh
governor limits and reloads the whole turn from AIConversationMessageId__c rather than resuming
any in-memory state.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-26     Chandler Stuart          Initial development
*/

public without sharing class AIMessageCalloutEventHandler {

    public static void handleAfterInsert(List<AIMessageCalloutEvent__e> events) {
        try {

            if (events == null || events.isEmpty()) return;

            for (AIMessageCalloutEvent__e event : events) {
                System.enqueueJob(new AiMessageProcessingQueueable((Id) event.AIConversationMessageId__c, event.AttemptNumber__c.intValue()));
            }

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIMessageCalloutEventHandler', 'handleAfterInsert');
        }
    }
}