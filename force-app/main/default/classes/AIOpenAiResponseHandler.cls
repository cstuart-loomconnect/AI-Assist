/*
Class Name: AIOpenAiResponseHandler

=================================================================
=================================================================

Description: IAIProviderResponseHandler for OpenAI's Chat Completions API - parses a response
and shapes providerMessages. Deliberately a separate class from AIOpenAiRequestBuilder; handling
a response and building a request are different jobs. Every field name/value this shape depends
on is a AIAssistApplicationConstants.OPENAI_* constant - adding or changing
a provider is a new pair of classes registered in AIProvider, never a change to AIAgentManager.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-26     Chandler Stuart          Initial development
1.1          2026-09-27     Chandler Stuart          Canonical types moved from AIAgentManager to AIProvider.
*/

public without sharing class AIOpenAiResponseHandler implements IAIProviderResponseHandler {

    public class AIOpenAiResponseHandlerException extends Exception {}

    // previousToolCalls non-null: appends one tool-role message per tool result from the prior iteration. openAiHttpResponse non-null: parses it and appends the assistant's message object as-is.
    public AIProvider.Response handleResponse(List<Map<String, Object>> providerMessages, HttpResponse openAiHttpResponse, List<AIProvider.ToolCall> previousToolCalls, List<Object> previousToolResults) {

        try {

            // Tool results - OpenAI expects one tool-role message per tool call from the prior assistant turn, each keyed by tool_call_id.
            if (previousToolCalls != null) {

                if (previousToolResults == null || previousToolResults.size() != previousToolCalls.size()) throw new AIOpenAiResponseHandlerException('Tool result count does not match tool call count - every tool call needs exactly one tool result.');

                // One tool-role message per tool call (unlike Anthropic, which batches all results into a single user-role message) - tool_call_id echoes the tool call's id so OpenAI can pair each output with its request.
                for (Integer toolIndex = 0; toolIndex < previousToolCalls.size(); toolIndex++) {
                    providerMessages.add( new Map<String, Object>{ AIAssistApplicationConstants.OPENAI_ROLE_KEY => AIAssistApplicationConstants.OPENAI_ROLE_TOOL, AIAssistApplicationConstants.OPENAI_FIELD_TOOL_RESULT_ID => previousToolCalls[toolIndex].id, AIAssistApplicationConstants.OPENAI_FIELD_CONTENT => AIProvider.stringifyToolResult(previousToolResults[toolIndex]) } );
                }
            }

            if (openAiHttpResponse == null) return null;

            String rawResponseBody = openAiHttpResponse.getBody();

            // Status not in AIAssistSettings__c.AIProviderSuccessStatusCodes__c - expose OpenAI's error, e.g. { "error": { "message": "...", "type": "invalid_request_error", ... } }, falling back to the raw body.
            if (!AIAssistSettingsService.getSuccessStatusCodes().contains(openAiHttpResponse.getStatusCode())) {

                String providerErrorDetail = rawResponseBody;
                Boolean isJsonObjectBody = String.isNotBlank(rawResponseBody) && rawResponseBody.trim().startsWith('{') && rawResponseBody.trim().endsWith('}');
                Object errorResponseBody = isJsonObjectBody ? JSON.deserializeUntyped(rawResponseBody) : null;
                Object errorDetails = errorResponseBody instanceof Map<String, Object> ? ((Map<String, Object>) errorResponseBody).get(AIAssistApplicationConstants.OPENAI_FIELD_ERROR) : null;

                if (errorDetails instanceof Map<String, Object>) {
                    Object providerErrorType = ((Map<String, Object>) errorDetails).get(AIAssistApplicationConstants.OPENAI_FIELD_ERROR_TYPE);
                    Object providerErrorMessage = ((Map<String, Object>) errorDetails).get(AIAssistApplicationConstants.OPENAI_FIELD_ERROR_MESSAGE);
                    if (providerErrorMessage != null) providerErrorDetail = (providerErrorType == null ? '' : providerErrorType + ' - ') + providerErrorMessage;
                }

                throw new AIOpenAiResponseHandlerException('AI provider returned HTTP ' + openAiHttpResponse.getStatusCode() + ': ' + providerErrorDetail);
            }

            // Parse the successful response body - the reply lives in choices[0].message
            Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(rawResponseBody);
            List<Object> responseChoices = (List<Object>) responseBody.get(AIAssistApplicationConstants.OPENAI_FIELD_CHOICES);

            if (responseChoices == null || responseChoices.isEmpty()) throw new AIOpenAiResponseHandlerException('OpenAI response contained no choices.');

            Map<String, Object> assistantMessage = (Map<String, Object>) ((Map<String, Object>) responseChoices[0]).get(AIAssistApplicationConstants.OPENAI_FIELD_MESSAGE);

            if (assistantMessage == null) throw new AIOpenAiResponseHandlerException('OpenAI response choice contained no message.');

            AIProvider.Response agentResponse = new AIProvider.Response();

            // Content is a single string (null when the assistant only calls tools) - becomes the reply text
            String messageContent = (String) assistantMessage.get(AIAssistApplicationConstants.OPENAI_FIELD_CONTENT);
            agentResponse.textContent = messageContent != null ? messageContent : '';

            List<Object> toolCallItems = (List<Object>) assistantMessage.get(AIAssistApplicationConstants.OPENAI_FIELD_TOOL_CALLS);

            if (toolCallItems == null) toolCallItems = new List<Object>();

            // Each tool_calls entry becomes a tool call - name and arguments live under its function object
            for (Object toolCallItemObject : toolCallItems) {

                Map<String, Object> toolCallItem = (Map<String, Object>) toolCallItemObject;
                Map<String, Object> toolFunction = (Map<String, Object>) toolCallItem.get(AIAssistApplicationConstants.OPENAI_FIELD_TOOL_FUNCTION);

                // OpenAI sends arguments as a JSON string, not an object - deserialize it (blank means no arguments)
                String toolArgumentsJson = (String) toolFunction.get(AIAssistApplicationConstants.OPENAI_FIELD_TOOL_CALL_ARGUMENTS);

                AIProvider.ToolCall toolCall = new AIProvider.ToolCall();
                toolCall.id = (String) toolCallItem.get(AIAssistApplicationConstants.OPENAI_FIELD_TOOL_CALL_ID);
                toolCall.name = (String) toolFunction.get(AIAssistApplicationConstants.OPENAI_FIELD_TOOL_NAME);
                toolCall.arguments = String.isBlank(toolArgumentsJson) ? new Map<String, Object>() : (Map<String, Object>) JSON.deserializeUntyped(toolArgumentsJson);

                agentResponse.toolCalls.add(toolCall);
            }

            // Total tokens come straight from usage.total_tokens (missing value counts as 0)
            Map<String, Object> tokenUsage = (Map<String, Object>) responseBody.get(AIAssistApplicationConstants.OPENAI_FIELD_USAGE);

            if (tokenUsage != null) {
                Integer totalTokens = (Integer) tokenUsage.get(AIAssistApplicationConstants.OPENAI_FIELD_USAGE_TOTAL_TOKENS);

                agentResponse.totalTokens = totalTokens != null ? totalTokens : 0;
            }

            // Add the assistant's message to the conversation exactly as OpenAI returned it (role, content, tool_calls), so the next request includes it
            providerMessages.add(assistantMessage);

            return agentResponse;

        } catch (Exception ex) {
            if (ex instanceof AIOpenAiResponseHandlerException) throw ex;
            throw new AIOpenAiResponseHandlerException('Failed to handle the OpenAI response: ' + ex.getMessage(), ex);
        }
    }
}