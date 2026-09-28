/*
Class Name: AIAgentManager

=================================================================
=================================================================

Description: Owns the actual conversation with the AI provider. Solely makes the callout(s) and
returns an AgentResult describing what happened - it never inserts, updates, or publishes
anything itself. The caller (AiMessageProcessingQueueable, via AIConversationMessageService)
evaluates that result and performs whatever update follows from it.

Flow (matches the numbered comments in executeAiMessage):
[1] Get the provider-specific request builder and response handler for
    AIModelConfiguration__c.AIProvider__c from AIProvider - the only classes that know a provider's
    JSON shape; everything else here stays provider-agnostic.
[2] Index the available Data Sources by tool name (DeveloperName__c).
[3] Build the tool definitions advertised to the model.
[4] Build the message history the model sees.
[5] Build the system prompt - the Prompt Template plus the Workflow Actions the model may suggest.
[6] Resolve the run limits - tool-calling iterations, tool calls per iteration, retry attempts,
    callout timeout.
[7] Tool-calling loop - send the request; either return the final reply, or run the requested
    tools (invokeTool) and send their results back on the next iteration. A failed or
    retryable-status callout, with attempts remaining, comes back as AgentResult.isRetryable =
    true - this class never schedules a retry itself (AiMessageProcessingFinalizer does).

Governor limits (AIGovernorLimits) - checked before each piece of work rather than after, since a
LimitException can't be caught:
- Each callout's timeout is trimmed to what's left of the 120s per-transaction callout budget.
- Tool calls stop once SOQL, callouts, CPU or heap run low, and at most
  AIAssistSettings__c.MaxToolCallsPerIteration__c run per model reply. Skipped calls still get a
  result explaining why, since providers reject a reply that leaves a tool call unanswered.
- A Data Source that writes to the database throws AIDataSourceWriteException, which is never
  caught here or in AiMessageProcessingQueueable. Letting it escape the job rolls the whole
  transaction back, so the Data Source's write is undone; AiMessageProcessingFinalizer then logs it,
  records the tokens and tells the chat UI.
- On the last allowed iteration, the model is sent the request with tool calls disabled, so it
  has to answer with what it already has instead of the turn failing.

Workflow Actions are never tool-called or executed here - they are described in the system prompt
as suggestions only. A final reply is scanned for a trailing structured suggestion
(applyWorkflowActionSuggestion), resolved to a real AIWorkflowAction__c Id, and returned on
AgentResult so the caller can store it for the chat UI to offer as a user-initiated button.

Exception logging - each failure is logged exactly once, by the method that catches it:
- executeAiMessage logs anything that stops the turn (bad configuration, provider error, etc.).
- invokeTool logs a failed tool call (AiDataSourceDispatcher rethrows without logging).
- applyWorkflowActionSuggestion logs a malformed suggestion.
- A failed callout is logged in the loop, since it is turned into a result rather than rethrown.
- AIDataSourceWriteException is never logged here - it's logged once by AiMessageProcessingFinalizer
  after the rollback (a log published here would be a duplicate).

What gets sent where:
- Tool failures reach the model only as a generic message - the real error (which can contain SOQL,
  record Ids or field values) stays in the log, since the model is a third party.
- AgentResult.errorMessage keeps the detailed error for logs and the failed-turn System message;
  AIConversationMessageService shows the user a generic message instead.

PII write deferral - executeAiMessage turns AIPiiMappingService.isDeferringWrites on for the loop
and back off when it returns. The mappings are still only held in memory: the caller MUST call
AIPiiMappingService.processCachedPIIMappings() once executeAiMessage returns, or they're lost.
The provider request builders/response handlers rethrow without logging, so executeAiMessage logs them.

PII masking isn't this class's concern - it already happened upstream in
AiDataSourceResultProcessor before a tool result ever reaches here. Rich text/markdown/emoji in
the model's reply is passed through as-is (never escaped, filtered, or truncated) - rendering it
is a front-end concern.

The canonical request/response types (Request, ToolDefinition, Response, ToolCall) live on
AIProvider, since the provider classes and their interfaces use them too.

Turn trace - executeAiMessage now also takes an AIExecutionStepTracker, timed around each data source
read and provider callout (trace.startPhase/endPhase). It's mutated in place, not returned on
AgentResult: the caller already holds the same reference, and reads it back afterwards to persist
as AIExecutionStep__c rows (AIExecutionStepRecorder) and, while showLiveProgress is on, to let the
chat window's "Working on it" card show real progress instead of a fixed placeholder.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-21     Chandler Stuart          Initial development
1.1          2026-09-22     Chandler Stuart          Provider-agnostic request/response mapping via Custom Metadata; callout retries moved to AIProviderCalloutRetryEvent__e for fresh governor limits.
1.2          2026-09-26     Chandler Stuart          Replaced Custom Metadata-driven mapping with one IAIProviderResponseHandler per provider. This class now solely makes callouts and returns AgentResult; callers own every update. Workflow Actions removed from tool-calling - suggested only, user-initiated to run.
1.3          2026-09-26     Chandler Stuart          Renamed from AiAgentOrchestrator; folded the standalone AIMessageDataStructure/AIMessageResponseDataStructure classes in as nested Request/Response.
1.4          2026-09-27     Chandler Stuart          Retryable status codes and the callout timeout moved to AIAssistSettings__c (RetryableStatusCodes__c, CalloutTimeoutMilliseconds__c) via AIAssistSettingsService - AIModelConfiguration__c.SystemTimeoutSeconds__c removed.
1.5          2026-09-27     Chandler Stuart          Defers PII mapping DML until after the callouts. Trims each callout's timeout to the 120s transaction budget. Retry results carry the tokens already spent.
1.6          2026-09-27     Chandler Stuart          Readability pass - clearer variable names, whole-method try/catch on every helper, each exception logged exactly once. Tool-calling limits moved to AIAssistSettings__c.
1.7          2026-09-27     Chandler Stuart          Governor limit checks via AIGovernorLimits (headroom before each tool call, DML detection, callout budget). Tool calls capped per iteration. Tokens kept on every failure result. Removed the unused triggeringMessage parameter. PII write deferral moved from the static block into executeAiMessage.
1.8          2026-09-27     Chandler Stuart          Blank messages skipped from history. Last iteration sent with tools disabled. Generic tool errors to the model. Tool description falls back to its name. Data Source writes rolled back via AIDataSourceWriteException. Running out of callout time is no longer retried. PII deferral switched off in a finally block.
1.9          2026-09-27     Chandler Stuart          Request/ToolDefinition/Response/ToolCall and stringifyToolResult moved to AIProvider, which now also picks the provider's request builder and response handler.
1.10         2026-09-28     Chandler Stuart          executeAiMessage takes an AIExecutionStepTracker, timed around each data source read and provider callout - live progress (AIAgentProgressPublisher) and the Debug Trace's per-step timing, iterations/attempt and request/response JSON (AIExecutionStepRecorder) all come from it.
*/

public without sharing class AIAgentManager {

    private static final Integer DEFAULT_MAX_OUTPUT_TOKENS = 1024;

    // Class initialisation - runs once per transaction, the first time AIAgentManager is referenced. Only non-throwing, side-effect-free work belongs here; the callout timeout is still validated inside executeAiMessage so a missing setting is caught and logged there.
    static {
        // Warms AIAssistSettingsService's per-transaction cache - every later call in this transaction reads the cached settings/status codes/tool-calling limits instead of re-resolving them.
        AIAssistSettingsService.getSettings();
        AIAssistSettingsService.getRetryStatusCodes();
        AIAssistSettingsService.getDefaultMaxToolCallingIterations();
        AIAssistSettingsService.getMaxToolCallingIterationsCap();
        AIAssistSettingsService.getMaxToolCallsPerIteration();
    }

    public class AIAgentManagerException extends Exception {}

    // Thrown when a Data Source wrote to the database. Deliberately never caught by this class or AiMessageProcessingQueueable: escaping the job rolls the whole transaction back (undoing the write), and AiMessageProcessingFinalizer then logs it, records tokensUsed and tells the chat UI.
    public class AIDataSourceWriteException extends Exception {
        public Decimal tokensUsed = 0;
    }

    // Always returned, never null - isSuccessful/isRetryable tell the caller which update to perform; this class never performs one itself.
    public class AgentResult {
        public Boolean isSuccessful = false;
        public String replyText;
        public Decimal totalTokensUsed = 0;
        public Boolean isRetryable = false;
        public String errorMessage;
        public String suggestedWorkflowActionId;
    }

    // Runs one full turn - callout(s), tool-calling loop, final text response - starting at attemptNumber (1 for the very first attempt; the caller increments this on every subsequent retry). Every argument is fully loaded by the caller; this class issues no SOQL of its own.
    // messageHistory must already end with the message being answered - the caller loads it up to and including that message.
    // trace is mutated in place as the turn runs (AIExecutionStepTracker.startPhase/endPhase around each data source read and provider callout) - the caller already holds the same reference, so nothing about it needs to come back on AgentResult.
    public static AgentResult executeAiMessage(AIAgent__c agent, AIModelConfiguration__c modelConfiguration, AIPromptTemplate__c promptTemplate, AIConversation__c conversation, List<AIConversationMessage__c> messageHistory, List<AIDataSource__c> availableDataSources, List<AIWorkflowAction__c> availableWorkflowActions, Integer attemptNumber, AIExecutionStepTracker trace) {

        // Declared outside the try so every failure result below - not just the successful one - reports the tokens already spent.
        Decimal totalTokensUsed = 0;

        try {

            // PII masked by tool calls must not write to the database mid-loop - uncommitted DML blocks every later callout in this transaction. The caller saves them once the callouts are done (AIPiiMappingService.processCachedPIIMappings).
            AIPiiMappingService.isDeferringWrites = true;

            // A trace that never publishes live and never captures full detail - so every call below can unconditionally use trace.startPhase/endPhase, with no separate null handling.
            if (trace == null) trace = new AIExecutionStepTracker(conversation != null ? conversation.Id : null, null, false, false);

            if (agent == null) throw new AIAgentManagerException('No AI Agent provided.');
            if (modelConfiguration == null) throw new AIAgentManagerException('No AI Model Configuration provided.');
            if (String.isBlank(modelConfiguration.NamedCredential__c)) throw new AIAgentManagerException('AI Model Configuration "' + modelConfiguration.DeveloperName__c + '" has no Named Credential configured.');
            if (String.isBlank(modelConfiguration.ApiPath__c)) throw new AIAgentManagerException('AI Model Configuration "' + modelConfiguration.DeveloperName__c + '" has no Api Path configured.');

            // [1] Get the provider's request builder and response handler - the only provider-specific classes; everything below stays provider-agnostic.
            String aiProviderName = modelConfiguration.AIProvider__c;
            if (!AIProvider.isSupported(aiProviderName)) throw new AIAgentManagerException('AI Model Configuration "' + modelConfiguration.DeveloperName__c + '" has an unsupported AI Provider "' + aiProviderName + '".');

            IAIProviderRequestBuilder providerRequestBuilder = AIProvider.getRequestBuilder(aiProviderName);
            IAIProviderResponseHandler providerResponseHandler = AIProvider.getResponseHandler(aiProviderName);

            // [2] Index the Data Sources by tool name (DeveloperName__c) - the model asks for a tool by this name, and invokeTool looks it up here.
            Map<String, AIDataSource__c> dataSourceByToolName = new Map<String, AIDataSource__c>();

            if (availableDataSources != null) {
                for (AIDataSource__c dataSource : availableDataSources) {
                    if (String.isNotBlank(dataSource.DeveloperName__c)) {
                        dataSourceByToolName.put(dataSource.DeveloperName__c, dataSource);
                    }
                }
            }

            // [3] Build the Tool Definitions advertised to the model - InputSchema__c is only advertised, never validated here (AiDataSourceDispatcher already fails closed on bad input). A blank schema falls back to an empty object schema.
            List<AIProvider.ToolDefinition> toolDefinitions = new List<AIProvider.ToolDefinition>();

            for (AIDataSource__c dataSource : dataSourceByToolName.values()) {

                AIProvider.ToolDefinition toolDefinition = new AIProvider.ToolDefinition();
                toolDefinition.name = dataSource.DeveloperName__c;
                toolDefinition.description = String.isNotBlank(dataSource.Description__c) ? dataSource.Description__c : dataSource.OutputDescription__c;
                if (String.isBlank(toolDefinition.description)) toolDefinition.description = dataSource.DeveloperName__c; // Providers expect a string, never null.

                if (String.isNotBlank(dataSource.InputSchema__c)) {
                    toolDefinition.inputSchema = (Map<String, Object>) JSON.deserializeUntyped(dataSource.InputSchema__c);
                } else {
                    toolDefinition.inputSchema = new Map<String, Object>{ 'type' => 'object', 'properties' => new Map<String, Object>() };
                }

                toolDefinitions.add(toolDefinition);
            }

            // [4] Build the canonical message history the model sees - User messages map to the user role, AI Agent messages to the assistant role. System-sender messages are internal audit notes, not something the user or model said, so they're excluded, as are blank messages.
            // The provider response handler appends to this same list as the loop runs (the model's replies and tool results), so it grows into the full conversation.
            List<Map<String, Object>> providerMessages = new List<Map<String, Object>>();

            if (messageHistory != null) {
                for (AIConversationMessage__c historyMessage : messageHistory) {

                    if (historyMessage.Sender__c == AIAssistApplicationConstants.SENDER_SYSTEM) continue;

                    // Providers reject a message with empty content, so one blank message would fail every later turn in the conversation.
                    if (String.isBlank(historyMessage.MessageBody__c)) continue;

                    String messageRole = (historyMessage.Sender__c == AIAssistApplicationConstants.SENDER_USER)
                        ? AIAssistApplicationConstants.CANONICAL_ROLE_USER
                        : AIAssistApplicationConstants.CANONICAL_ROLE_ASSISTANT;

                    providerMessages.add(new Map<String, Object>{
                        AIAssistApplicationConstants.CANONICAL_ROLE_KEY    => messageRole,
                        AIAssistApplicationConstants.CANONICAL_CONTENT_KEY => historyMessage.MessageBody__c
                    });
                }
            }

            // [5] Build the system prompt - the Prompt Template plus a compact list of Workflow Actions the model may suggest (never run). Parts are single-newline joined and whitespace collapsed to keep token usage down on every iteration.
            List<String> systemPromptParts = new List<String>();

            if (promptTemplate != null) {
                if (String.isNotBlank(promptTemplate.AISystemContext__c)) systemPromptParts.add(promptTemplate.AISystemContext__c);
                if (String.isNotBlank(promptTemplate.AIPrompt__c)) systemPromptParts.add(promptTemplate.AIPrompt__c);
                if (String.isNotBlank(promptTemplate.AITone__c)) systemPromptParts.add('Tone: ' + promptTemplate.AITone__c);
                if (String.isNotBlank(promptTemplate.AIExclusionRules__c)) systemPromptParts.add('Do not: ' + promptTemplate.AIExclusionRules__c);
            }

            if (availableWorkflowActions != null && !availableWorkflowActions.isEmpty()) {

                systemPromptParts.add(AIAssistApplicationConstants.WORKFLOW_ACTION_PROMPT_INSTRUCTION);

                for (AIWorkflowAction__c workflowAction : availableWorkflowActions) {
                    String workflowActionDescription = String.isNotBlank(workflowAction.Description__c) ? workflowAction.Description__c : workflowAction.OutputDescription__c;
                    systemPromptParts.add(workflowAction.DeveloperName__c + ': ' + workflowActionDescription);
                }

                systemPromptParts.add(AIAssistApplicationConstants.WORKFLOW_ACTION_PROMPT_JSON_INSTRUCTION);
            }

            // [5a] Collapse blank lines and repeated spaces/tabs, keeping single line breaks so authored lists stay readable.
            String systemPromptText = null;

            if (!systemPromptParts.isEmpty()) systemPromptText = String.join(systemPromptParts, '\n').replaceAll('[ \\t]*\\n\\s*', '\n').replaceAll('[ \\t]+', ' ').trim();

            // [6] Resolve the run limits and callout target.

            // Tool-calling iterations - the agent's own value, else the org default (AIAssistSettings__c). Clamped to 1..cap, since 0 or negative would skip the callout entirely and an unbounded value risks the 100-callout transaction limit.
            Integer maxToolCallingIterations = (agent.MaxToolCallingIterations__c == null) ? AIAssistSettingsService.getDefaultMaxToolCallingIterations() : agent.MaxToolCallingIterations__c.intValue();
            maxToolCallingIterations = Math.max(1, Math.min(maxToolCallingIterations, AIAssistSettingsService.getMaxToolCallingIterationsCap()));

            // Total attempts including retries (model-level) - the first attempt plus RetryAttempts__c.
            Integer configuredRetryAttempts = (modelConfiguration.RetryAttempts__c == null) ? 0 : modelConfiguration.RetryAttempts__c.intValue();
            Integer maxAttempts = 1 + configuredRetryAttempts;

            trace.toolCallingIterationsMax = maxToolCallingIterations;
            trace.attemptNumber = attemptNumber;

            // Tool calls run per model reply - any beyond this are skipped (AIAssistSettings__c.MaxToolCallsPerIteration__c).
            Integer maxToolCallsPerIteration = AIAssistSettingsService.getMaxToolCallsPerIteration();

            Integer maxOutputTokens = (modelConfiguration.MaximumOutputTokens__c == null) ? DEFAULT_MAX_OUTPUT_TOKENS : modelConfiguration.MaximumOutputTokens__c.intValue();
            Integer configuredCalloutTimeoutMillis = AIAssistSettingsService.getCalloutTimeoutMilliseconds(); // Throws if not configured - caught and logged below.
            String calloutEndpoint = 'callout:' + modelConfiguration.NamedCredential__c + modelConfiguration.ApiPath__c;

            Long calloutBudgetStartMilliseconds = System.currentTimeMillis(); // Start of the 120s callout budget - see AIGovernorLimits.getRemainingCalloutMilliseconds.

            // Tool calls (and their results) from the iteration just finished. They're handed to the response handler at the top of the NEXT iteration, since they must be added to providerMessages before that iteration's request is built.
            List<AIProvider.ToolCall> previousToolCalls = null;
            List<Object> previousToolResults = null;

            // Set when a callout can't complete (out of time, callout exception, retryable HTTP status) - the loop breaks and a single retryable-or-failed result is returned after it.
            String calloutErrorMessage = null;
            Boolean isCalloutErrorRetryable = true;

            // [7] Tool-calling loop - each iteration sends the request, then either returns the model's final text response or runs the requested tools and feeds their results into the next iteration. Stops early on a callout error, or at maxToolCallingIterations.
            for (Integer iteration = 0; iteration < maxToolCallingIterations; iteration++) {

                Boolean isLastIteration = (iteration == maxToolCallingIterations - 1);

                // Add the previous iteration's tool results to the conversation, in this provider's shape.
                if (previousToolCalls != null) {
                    providerResponseHandler.handleResponse(providerMessages, null, previousToolCalls, previousToolResults);
                    previousToolCalls = null;
                    previousToolResults = null;
                }

                AIProvider.Request canonicalRequest = new AIProvider.Request();
                canonicalRequest.modelIdentifier = modelConfiguration.ModelIdentifier__c;
                canonicalRequest.maxOutputTokens = maxOutputTokens;
                canonicalRequest.temperature = modelConfiguration.Temperature__c;
                canonicalRequest.systemPromptText = systemPromptText;
                canonicalRequest.messages = providerMessages;
                canonicalRequest.tools = toolDefinitions;
                canonicalRequest.allowToolCalls = !isLastIteration; // Last chance - the model must answer with what it already has.

                String requestBody = JSON.serialize(providerRequestBuilder.buildRequestBody(canonicalRequest));

                // [7a] Trim this callout's timeout to what's left of the transaction's 120s callout budget - otherwise a slow provider across several iterations hits the platform limit mid-turn.
                Integer remainingCalloutMillis = AIGovernorLimits.getRemainingCalloutMilliseconds(calloutBudgetStartMilliseconds);

                if (remainingCalloutMillis < AIAssistApplicationConstants.MIN_CALLOUT_TIMEOUT_MILLISECONDS) {
                    calloutErrorMessage = 'Ran out of callout time after ' + iteration + ' tool-calling iteration(s).';
                    isCalloutErrorRetryable = false; // A retry would repeat the same iterations and run out again.
                    break;
                }

                // Only when a debug user is watching (trace.captureFullDetail) - both are already-pseudonymised text, but there's no reason to hold them in memory for every turn.
                if (trace.captureFullDetail) {
                    trace.lastRequestJson = requestBody;
                    trace.sentPreviewText = buildSentPreview(providerMessages);
                }

                // [7b] Build and send the callout via the Named Credential with the trimmed timeout. A thrown callout exception (timeout, unreachable endpoint) breaks the loop as a retryable-or-failed result rather than a hard failure.
                HttpRequest httpRequest = new HttpRequest();
                httpRequest.setEndpoint(calloutEndpoint);
                httpRequest.setMethod(AIAssistApplicationConstants.HTTP_METHOD_POST);
                httpRequest.setHeader(AIAssistApplicationConstants.HTTP_HEADER_CONTENT_TYPE, AIAssistApplicationConstants.CONTENT_TYPE_JSON);
                if (String.isNotBlank(modelConfiguration.ApiVersionHeaderName__c)) httpRequest.setHeader(modelConfiguration.ApiVersionHeaderName__c, modelConfiguration.ApiVersionHeaderValue__c);
                httpRequest.setTimeout(Math.min(configuredCalloutTimeoutMillis, remainingCalloutMillis));
                httpRequest.setBody(requestBody);

                HttpResponse httpResponse;
                trace.startPhase('Provider callout', null);
                try {
                    httpResponse = new Http().send(httpRequest);
                    trace.endPhase(true);
                } catch (Exception calloutException) {
                    trace.endPhase(false);

                    // Uncommitted DML earlier in this transaction that the per-tool check missed - treated the same as a Data Source write, so it's rolled back too.
                    if (AIGovernorLimits.isUncommittedWorkException(calloutException)) {
                        throw new AIDataSourceWriteException('A database write earlier in this turn blocked the AI provider callout. AI Data Sources must be read-only.', calloutException);
                    }

                    // Logged here because it's turned into a result below rather than rethrown - the outer catch never sees it.
                    AIPlatformLogManager.logException(calloutException, 'AIAgentManager', 'executeAiMessage');
                    calloutErrorMessage = 'AI provider callout failed: ' + calloutException.getMessage();
                    break;
                }

                trace.toolCallingIterationsUsed = iteration + 1;
                if (trace.captureFullDetail) trace.lastResponseJson = httpResponse.getBody();

                // [7c] A retryable status (e.g. 429, 503 - AIAssistSettings__c.RetryableStatusCodes__c) ends this attempt so the caller can retry with fresh limits.
                if (AIAssistSettingsService.getRetryStatusCodes().contains(httpResponse.getStatusCode())) {
                    calloutErrorMessage = 'AI provider returned a retryable HTTP status: ' + httpResponse.getStatusCode();
                    break;
                }

                // [7d] Parse the reply into the canonical Response. Throws for any other non-success status - a hard, non-retryable failure caught and logged below.
                AIProvider.Response modelResponse = providerResponseHandler.handleResponse(providerMessages, httpResponse, null, null);
                totalTokensUsed += modelResponse.totalTokens;

                // [7e] No tool calls - this is the model's final reply.
                if (modelResponse.toolCalls.isEmpty()) {
                    AgentResult successResult = new AgentResult();
                    successResult.isSuccessful = true;
                    successResult.totalTokensUsed = totalTokensUsed;
                    applyWorkflowActionSuggestion(successResult, modelResponse.textContent, availableWorkflowActions);
                    return successResult;
                }

                // Tool calls were disabled on the last iteration, so this only happens if the provider ignored that - their results could never be sent back, so don't run them.
                if (isLastIteration) break;

                // [7f] Run the requested tools and keep the results for the next iteration's request.
                // Every tool call must get a result (providers reject a reply that leaves one unanswered), so a skipped call gets an explanation instead of being dropped.
                List<Object> toolResults = new List<Object>();

                for (Integer toolIndex = 0; toolIndex < modelResponse.toolCalls.size(); toolIndex++) {

                    AIProvider.ToolCall toolCall = modelResponse.toolCalls[toolIndex];

                    // Over the per-reply cap (AIAssistSettings__c.MaxToolCallsPerIteration__c).
                    // Over the per-reply cap (AIAssistSettings__c.MaxToolCallsPerIteration__c).
                    if (toolIndex >= maxToolCallsPerIteration) {
                        toolResults.add(AIAssistApplicationConstants.TOOL_RESULT_SKIPPED_TOO_MANY_CALLS);
                        continue;
                    }

                    // Not enough SOQL/callouts/CPU/heap left to run another tool and still finish the turn - running it could throw an uncatchable LimitException.
                    if (!AIGovernorLimits.isSafeToRunToolCall()) {
                        toolResults.add(AIAssistApplicationConstants.TOOL_RESULT_SKIPPED_LIMITS_REACHED);
                        continue;
                    }

                    AIGovernorLimits.DmlSnapshot dmlBeforeTool = AIGovernorLimits.takeDmlSnapshot();

                    AIDataSource__c dataSourceForTrace = dataSourceByToolName.get(toolCall.name);
                    trace.startPhase(buildDataSourceLiveLabel(dataSourceForTrace, toolCall.name), dataSourceForTrace != null ? dataSourceForTrace.Id : null);

                    Object toolResult = invokeTool(toolCall, dataSourceByToolName, conversation);
                    trace.endPhase(toolResult != AIAssistApplicationConstants.TOOL_RESULT_FAILED);
                    toolResults.add(toolResult);

                    // A Data Source that wrote to the database has blocked every later callout in this transaction - fail now with a clear reason rather than at the next callout.
                    // Thrown as AIDataSourceWriteException so it escapes the job and the whole transaction - including this write - is rolled back.
                    if (AIGovernorLimits.isUncommittedDmlSince(dmlBeforeTool)) {
                        throw new AIDataSourceWriteException('AI Data Source "' + toolCall.name + '" wrote to the database. AI Data Sources must be read-only, since a database write blocks every later AI provider callout in the same transaction.');
                    }
                }

                previousToolCalls = modelResponse.toolCalls;
                previousToolResults = toolResults;
            }

            // Callout couldn't complete - retryable while attempts remain (AiMessageProcessingFinalizer schedules the retry). Carries the tokens this attempt already spent so the retry adds to them rather than losing them.
            if (calloutErrorMessage != null) {
                AgentResult calloutFailureResult = new AgentResult();
                calloutFailureResult.errorMessage = calloutErrorMessage;
                calloutFailureResult.totalTokensUsed = totalTokensUsed;
                calloutFailureResult.isRetryable = isCalloutErrorRetryable && attemptNumber < maxAttempts;

                return calloutFailureResult;
            }

            throw new AIAgentManagerException('Reached the maximum of ' + maxToolCallingIterations + ' tool-calling iterations without a final response.');

        } catch (AIDataSourceWriteException dataSourceWriteException) {
            // Not logged or handled here - see AIDataSourceWriteException. Rethrown with the tokens spent so far, so they can still be recorded after the rollback.
            dataSourceWriteException.tokensUsed = totalTokensUsed;
            throw dataSourceWriteException;

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIAgentManager', 'executeAiMessage');

            AgentResult failureResult = new AgentResult();
            failureResult.errorMessage = 'Failed to get a response from the AI provider: ' + ex.getMessage();
            failureResult.totalTokensUsed = totalTokensUsed; // Tokens already spent are still billed - the caller records them.
            return failureResult;

        } finally {
            // Deferral only applies while the loop is running. The mappings stay cached in memory - the caller must still call AIPiiMappingService.processCachedPIIMappings().
            AIPiiMappingService.isDeferringWrites = false;
        }
    }

    // Runs one tool call against its matching Data Source. A tool failure doesn't abort the turn - it's logged here and the model is told the tool failed, so it can react rather than the conversation just dying.
    // The model only ever gets a generic message: the real error can contain SOQL, class names, record Ids or field values, and the model is a third party.
    private static Object invokeTool(AIProvider.ToolCall toolCall, Map<String, AIDataSource__c> dataSourceByToolName, AIConversation__c conversation) {
        try {

            AIDataSource__c dataSource = dataSourceByToolName.get(toolCall.name);
            if (dataSource == null) throw new AIAgentManagerException('The model requested an unknown tool "' + toolCall.name + '".');

            Id relatedRecordId = String.isBlank(conversation.RelatedRecordId__c) ? null : (Id) conversation.RelatedRecordId__c;

            List<Object> toolRecords = AiDataSourceDispatcher.execute(dataSource.Id, relatedRecordId, toolCall.arguments, null, conversation.Id);

            // An explicit message, not a bare "[]", so the model reads a genuine no-match and stops retrying.
            if (toolRecords == null || toolRecords.isEmpty()) return AIAssistApplicationConstants.TOOL_RESULT_NO_RECORDS_FOUND;

            return toolRecords;

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIAgentManager', 'invokeTool');
            return AIAssistApplicationConstants.TOOL_RESULT_FAILED;
        }
    }

    // The live "Working on it" label for a data source read - "Reading Contact Roles". Falls back to the raw tool name for a tool the model requested that doesn't resolve to a Data Source, so startPhase always has something to publish.
    private static String buildDataSourceLiveLabel(AIDataSource__c dataSource, String toolName) {
        return 'Reading ' + humaniseDeveloperName(dataSource != null ? dataSource.DeveloperName__c : toolName);
    }

    // "ContactRoles" / "Contact_Roles" -> "Contact Roles". Duplicated in miniature from AIChatDataStructure.humanise rather than shared - this class has no other reason to depend on the AIChatController family, and the function is a handful of lines.
    private static String humaniseDeveloperName(String developerName) {
        if (String.isBlank(developerName)) return '';
        String spaced = developerName.replace('_', ' ').replaceAll('([a-z0-9])([A-Z])', '$1 $2').normalizeSpace();
        return spaced.left(1).toUpperCase() + spaced.substring(1);
    }

    // The newest user-role message actually in providerMessages when this callout was built - a short, already-pseudonymised preview so a debug user can confirm masking worked without opening the PII mapping pairs.
    private static String buildSentPreview(List<Map<String, Object>> providerMessages) {
        for (Integer messageIndex = providerMessages.size() - 1; messageIndex >= 0; messageIndex--) {

            Map<String, Object> message = providerMessages[messageIndex];
            if (String.valueOf(message.get(AIAssistApplicationConstants.CANONICAL_ROLE_KEY)) != AIAssistApplicationConstants.CANONICAL_ROLE_USER) continue;

            String content = String.valueOf(message.get(AIAssistApplicationConstants.CANONICAL_CONTENT_KEY));
            return String.isBlank(content) ? null : content.abbreviate(200);
        }
        return null;
    }

    // Looks for a trailing {"suggested_workflow_action": "<DeveloperName>"} line, resolves it against what was actually offered, and strips it out of the visible reply.
    // The reply is always set first, so if nothing valid is found - or anything goes wrong - the user still gets the model's full reply, just without a suggestion.
    private static void applyWorkflowActionSuggestion(AgentResult agentResult, String modelReplyText, List<AIWorkflowAction__c> availableWorkflowActions) {
        try {

            agentResult.replyText = modelReplyText;

            if (String.isBlank(modelReplyText) || availableWorkflowActions == null || availableWorkflowActions.isEmpty()) return;

            // The suggestion, if any, is the last JSON object in the reply.
            Integer suggestionStartIndex = modelReplyText.lastIndexOf('{');
            if (suggestionStartIndex < 0) return;

            // Only parse text that actually names the suggestion key - an ordinary reply that happens to contain a brace isn't a suggestion, and shouldn't be parsed or logged as a failure.
            String suggestionJson = modelReplyText.substring(suggestionStartIndex);
            if (!suggestionJson.contains(AIAssistApplicationConstants.SUGGESTED_WORKFLOW_ACTION_JSON_KEY)) return;

            Map<String, Object> suggestion = (Map<String, Object>) JSON.deserializeUntyped(suggestionJson);
            String suggestedDeveloperName = (String) suggestion.get(AIAssistApplicationConstants.SUGGESTED_WORKFLOW_ACTION_JSON_KEY);
            if (String.isBlank(suggestedDeveloperName)) return;

            // Only a Workflow Action that was actually offered to the model is accepted.
            for (AIWorkflowAction__c workflowAction : availableWorkflowActions) {
                if (workflowAction.DeveloperName__c == suggestedDeveloperName) {

                    agentResult.suggestedWorkflowActionId = workflowAction.Id;

                    // Strip the JSON line from the visible reply - unless it was the whole reply. A blank reply would be saved as a blank message, and providers reject blank messages.
                    String replyWithoutSuggestion = modelReplyText.substring(0, suggestionStartIndex).trim();
                    agentResult.replyText = String.isNotBlank(replyWithoutSuggestion) ? replyWithoutSuggestion : AIAssistApplicationConstants.WORKFLOW_ACTION_SUGGESTION_ONLY_REPLY;
                    return;
                }
            }

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIAgentManager', 'applyWorkflowActionSuggestion');
        }
    }
}