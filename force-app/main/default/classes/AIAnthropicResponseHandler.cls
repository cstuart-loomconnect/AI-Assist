/*
Class Name: AIAnthropicResponseHandler

=================================================================
=================================================================

Description: IAIProviderResponseHandler for Anthropic's Messages API - parses a response and
shapes providerMessages. Deliberately a separate class from AIAnthropicRequestBuilder; handling
a response and building a request are different jobs. Every field name/value this shape depends
on is a AIAssistApplicationConstants.ANTHROPIC_* constant - adding or changing
a provider is a new pair of classes, never a change to AIAgentManager.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-26     Chandler Stuart          Initial development
1.1          2026-09-26     Chandler Stuart          Wrapped handleResponse in a single try/catch - wraps unexpected failures in AIAnthropicResponseHandlerException; logging left to the caller.
*/

public without sharing class AIAnthropicResponseHandler implements IAIProviderResponseHandler {

    public class AIAnthropicResponseHandlerException extends Exception {}

    // previousToolCalls non-null: batches every tool result from the prior iteration into one user-role message. anthropicHttpResponse non-null: parses it and appends the assistant's content array as-is.
    public AIAgentManager.Response handleResponse(List<Map<String, Object>> providerMessages, HttpResponse anthropicHttpResponse, List<AIAgentManager.ToolCall> previousToolCalls, List<Object> previousToolResults) {

        try {

            // Tool results - Anthropic expects every result from one assistant turn in a single user-role message, one tool_result block per tool_use id.
            if (previousToolCalls != null) {

                if (previousToolResults == null || previousToolResults.size() != previousToolCalls.size()) throw new AIAnthropicResponseHandlerException('Tool result count does not match tool call count - every tool_use block needs exactly one tool_result.');

                // One tool_result block per tool call - tool_use_id echoes the tool_use block's id so Anthropic can pair each output with its request.
                List<Object> toolResultBlocks = new List<Object>();

                for (Integer toolIndex = 0; toolIndex < previousToolCalls.size(); toolIndex++) {
                    toolResultBlocks.add( new Map<String, Object>{ AIAssistApplicationConstants.ANTHROPIC_FIELD_BLOCK_TYPE => AIAssistApplicationConstants.ANTHROPIC_BLOCK_TYPE_TOOL_RESULT, AIAssistApplicationConstants.ANTHROPIC_FIELD_TOOL_RESULT_ID => previousToolCalls[toolIndex].id, AIAssistApplicationConstants.ANTHROPIC_FIELD_CONTENT => AIAgentManager.stringifyToolResult(previousToolResults[toolIndex]) } );
                }

                // Tool results go back as a user-role message (Anthropic has no separate "tool" role, unlike OpenAI) - all blocks in one message, never split across several.
                providerMessages.add(new Map<String, Object>{ AIAssistApplicationConstants.ANTHROPIC_ROLE_KEY => AIAssistApplicationConstants.ANTHROPIC_ROLE_USER, AIAssistApplicationConstants.ANTHROPIC_FIELD_CONTENT => toolResultBlocks });
            }

            if (anthropicHttpResponse == null) return null;

            String rawResponseBody = anthropicHttpResponse.getBody();

            // Status not in AIAssistSettings__c.AIProviderSuccessStatusCodes__c - expose Anthropic's error, e.g. { "type": "error", "error": { "type": "invalid_request_error", "message": "..." } }, falling back to the raw body.
            if (!AIAssistSettingsService.getAIProviderSuccessStatusCodes().contains(anthropicHttpResponse.getStatusCode())) {

                String providerErrorDetail = rawResponseBody;
                Boolean isJsonObjectBody = String.isNotBlank(rawResponseBody) && rawResponseBody.trim().startsWith('{') && rawResponseBody.trim().endsWith('}');
                Object errorResponseBody = isJsonObjectBody ? JSON.deserializeUntyped(rawResponseBody) : null;
                Object errorDetails = errorResponseBody instanceof Map<String, Object> ? ((Map<String, Object>) errorResponseBody).get(AIAssistApplicationConstants.ANTHROPIC_FIELD_ERROR) : null;

                if (errorDetails instanceof Map<String, Object>) {
                    Object providerErrorType = ((Map<String, Object>) errorDetails).get(AIAssistApplicationConstants.ANTHROPIC_FIELD_ERROR_TYPE);
                    Object providerErrorMessage = ((Map<String, Object>) errorDetails).get(AIAssistApplicationConstants.ANTHROPIC_FIELD_ERROR_MESSAGE);
                    if (providerErrorMessage != null) providerErrorDetail = (providerErrorType == null ? '' : providerErrorType + ' - ') + providerErrorMessage;
                }

                throw new AIAnthropicResponseHandlerException('AI provider returned HTTP ' + anthropicHttpResponse.getStatusCode() + ': ' + providerErrorDetail);
            }

            // Parse the successful response body
            Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(rawResponseBody);
            List<Object> contentBlocks = (List<Object>) responseBody.get(AIAssistApplicationConstants.ANTHROPIC_FIELD_CONTENT);

            if (contentBlocks == null) contentBlocks = new List<Object>();

            AIAgentManager.Response agentResponse = new AIAgentManager.Response();
            List<String> responseTextLines = new List<String>();

            // Text blocks become the reply text, tool_use blocks become tool calls - any other block type is ignored here
            for (Object contentBlockObject : contentBlocks) {

                Map<String, Object> contentBlock = (Map<String, Object>) contentBlockObject;
                String contentBlockType = (String) contentBlock.get(AIAssistApplicationConstants.ANTHROPIC_FIELD_BLOCK_TYPE);

                if (contentBlockType == AIAssistApplicationConstants.ANTHROPIC_BLOCK_TYPE_TEXT) {
                    String blockText = (String) contentBlock.get(AIAssistApplicationConstants.ANTHROPIC_FIELD_TEXT);
                    responseTextLines.add(blockText);
                }

                if (contentBlockType == AIAssistApplicationConstants.ANTHROPIC_BLOCK_TYPE_TOOL_USE) {
                    Map<String, Object> toolArguments = (Map<String, Object>) contentBlock.get(AIAssistApplicationConstants.ANTHROPIC_FIELD_TOOL_USE_INPUT);

                    AIAgentManager.ToolCall toolCall = new AIAgentManager.ToolCall();
                    toolCall.id = (String) contentBlock.get(AIAssistApplicationConstants.ANTHROPIC_FIELD_TOOL_USE_ID);
                    toolCall.name = (String) contentBlock.get(AIAssistApplicationConstants.ANTHROPIC_FIELD_TOOL_NAME);
                    toolCall.arguments = toolArguments != null ? toolArguments : new Map<String, Object>();

                    agentResponse.toolCalls.add(toolCall);
                }
            }

            agentResponse.textContent = String.join(responseTextLines, '\n');

            // Total tokens = input tokens + output tokens (missing values count as 0)
            Map<String, Object> tokenUsage = (Map<String, Object>) responseBody.get(AIAssistApplicationConstants.ANTHROPIC_FIELD_USAGE);

            if (tokenUsage != null) {
                Integer inputTokens = (Integer) tokenUsage.get(AIAssistApplicationConstants.ANTHROPIC_FIELD_USAGE_INPUT_TOKENS);
                Integer outputTokens = (Integer) tokenUsage.get(AIAssistApplicationConstants.ANTHROPIC_FIELD_USAGE_OUTPUT_TOKENS);

                agentResponse.totalTokens = (inputTokens != null ? inputTokens : 0) + (outputTokens != null ? outputTokens : 0);
            }

            // Add the assistant's reply to the conversation exactly as Anthropic returned it, so the next request includes it
            providerMessages.add(new Map<String, Object>{
                AIAssistApplicationConstants.ANTHROPIC_ROLE_KEY => AIAssistApplicationConstants.ANTHROPIC_ROLE_ASSISTANT,
                AIAssistApplicationConstants.ANTHROPIC_FIELD_CONTENT => contentBlocks
            });

            return agentResponse;

        } catch (Exception ex) {
            // Not logged here - AIAgentManager.executeAiMessage handles and logs it, so it's logged exactly once. This handler's own exceptions (count mismatch, provider HTTP error) already carry a user-facing message and are rethrown as-is; anything unexpected (malformed JSON, bad cast) is wrapped with the original as its cause.
            if (ex instanceof AIAnthropicResponseHandlerException) throw ex;
            throw new AIAnthropicResponseHandlerException('Failed to handle the Anthropic response: ' + ex.getMessage(), ex);
        }
    }
}