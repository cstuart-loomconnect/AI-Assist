/*
Class Name: AIGovernorLimits

=================================================================
=================================================================

Description: One place for the Salesforce governor limits AI Assist has to work within, and the
checks against them. Many of these limits (CPU, heap, SOQL, callouts) throw a LimitException when
exceeded, which no try/catch can handle - so the only safe option is to check what's left BEFORE
doing the work, and stop gracefully when it runs low.

Used by AIAgentManager's tool-calling loop to:
- Trim each AI provider callout to what's left of the 120s per-transaction callout budget.
- Stop running tool calls before SOQL, callouts, CPU or heap run out.
- Detect a Data Source that wrote to the database, since uncommitted DML blocks every later
  callout in the same transaction.

Every method catches and logs its own exceptions, then returns the conservative answer - the one
that stops the work rather than letting it run on into a limit.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-27     Chandler Stuart          Initial development
1.1          2026-09-27     Chandler Stuart          Removed getRetryDelayMinutes - retries are now enqueued immediately, with no delay.
*/

public without sharing class AIGovernorLimits {

    // A point-in-time count of the statements that can block callouts. Take one before running code you don't control (e.g. an Apex Data Source), then call isUncommittedDmlSince() afterwards.
    public class DmlSnapshot {
        private Integer dmlStatementCount;
        private Integer publishImmediateStatementCount;
    }

    // Returns null if the counts can't be read - isUncommittedDmlSince() treats a null snapshot as "no DML".
    public static DmlSnapshot takeDmlSnapshot() {

        try {
            DmlSnapshot dmlSnapshot = new DmlSnapshot();
            dmlSnapshot.dmlStatementCount = Limits.getDmlStatements();
            dmlSnapshot.publishImmediateStatementCount = Limits.getPublishImmediateDML();
            return dmlSnapshot;

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIGovernorLimits', 'takeDmlSnapshot');
            return null;
        }
    }

    // True when DML (or an after-commit event publish) ran since the snapshot. Publish-immediately events - which is how AIPlatformLogManager logs - don't block callouts, so they're discounted in case the platform counts them as DML statements.
    public static Boolean isUncommittedDmlSince(DmlSnapshot dmlSnapshot) {

        try {
            if (dmlSnapshot == null) return false;

            Integer dmlStatementCountSince = Limits.getDmlStatements() - dmlSnapshot.dmlStatementCount;
            Integer publishImmediateStatementCountSince = Limits.getPublishImmediateDML() - dmlSnapshot.publishImmediateStatementCount;
            Boolean isUncommittedDml = dmlStatementCountSince > publishImmediateStatementCountSince;

            return isUncommittedDml;

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIGovernorLimits', 'isUncommittedDmlSince');
            return true; // Assume a write happened - failing the turn is safer than a later callout failing on uncommitted work.
        }
    }

    // True when a callout failed because of uncommitted DML earlier in the transaction - retrying won't help, since the same code will write again.
    public static Boolean isUncommittedWorkException(Exception calloutEx) {

        try {
            Boolean isCalloutException = calloutEx instanceof CalloutException;
            String errorMessage = (calloutEx == null) ? null : calloutEx.getMessage();
            Boolean isUncommittedWorkMessage = String.isNotBlank(errorMessage) && errorMessage.containsIgnoreCase(AIAssistApplicationConstants.UNCOMMITTED_WORK_ERROR_TEXT);

            return isCalloutException && isUncommittedWorkMessage;

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIGovernorLimits', 'isUncommittedWorkException');
            return false;
        }
    }

    // How much of the 120s callout budget is left, measured by wall-clock time since calloutBudgetStartMilliseconds. Wall-clock is deliberately conservative - it also covers any callouts an Apex Data Source makes along the way.
    public static Integer getRemainingCalloutMilliseconds(Long calloutBudgetStartMilliseconds) {

        try {
            Integer elapsedMilliseconds = (System.currentTimeMillis() - calloutBudgetStartMilliseconds).intValue();
            Integer remainingCalloutMilliseconds = AIAssistApplicationConstants.MAX_TRANSACTION_CALLOUT_MILLISECONDS - elapsedMilliseconds;

            return remainingCalloutMilliseconds;

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIGovernorLimits', 'getRemainingCalloutMilliseconds');
            return 0; // No budget - the caller stops rather than risk the platform's callout limit.
        }
    }

    // True when enough Publish Immediately headroom (Limits.getLimitPublishImmediateDML()) is left to publish one more AIAgentProgressEvent__e. That budget is shared with AIPlatformLogManager's own logging, which must always get through - a busy turn (many tool-calling iterations, each logging its own failures) could otherwise let cosmetic live-progress events crowd out a real error being logged, or hit the platform's limit outright. Reserved via AIAssistApplicationConstants.PROGRESS_EVENT_RESERVED_PUBLISH_IMMEDIATE.
    public static Boolean isSafeToPublishProgress() {

        try {
            Integer remainingPublishImmediate = Limits.getLimitPublishImmediateDML() - Limits.getPublishImmediateDML();
            return remainingPublishImmediate > AIAssistApplicationConstants.PROGRESS_EVENT_RESERVED_PUBLISH_IMMEDIATE;

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIGovernorLimits', 'isSafeToPublishProgress');
            return false; // Skip the live update rather than risk crowding out logging.
        }
    }

    // True when enough of each limit is left to run one more tool call and still finish the turn safely.
    public static Boolean isSafeToRunToolCall() {

        try {
            Integer remainingSoqlQueries = Limits.getLimitQueries() - Limits.getQueries();
            Integer remainingCallouts = Limits.getLimitCallouts() - Limits.getCallouts();
            Integer remainingCpuMilliseconds = Limits.getLimitCpuTime() - Limits.getCpuTime();
            Integer remainingHeapBytes = Limits.getLimitHeapSize() - Limits.getHeapSize();

            Boolean isEnoughSoqlRemaining = remainingSoqlQueries > AIAssistApplicationConstants.TOOL_CALL_RESERVED_SOQL_QUERIES;
            Boolean isEnoughCalloutsRemaining = remainingCallouts > AIAssistApplicationConstants.TOOL_CALL_RESERVED_CALLOUTS;
            Boolean isEnoughCpuRemaining = remainingCpuMilliseconds > AIAssistApplicationConstants.TOOL_CALL_RESERVED_CPU_MILLISECONDS;
            Boolean isEnoughHeapRemaining = remainingHeapBytes > AIAssistApplicationConstants.TOOL_CALL_RESERVED_HEAP_BYTES;

            return isEnoughSoqlRemaining && isEnoughCalloutsRemaining && isEnoughCpuRemaining && isEnoughHeapRemaining;

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIGovernorLimits', 'isSafeToRunToolCall');
            return false; // Skip the tool rather than risk an uncatchable LimitException.
        }
    }
}