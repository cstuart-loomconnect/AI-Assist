/*
Class Name: AiMessageProcessingFinalizer

=================================================================
=================================================================

Description: Attached to every AiMessageProcessingQueueable job, and runs after it however the
job ended - successfully, with a caught exception, or killed by an uncatchable LimitException
(CPU, heap, SOQL, callouts). It owns everything that has to happen after a turn, so it happens
exactly once and always:

[1] If the job died on an unhandled error, log it, record the tokens it had spent, and tell the
    chat UI the turn failed - the job never got the chance to. This covers an uncatchable governor
    limit, and a Data Source that wrote to the database (AIAgentManager.AIDataSourceWriteException),
    which the job lets escape on purpose so the write is rolled back.
[2] If the job asked for a retry, enqueue it immediately - no delay. The conversation stays
    locked until the retry has run. AIAgentManager stops asking for retries once the model's
    RetryAttempts__c are used up, and the turn fails.
[3] Otherwise hand the conversation's processing lock on (AIConversationLockService): start the
    user's newest message if one arrived during this turn, or release the lock.

Runs as the same user as the job, so retries and hand-offs keep the original user's sharing and
field access. (The AIMessageCalloutEvent__e platform event this replaced ran retries as the
Automated Process user.)

A finalizer can enqueue at most one job, and this one never enqueues more than one - a retry takes
priority, and the waiting message is picked up by the retry's own finalizer.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-27     Chandler Stuart          Initial development - replaces the AIMessageCalloutEvent__e retry mechanism.
1.1          2026-09-27     Chandler Stuart          Records the tokens spent when the job dies on an unhandled error.
1.2          2026-09-27     Chandler Stuart          Naming pass - shouldRetry/totalTokensUsed/isJobFailed. Retry, failure handling and lock hand-off all folded into execute - no private helpers.
1.3          2026-09-27     Chandler Stuart          Dropped the per-step try/catch around the retry enqueue and lock extension - the outer try/catch covers them.
1.4          2026-09-27     Chandler Stuart          Retries are enqueued immediately with no delay; the model's RetryAttempts__c still caps how many run.
*/

public without sharing class AiMessageProcessingFinalizer implements Finalizer {

    private Id triggeringMessageId;
    private Id conversationId;
    private Integer attemptNumber;

    // Set by AiMessageProcessingQueueable while the job runs.
    @TestVisible private Boolean shouldRetry = false;
    @TestVisible private Decimal totalTokensUsed = 0;

    public AiMessageProcessingFinalizer(Id triggeringMessageId, Id conversationId, Integer attemptNumber) {
        this.triggeringMessageId = triggeringMessageId;
        this.conversationId = conversationId;
        this.attemptNumber = attemptNumber == null ? 1 : attemptNumber;
    }

    // Called by the job with the tokens spent so far, so they can still be recorded if it dies on an unhandled error.
    public void setTokensUsed(Decimal totalTokensUsed) {
        this.totalTokensUsed = totalTokensUsed == null ? 0 : totalTokensUsed;
    }

    // Called by the job when AIAgentManager returned a retryable result. totalTokensUsed covers every attempt so far, so the retry carries it forward.
    public void requestRetry(Decimal totalTokensUsed) {
        this.shouldRetry = true;
        setTokensUsed(totalTokensUsed);
    }

    public void execute(FinalizerContext context) {
        try {

            // context is only null when a test calls execute() directly.
            Boolean isJobFailed = context != null && context.getResult() == ParentJobResult.UNHANDLED_EXCEPTION;

            // [1] The job was killed before it could report anything - usually a governor limit.
            if (isJobFailed) {
                Exception jobException = context.getException();
                AIPlatformLogManager.logException(jobException, 'AiMessageProcessingQueueable', 'execute');

                // Records the tokens the turn spent (with the detailed reason, for the logs/System message) and tells the chat UI it failed - the user only ever sees the generic message.
                AIConversationMessageService.processFailedAIMessageTokens(conversationId, totalTokensUsed, jobException == null ? null : jobException.getMessage());
                AIConversationMessageService.processInvalidAIMessage(conversationId, AIAssistApplicationConstants.MESSAGE_PROCESSING_GENERIC_FAILURE_MESSAGE);
            }

            // [2] Retry requested - only trusted if the job finished normally. Re-runs the same message as a new job straight away, with fresh governor limits,
            // and keeps the conversation locked until the retry has run. Returns so [3] never enqueues a second job - going over a finalizer's one-job limit throws an uncatchable LimitException.
            if (shouldRetry && !isJobFailed) {
                System.enqueueJob(new AiMessageProcessingQueueable(triggeringMessageId, conversationId, attemptNumber + 1, totalTokensUsed));
                AIConversationLockService.extendLock(conversationId);
                return;
            }

            // [3] Turn over - hand the lock to the user's newest waiting message (starting a job for it), or release it if nothing is waiting.
            Id nextMessageId = AIConversationLockService.releaseLockOrGetNextMessage(conversationId, triggeringMessageId);

            if (nextMessageId != null) {
                System.enqueueJob(new AiMessageProcessingQueueable(nextMessageId, conversationId));
            }

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AiMessageProcessingFinalizer', 'execute');
        }
    }
}