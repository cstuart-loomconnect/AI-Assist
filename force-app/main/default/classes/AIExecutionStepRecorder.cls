/*
Class Name: AIExecutionStepRecorder

=================================================================
=================================================================

Description: Turns one AIExecutionStepTracker into the AIExecutionStep__c rows for a reply that's just
been saved - a data source step per tool call, and (only when AIExecutionStepTracker.captureFullDetail is
on) a provider callout step per callout, carrying the iterations/attempt it took. The request JSON,
response JSON and sent preview only ever go on the last callout step, since AIExecutionStepTracker only
ever holds the most recent callout's - putting it on every callout step would mislabel the earlier
ones with the final callout's detail.

Called by AIConversationMessageService.processValidAIMessage once the reply message exists - a
MasterDetail child needs a real parent Id, so this can't run any earlier. Never called for a failed
turn: there's no reply message to attach the steps to.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-28     Chandler Stuart          Initial development.
*/

public without sharing class AIExecutionStepRecorder {

    public static void record(Id replyMessageId, AIExecutionStepTracker trace) {
        try {

            if (replyMessageId == null || trace == null || trace.steps.isEmpty()) return;

            Integer lastCalloutIndex = -1;
            for (Integer stepIndex = 0; stepIndex < trace.steps.size(); stepIndex++) {
                if (trace.steps[stepIndex].dataSourceId == null) lastCalloutIndex = stepIndex;
            }

            List<AIExecutionStep__c> stepsToInsert = new List<AIExecutionStep__c>();

            for (Integer stepIndex = 0; stepIndex < trace.steps.size(); stepIndex++) {

                AIExecutionStepTracker.StepEntry entry = trace.steps[stepIndex];

                AIExecutionStep__c step = new AIExecutionStep__c(
                    AIConversationMessage__c = replyMessageId,
                    AIDataSource__c = entry.dataSourceId,
                    StepOrder__c = stepIndex + 1,
                    Status__c = entry.isSuccess ? AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS : AIAssistApplicationConstants.EXECUTION_STEP_STATUS_FAILED,
                    DurationMilliseconds__c = entry.durationMilliseconds,
                    ToolCallingIterationsUsed__c = trace.toolCallingIterationsUsed,
                    ToolCallingIterationsMax__c = trace.toolCallingIterationsMax,
                    AttemptNumber__c = trace.attemptNumber
                );

                if (trace.captureFullDetail && stepIndex == lastCalloutIndex) {
                    step.RequestJson__c = trace.lastRequestJson;
                    step.ResponseJson__c = trace.lastResponseJson;
                    step.SentPreviewText__c = trace.sentPreviewText;
                }

                stepsToInsert.add(step);
            }

            List<Database.SaveResult> saveResults = Database.insert(stepsToInsert, false);
            AIPlatformLogManager.logExceptions(saveResults, 'AIExecutionStepRecorder', 'record');

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIExecutionStepRecorder', 'record');
        }
    }
}
