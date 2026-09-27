/*
Class Name: AIAnthropicRequestBuilder

=================================================================
=================================================================

Description: IAIProviderRequestBuilder for Anthropic's Messages API - builds the request body.
Deliberately a separate class from AIAnthropicResponseHandler; building a request and handling
a response are different jobs. The endpoint path and version header live on
AIModelConfiguration__c instead of here, since they vary per deployment, not per provider brand.
Every JSON field name this shape depends on is a AIAssistApplicationConstants.ANTHROPIC_* constant -
adding or changing a provider is a new pair of classes registered in AIProvider, never a change to AIAgentManager.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-26     Chandler Stuart          Initial development
1.1          2026-09-26     Chandler Stuart          Removed apiPath/apiVersionHeader* - moved to AIModelConfiguration__c fields.
1.2          2026-09-26     Chandler Stuart          Moved field names to AIAssistApplicationConstants, wrapped in try/catch.
1.3          2026-09-27     Chandler Stuart          Sends tool_choice {"type": "none"} when Request.allowToolCalls is false.
1.4          2026-09-27     Chandler Stuart          Canonical types moved from AIAgentManager to AIProvider.
*/

public without sharing class AIAnthropicRequestBuilder implements IAIProviderRequestBuilder {

    public class AIAnthropicRequestBuilderException extends Exception {}

    // Builds { model, max_tokens, messages, [temperature], [system], [tools] } - optional keys are omitted entirely when unset, never sent as null.
    public Map<String, Object> buildRequestBody(AIProvider.Request request) {

        try {

            // Required fields - Anthropic rejects a request missing any of these
            Map<String, Object> requestBody = new Map<String, Object>{
                AIAssistApplicationConstants.ANTHROPIC_FIELD_MODEL => request.modelIdentifier,
                AIAssistApplicationConstants.ANTHROPIC_FIELD_MAX_TOKENS => request.maxOutputTokens,
                AIAssistApplicationConstants.ANTHROPIC_FIELD_MESSAGES => request.messages
            };

            if (request.temperature != null) requestBody.put(AIAssistApplicationConstants.ANTHROPIC_FIELD_TEMPERATURE, request.temperature);

            // System prompt is a top-level field on Anthropic (unlike OpenAI, where it is a system-role message)
            if (String.isNotBlank(request.systemPromptText)) requestBody.put(AIAssistApplicationConstants.ANTHROPIC_FIELD_SYSTEM, request.systemPromptText);

            // One { name, description, input_schema } entry per tool - Anthropic's flat tool shape, with no OpenAI-style "function" wrapper.
            if (request.tools != null && !request.tools.isEmpty()) {

                List<Object> toolDefinitions = new List<Object>();

                for (AIProvider.ToolDefinition tool : request.tools) {
                    toolDefinitions.add(new Map<String, Object>{
                        AIAssistApplicationConstants.ANTHROPIC_FIELD_TOOL_NAME => tool.name,
                        AIAssistApplicationConstants.ANTHROPIC_FIELD_TOOL_DESCRIPTION => tool.description,
                        AIAssistApplicationConstants.ANTHROPIC_FIELD_TOOL_INPUT_SCHEMA => tool.inputSchema
                    });
                }

                requestBody.put(AIAssistApplicationConstants.ANTHROPIC_FIELD_TOOLS, toolDefinitions);

                // Last tool-calling iteration - tools stay listed (Anthropic rejects a conversation with tool_use blocks but no tools) but the model may not call one.
                if (request.allowToolCalls == false) requestBody.put(AIAssistApplicationConstants.ANTHROPIC_FIELD_TOOL_CHOICE, new Map<String, Object>{ AIAssistApplicationConstants.ANTHROPIC_FIELD_TOOL_CHOICE_TYPE => AIAssistApplicationConstants.ANTHROPIC_TOOL_CHOICE_NONE });

            }

            return requestBody;

        } catch (Exception ex) {
            // Not logged here - AIAgentManager.executeAiMessage handles and logs it, so it's logged exactly once. Rethrown rather than swallowed, since a null body must never reach Anthropic.
            throw new AIAnthropicRequestBuilderException('Failed to build the Anthropic request body: ' + ex.getMessage(), ex);
        }
    }
}