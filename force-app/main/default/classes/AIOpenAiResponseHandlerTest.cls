/*
Class Name: AIOpenAiResponseHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIOpenAiResponseHandler.

=================================================================
=================================================================
Applicable Classes:

AIOpenAiResponseHandler: Coverage 100%

Version      Date               Author                   Description
1.0          2026-09-27         Chandler Stuart          Initial development
1.1          2026-09-27         Chandler Stuart          Canonical types moved from AIAgentManager to AIProvider.
*/

@IsTest private class AIOpenAiResponseHandlerTest {

    // testScenario1: A successful response parses choices[0].message content into textContent, tool_calls into tool calls (deserializing the arguments JSON string), reads usage.total_tokens, and appends the assistant's message object to providerMessages.
    // testScenario2: Prior tool results are added as one tool-role message per tool call keyed by tool_call_id, and a null HttpResponse returns null.
    // testScenario3: A tool result count that doesn't match the tool call count throws AIOpenAiResponseHandlerException.
    // testScenario4: A non-success status throws AIOpenAiResponseHandlerException - exposing OpenAI's error type and message for a JSON body, falling back to the raw body otherwise.
    // testScenario5: An unexpected failure (malformed JSON on a success status) is caught and rethrown as AIOpenAiResponseHandlerException with the original exception as its cause.
    // testScenario6: A tool-only turn (null content, blank arguments, no usage) returns empty text, empty arguments and 0 tokens; a response with no choices or a choice with no message throws AIOpenAiResponseHandlerException.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = true;
        settings.DisableExceptionLogging__c = false;
        settings.AIProviderSuccessStatusCodes__c = '200';
        upsert settings;
    }

    @IsTest static void testScenario1() {

        String responseBody = JSON.serialize(new Map<String, Object>{
            'choices' => new List<Object>{
                new Map<String, Object>{ 'index' => 0, 'message' => new Map<String, Object>{
                    'role' => 'assistant',
                    'content' => 'Looking that up.',
                    'tool_calls' => new List<Object>{
                        new Map<String, Object>{ 'id' => 'call_01', 'type' => 'function', 'function' => new Map<String, Object>{ 'name' => 'getAccount', 'arguments' => '{"accountName":"Acme"}' } }
                    }
                } }
            },
            'usage' => new Map<String, Object>{ 'prompt_tokens' => 120, 'completion_tokens' => 30, 'total_tokens' => 150 }
        });

        List<Map<String, Object>> providerMessages = new List<Map<String, Object>>();

        Test.startTest();
            AIProvider.Response agentResponse = new AIOpenAiResponseHandler().handleResponse(providerMessages, buildHttpResponse(200, responseBody), null, null);
        Test.stopTest();

        Assert.areEqual('Looking that up.', agentResponse.textContent, 'Message content should become the reply text.');
        Assert.areEqual(1, agentResponse.toolCalls.size(), 'The tool_calls entry should become one tool call.');
        Assert.areEqual('call_01', agentResponse.toolCalls[0].id, 'Tool call id should echo the tool_calls entry id.');
        Assert.areEqual('getAccount', agentResponse.toolCalls[0].name, 'Tool call name should echo the function name.');
        Assert.areEqual('Acme', agentResponse.toolCalls[0].arguments.get('accountName'), 'Tool call arguments should be the deserialized arguments JSON string.');
        Assert.areEqual(150, agentResponse.totalTokens, 'Total tokens should come from usage.total_tokens.');
        Assert.areEqual(1, providerMessages.size(), 'The assistant turn should be appended to providerMessages.');
        Assert.areEqual('assistant', providerMessages[0].get('role'), 'The appended message should be assistant-role.');
        Assert.areEqual(1, ((List<Object>) providerMessages[0].get('tool_calls')).size(), 'The assistant message should be appended as-is, tool_calls included.');
    }

    @IsTest static void testScenario2() {

        List<AIProvider.ToolCall> previousToolCalls = new List<AIProvider.ToolCall>{ buildToolCall('call_01'), buildToolCall('call_02') };
        List<Object> previousToolResults = new List<Object>{ 'plain text result', new Map<String, Object>{ 'Name' => 'Acme' } };
        List<Map<String, Object>> providerMessages = new List<Map<String, Object>>();

        Test.startTest();
            AIProvider.Response agentResponse = new AIOpenAiResponseHandler().handleResponse(providerMessages, null, previousToolCalls, previousToolResults);
        Test.stopTest();

        Assert.isNull(agentResponse, 'A null HttpResponse should return null.');
        Assert.areEqual(2, providerMessages.size(), 'There should be one tool-role message per tool call.');

        Assert.areEqual('tool', providerMessages[0].get('role'), 'Tool results should go back as tool-role messages.');
        Assert.areEqual('call_01', providerMessages[0].get('tool_call_id'), 'tool_call_id should echo the matching tool call id.');
        Assert.areEqual('plain text result', providerMessages[0].get('content'), 'A String result should be passed through unchanged.');
        Assert.areEqual('tool', providerMessages[1].get('role'), 'Tool results should go back as tool-role messages.');
        Assert.areEqual('call_02', providerMessages[1].get('tool_call_id'), 'tool_call_id should echo the matching tool call id.');
        Assert.areEqual(JSON.serialize(new Map<String, Object>{ 'Name' => 'Acme' }), providerMessages[1].get('content'), 'A non-String result should be serialized to JSON.');
    }

    @IsTest static void testScenario3() {

        List<AIProvider.ToolCall> previousToolCalls = new List<AIProvider.ToolCall>{ buildToolCall('call_01'), buildToolCall('call_02') };
        List<Object> previousToolResults = new List<Object>{ 'only one result' };

        Test.startTest();
            try {
                new AIOpenAiResponseHandler().handleResponse(new List<Map<String, Object>>(), null, previousToolCalls, previousToolResults);
                Assert.fail('A tool result count that doesn\'t match the tool call count should have thrown.');
            } catch (AIOpenAiResponseHandler.AIOpenAiResponseHandlerException ex) {
                Assert.isTrue(ex.getMessage().contains('does not match tool call count'), 'Error should explain the count mismatch.');
            }
        Test.stopTest();
    }

    @IsTest static void testScenario4() {

        String jsonErrorBody = JSON.serialize(new Map<String, Object>{
            'error' => new Map<String, Object>{ 'type' => 'invalid_request_error', 'message' => 'max_tokens is too large', 'param' => 'max_tokens', 'code' => null }
        });

        Test.startTest();

            try {
                new AIOpenAiResponseHandler().handleResponse(new List<Map<String, Object>>(), buildHttpResponse(400, jsonErrorBody), null, null);
                Assert.fail('A non-success status should have thrown.');
            } catch (AIOpenAiResponseHandler.AIOpenAiResponseHandlerException ex) {
                Assert.areEqual('AI provider returned HTTP 400: invalid_request_error - max_tokens is too large', ex.getMessage(), 'Error should expose OpenAI\'s error type and message.');
            }

            try {
                new AIOpenAiResponseHandler().handleResponse(new List<Map<String, Object>>(), buildHttpResponse(503, 'Service Unavailable'), null, null);
                Assert.fail('A non-success status should have thrown.');
            } catch (AIOpenAiResponseHandler.AIOpenAiResponseHandlerException ex) {
                Assert.areEqual('AI provider returned HTTP 503: Service Unavailable', ex.getMessage(), 'Error should fall back to the raw body when it isn\'t JSON.');
            }

        Test.stopTest();
    }

    @IsTest static void testScenario5() {

        Test.startTest();
            try {
                new AIOpenAiResponseHandler().handleResponse(new List<Map<String, Object>>(), buildHttpResponse(200, '{ not valid json'), null, null);
                Assert.fail('A malformed success body should have thrown.');
            } catch (AIOpenAiResponseHandler.AIOpenAiResponseHandlerException ex) {
                Assert.isTrue(ex.getMessage().startsWith('Failed to handle the OpenAI response: '), 'Error should explain the response could not be handled.');
                Assert.isInstanceOfType(ex.getCause(), JSONException.class, 'The original exception should be preserved as the cause.');
            }
        Test.stopTest();
    }

    @IsTest static void testScenario6() {

        String toolOnlyBody = JSON.serialize(new Map<String, Object>{
            'choices' => new List<Object>{
                new Map<String, Object>{ 'message' => new Map<String, Object>{
                    'role' => 'assistant',
                    'content' => null,
                    'tool_calls' => new List<Object>{
                        new Map<String, Object>{ 'id' => 'call_01', 'type' => 'function', 'function' => new Map<String, Object>{ 'name' => 'getAccount', 'arguments' => '' } }
                    }
                } }
            }
        });

        String noChoicesBody = JSON.serialize(new Map<String, Object>{ 'choices' => new List<Object>() });
        String noMessageBody = JSON.serialize(new Map<String, Object>{ 'choices' => new List<Object>{ new Map<String, Object>{ 'index' => 0 } } });

        Test.startTest();

            AIProvider.Response agentResponse = new AIOpenAiResponseHandler().handleResponse(new List<Map<String, Object>>(), buildHttpResponse(200, toolOnlyBody), null, null);

            try {
                new AIOpenAiResponseHandler().handleResponse(new List<Map<String, Object>>(), buildHttpResponse(200, noChoicesBody), null, null);
                Assert.fail('A response with no choices should have thrown.');
            } catch (AIOpenAiResponseHandler.AIOpenAiResponseHandlerException ex) {
                Assert.areEqual('OpenAI response contained no choices.', ex.getMessage(), 'Error should explain there were no choices.');
            }

            try {
                new AIOpenAiResponseHandler().handleResponse(new List<Map<String, Object>>(), buildHttpResponse(200, noMessageBody), null, null);
                Assert.fail('A choice with no message should have thrown.');
            } catch (AIOpenAiResponseHandler.AIOpenAiResponseHandlerException ex) {
                Assert.areEqual('OpenAI response choice contained no message.', ex.getMessage(), 'Error should explain the choice had no message.');
            }

        Test.stopTest();

        Assert.areEqual('', agentResponse.textContent, 'Null content should become empty reply text.');
        Assert.areEqual(1, agentResponse.toolCalls.size(), 'The tool_calls entry should still become one tool call.');
        Assert.isTrue(agentResponse.toolCalls[0].arguments.isEmpty(), 'Blank arguments should become an empty map.');
        Assert.areEqual(0, agentResponse.totalTokens, 'A missing usage block should leave total tokens at 0.');
    }

    private static HttpResponse buildHttpResponse(Integer statusCode, String body) {
        HttpResponse httpResponse = new HttpResponse();
        httpResponse.setStatusCode(statusCode);
        httpResponse.setBody(body);
        return httpResponse;
    }

    private static AIProvider.ToolCall buildToolCall(String toolCallId) {
        AIProvider.ToolCall toolCall = new AIProvider.ToolCall();
        toolCall.id = toolCallId;
        toolCall.name = 'getAccount';
        toolCall.arguments = new Map<String, Object>();
        return toolCall;
    }
}