/*
Class Name: IAIProviderResponseHandler

=================================================================
=================================================================

Description: Contract for one AI provider's response shape - a single method covering
everything response-side. AIAgentManager instantiates the implementation matching
AIModelConfiguration__c.AIProvider__c (e.g. AIAnthropicResponseHandler, AIOpenAiResponseHandler)
and never inspects a provider's raw JSON itself.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-26     Chandler Stuart          Initial development
*/

public interface IAIProviderResponseHandler {

    // Shapes providerMessages for one job: either appends prior tool results (previousToolCalls/previousToolResults set, response null) or parses response and appends the assistant turn (response set, previousToolCalls/previousToolResults null); called once per job per tool-calling loop pass by AIAgentManager.
    AIAgentManager.Response handleResponse(List<Map<String, Object>> providerMessages, HttpResponse response, List<AIAgentManager.ToolCall> previousToolCalls, List<Object> previousToolResults);
}