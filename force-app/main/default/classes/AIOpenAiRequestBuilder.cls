/*
Class Name: AIOpenAiRequestBuilder

=================================================================
=================================================================

Description: IAIProviderRequestBuilder for OpenAI's Chat Completions API - builds the request
body. Deliberately a separate class from AIOpenAiResponseHandler; building a request and
handling a response are different jobs. The endpoint path and version header live on
AIModelConfiguration__c instead of here, since they vary per deployment, not per provider brand.
Every JSON field name/value this shape depends on is a AIAssistApplicationConstants.OPENAI_* constant -
adding or changing a provider is a new pair of classes registered in AIProvider, never a change to AIAgentManager.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-26     Chandler Stuart          Initial development
1.1          2026-09-26     Chandler Stuart          Removed apiPath/apiVersionHeader* - moved to AIModelConfiguration__c fields.
1.2          2026-09-27     Chandler Stuart          Moved field names to AIAssistApplicationConstants, wrapped in try/catch.
1.3          2026-09-27     Chandler Stuart          Sends tool_choice "none" when Request.allowToolCalls is false.
1.4          2026-09-27     Chandler Stuart          Canonical types moved from AIAgentManager to AIProvider.
*/

public without sharing class AIOpenAiRequestBuilder implements IAIProviderRequestBuilder {

    public class AIOpenAiRequestBuilderException extends Exception {}

    // Builds { model, max_tokens, messages, [temperature], [tools] } - optional keys are omitted entirely when unset, never sent as null.
    public Map<String, Object> buildRequestBody(AIProvider.Request request) {

        try {

            // System prompt goes first as a system-role message (unlike Anthropic, where it is a top-level field)
            List<Map<String, Object>> allMessages = new List<Map<String, Object>>();

            if (String.isNotBlank(request.systemPromptText)) {
                Map<String, Object> systemMessage = new Map<String, Object>{
                    AIAssistApplicationConstants.OPENAI_ROLE_KEY => AIAssistApplicationConstants.OPENAI_ROLE_SYSTEM,
                    AIAssistApplicationConstants.OPENAI_FIELD_CONTENT => request.systemPromptText
                };
                allMessages.add(systemMessage);
            }

            allMessages.addAll(request.messages);

            // Required fields - OpenAI rejects a request missing any of these
            Map<String, Object> requestBody = new Map<String, Object>{
                AIAssistApplicationConstants.OPENAI_FIELD_MODEL => request.modelIdentifier,
                AIAssistApplicationConstants.OPENAI_FIELD_MAX_TOKENS => request.maxOutputTokens,
                AIAssistApplicationConstants.OPENAI_FIELD_MESSAGES => allMessages
            };

            if (request.temperature != null) requestBody.put(AIAssistApplicationConstants.OPENAI_FIELD_TEMPERATURE, request.temperature);

            // One { type: "function", function: { name, description, parameters } } entry per tool - OpenAI wraps each tool in a "function" object.
            if (request.tools != null && !request.tools.isEmpty()) {

                List<Object> toolDefinitions = new List<Object>();

                for (AIProvider.ToolDefinition tool : request.tools) {

                    Map<String, Object> functionDetails = new Map<String, Object>{
                        AIAssistApplicationConstants.OPENAI_FIELD_TOOL_NAME => tool.name,
                        AIAssistApplicationConstants.OPENAI_FIELD_TOOL_DESCRIPTION => tool.description,
                        AIAssistApplicationConstants.OPENAI_FIELD_TOOL_PARAMETERS => tool.inputSchema
                    };

                    Map<String, Object> toolDefinition = new Map<String, Object>{
                        AIAssistApplicationConstants.OPENAI_FIELD_TOOL_TYPE => AIAssistApplicationConstants.OPENAI_TOOL_TYPE_FUNCTION,
                        AIAssistApplicationConstants.OPENAI_FIELD_TOOL_FUNCTION => functionDetails
                    };

                    toolDefinitions.add(toolDefinition);
                }

                requestBody.put(AIAssistApplicationConstants.OPENAI_FIELD_TOOLS, toolDefinitions);

                // Last tool-calling iteration - tools stay listed (OpenAI only accepts tool_choice alongside tools) but the model may not call one.
                if (request.allowToolCalls == false) requestBody.put(AIAssistApplicationConstants.OPENAI_FIELD_TOOL_CHOICE, AIAssistApplicationConstants.OPENAI_TOOL_CHOICE_NONE);
            }

            return requestBody;

        } catch (Exception ex) {
            throw new AIOpenAiRequestBuilderException('Failed to build the OpenAI request body: ' + ex.getMessage(), ex);
        }
    }
}