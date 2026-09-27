/*
Class Name: AIProvider

=================================================================
=================================================================

Description: Everything shared between AIAgentManager and the provider classes (the
IAIProviderRequestBuilder/IAIProviderResponseHandler implementations):
- The canonical, provider-agnostic data types - Request/ToolDefinition going out, Response/ToolCall
  coming back. No provider-specific field names live on these; each provider class converts to
  and from its own JSON shape.
- The provider lookup - which request builder and response handler serve each
  AIModelConfiguration__c.AIProvider__c value.

Adding a provider: add its AIProvider__c picklist value and AI_PROVIDER_* constant, write its
request builder and response handler, then add one line to each map below. AIAgentManager never
changes.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-27     Chandler Stuart          Initial development - Request/ToolDefinition/Response/ToolCall and stringifyToolResult moved from AIAgentManager, plus the provider lookup.
*/

public without sharing class AIProvider {

    public class AIProviderException extends Exception {}

    // Keyed by the lower-cased AIProvider__c value, so the match is case-insensitive.
    private static final Map<String, Type> REQUEST_BUILDER_BY_PROVIDER = new Map<String, Type>{
        AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC.toLowerCase() => AIAnthropicRequestBuilder.class, // Anthropic - Messages API
        AIAssistApplicationConstants.AI_PROVIDER_OPEN_AI.toLowerCase()   => AIOpenAiRequestBuilder.class     // OpenAI - Chat Completions API
    };

    private static final Map<String, Type> RESPONSE_HANDLER_BY_PROVIDER = new Map<String, Type>{
        AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC.toLowerCase() => AIAnthropicResponseHandler.class,
        AIAssistApplicationConstants.AI_PROVIDER_OPEN_AI.toLowerCase()   => AIOpenAiResponseHandler.class
    };

    // The canonical shape of one outbound request to an AI provider. Built by AIAgentManager from
    // AIModelConfiguration__c, the assembled system prompt, and conversation history/tools - an
    // IAIProviderRequestBuilder then converts it into its provider's exact JSON shape.
    public class Request {
        public String modelIdentifier;
        public Integer maxOutputTokens;
        public Decimal temperature;
        public String systemPromptText;
        public List<Map<String, Object>> messages;
        public List<ToolDefinition> tools;
        // false on the last allowed iteration - tools are still listed (providers reject a conversation containing tool calls without them) but the model may not call one, so it must answer.
        public Boolean allowToolCalls = true;
    }

    // Apex doesn't allow a nested type to itself declare a nested type, so ToolDefinition sits
    // alongside Request rather than inside it, even though it only ever appears as Request.tools.
    public class ToolDefinition {
        public String name;
        public String description;
        public Map<String, Object> inputSchema;
    }

    // The canonical shape of one parsed AI provider response. Each IAIProviderResponseHandler
    // converts its provider's raw HttpResponse into this shape (and appends its own provider-shaped
    // representation of "what the assistant said" directly onto providerMessages itself) -
    // AIAgentManager's tool-calling loop reads only this shape, never a provider's raw JSON.
    public class Response {
        public String textContent;
        public List<ToolCall> toolCalls = new List<ToolCall>();
        public Decimal totalTokens = 0;
    }

    // Sits alongside Response for the same reason ToolDefinition sits alongside Request.
    public class ToolCall {
        public String id;
        public String name;
        public Map<String, Object> arguments;
    }

    // True when AIProvider__c names a provider with a request builder and response handler.
    public static Boolean isSupported(String providerName) {
        if (String.isBlank(providerName)) return false;
        return REQUEST_BUILDER_BY_PROVIDER.containsKey(providerName.toLowerCase()) && RESPONSE_HANDLER_BY_PROVIDER.containsKey(providerName.toLowerCase());
    }

    // Throws for an unsupported provider - check isSupported first for a clearer error.
    public static IAIProviderRequestBuilder getRequestBuilder(String providerName) {
        if (!isSupported(providerName)) throw new AIProviderException('Unsupported AI Provider "' + providerName + '".');
        return (IAIProviderRequestBuilder) REQUEST_BUILDER_BY_PROVIDER.get(providerName.toLowerCase()).newInstance();
    }

    // Throws for an unsupported provider - check isSupported first for a clearer error.
    public static IAIProviderResponseHandler getResponseHandler(String providerName) {
        if (!isSupported(providerName)) throw new AIProviderException('Unsupported AI Provider "' + providerName + '".');
        return (IAIProviderResponseHandler) RESPONSE_HANDLER_BY_PROVIDER.get(providerName.toLowerCase()).newInstance();
    }

    // Tool results are fed back to the provider as text either way - a String passes through untouched, anything else is JSON-serialized.
    public static String stringifyToolResult(Object toolResult) {
        if (toolResult instanceof String) return (String) toolResult;
        try {
            return JSON.serialize(toolResult);
        } catch (Exception ex) {
            return String.valueOf(toolResult); // Not serializable - fall back to its plain text form rather than losing the result.
        }
    }
}