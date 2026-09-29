/*
Class Name: AIAgentProgressPublisher

=================================================================
=================================================================

Description: Publishes one AIAgentProgressEvent__e so the chat LWC's "Working on it" card can
show live progress while AIAgentManager is still mid-turn. The event's PublishBehavior is
PublishImmediately, not PublishAfterCommit - AiMessageProcessingQueueable's transaction is still
running, callouts in flight, when these need to arrive, so there is no commit to wait for.

Best-effort only: a dropped or delayed event never affects the turn itself, only what the working
indicator shows meanwhile, so every failure is swallowed and logged rather than thrown.

Publish Immediately events share one 150-per-transaction budget (Limits.getLimitPublishImmediateDML())
with AIPlatformLogManager's own logging - a busy turn (many tool-calling iterations, each able to log
its own failures) could let these cosmetic events crowd out a real error being logged, or hit the
limit outright. AIGovernorLimits.isSafeToPublishProgress() is checked first, so this class is always
the one that gives up that budget, never AIPlatformLogManager.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-28     Chandler Stuart          Initial development.
1.1          2026-09-28     Chandler Stuart          Checks AIGovernorLimits.isSafeToPublishProgress() first - Publish Immediately headroom is shared with AIPlatformLogManager's logging, which must always win it.
*/

public without sharing class AIAgentProgressPublisher {

    public static void publishStep(Id conversationId, Id userMessageId, String stepLabel) {
        try {

            if (conversationId == null || userMessageId == null || String.isBlank(stepLabel)) return;
            if (!AIGovernorLimits.isSafeToPublishProgress()) return;

            EventBus.publish(new AIAgentProgressEvent__e(
                AIConversationId__c = String.valueOf(conversationId),
                UserMessageId__c = String.valueOf(userMessageId),
                StepLabel__c = stepLabel.abbreviate(255)
            ));

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIAgentProgressPublisher', 'publishStep');
        }
    }
}