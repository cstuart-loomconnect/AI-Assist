/*
Class Name: AIExecutionStepTracker

=================================================================
=================================================================

Description: Everything AIAgentManager learns about one turn as it runs - a data source read or a
provider callout timed by startPhase/endPhase, the iterations/attempt it took, and (only when
captureFullDetail is on) the final callout's request/response JSON and a preview of what was sent.
Handed to AIAgentManager.executeAiMessage by the caller, and read back afterwards to persist as
AIExecutionStep__c rows (AIExecutionStepRecorder) - this class itself never touches the database.

startPhase also publishes the phase live (AIAgentProgressPublisher) when showLiveProgress is on, so
the chat window's "Working on it" card can show real progress instead of a fixed placeholder.

A data source phase is always kept in steps - the chat window's "Sources" chips need it regardless
of debug mode. A provider callout phase is only kept when captureFullDetail is on, since it's only
ever shown in the Debug Trace.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-28     Chandler Stuart          Initial development.
*/

public class AIExecutionStepTracker {

    public class StepEntry {
        public Id dataSourceId; // Null for a provider callout phase.
        public Long durationMilliseconds;
        public Boolean isSuccess = true;
    }

    private final Id conversationId;
    private final Id userMessageId;
    private final Boolean showLiveProgress;

    // Whether the running user has AIUserSettings__c.DebugModeEnabled__c - gates the request/response JSON, sent preview and provider callout steps, which are only ever shown in the Debug Trace.
    public final Boolean captureFullDetail;

    public List<StepEntry> steps = new List<StepEntry>();
    public String sentPreviewText;
    public String lastRequestJson;
    public String lastResponseJson;
    public Integer toolCallingIterationsUsed = 0;
    public Integer toolCallingIterationsMax = 0;
    public Integer attemptNumber = 1;

    private Long phaseStartedAtMillis;
    private Id phaseDataSourceId;

    public AIExecutionStepTracker(Id conversationId, Id userMessageId, Boolean showLiveProgress, Boolean captureFullDetail) {
        this.conversationId = conversationId;
        this.userMessageId = userMessageId;
        this.showLiveProgress = showLiveProgress == true;
        this.captureFullDetail = captureFullDetail == true;
    }

    // Starts timing a phase - a data source read (dataSourceId set) or a provider callout (dataSourceId null).
    public void startPhase(String liveLabel, Id dataSourceId) {
        phaseStartedAtMillis = System.currentTimeMillis();
        phaseDataSourceId = dataSourceId;
        if (showLiveProgress) AIAgentProgressPublisher.publishStep(conversationId, userMessageId, liveLabel);
    }

    // Ends the phase started by startPhase, recording how long it took.
    public void endPhase(Boolean isSuccess) {
        if (phaseStartedAtMillis == null) return;

        Boolean isDataSourcePhase = phaseDataSourceId != null;
        if (isDataSourcePhase || captureFullDetail) {
            StepEntry entry = new StepEntry();
            entry.dataSourceId = phaseDataSourceId;
            entry.durationMilliseconds = System.currentTimeMillis() - phaseStartedAtMillis;
            entry.isSuccess = isSuccess != false;
            steps.add(entry);
        }

        phaseStartedAtMillis = null;
        phaseDataSourceId = null;
    }
}