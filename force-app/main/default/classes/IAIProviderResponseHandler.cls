/*
Class Name: IAIProviderResponseHandler

=================================================================
=================================================================

Description: Contract for one AI provider's response shape - a single method covering
everything response-side. AIProvider picks the implementation matching
AIModelConfiguration__c.AIProvider__c (e.g. AIAnthropicResponseHandler, AIOpenAiResponseHandler)
and AIAgentManager never inspects a provider's raw JSON itself.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-26     Chandler Stuart          Initial development
1.1          2026-09-27     Chandler Stuart          Canonical types moved from AIAgentManager to AIProvider.
*/

public interface IAIProviderResponseHandler {

    // Shapes providerMessages for one job: either appends prior tool results (previousToolCalls/previousToolResults set, response null) or parses response and appends the assistant turn (response set, previousToolCalls/previousToolResults null); called once per job per tool-calling loop pass by AIAgentManager.
    AIProvider.Response handleResponse(List<Map<String, Object>> providerMessages, HttpResponse response, List<AIProvider.ToolCall> previousToolCalls, List<Object> previousToolResults);
}