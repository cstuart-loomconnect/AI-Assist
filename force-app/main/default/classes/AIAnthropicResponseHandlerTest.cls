/*
Class Name: AIAnthropicResponseHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIAnthropicResponseHandler.

=================================================================
=================================================================
Applicable Classes:

AIAnthropicResponseHandler: Coverage 100%

Version      Date               Author                   Description
1.0          2026-09-26         Chandler Stuart          Initial development
1.1          2026-09-27         Chandler Stuart          Canonical types moved from AIAgentManager to AIProvider.
*/

@IsTest private class AIAnthropicResponseHandlerTest {

    // testScenario1: A successful response parses text blocks into textContent, tool_use blocks into tool calls, sums input/output tokens, and appends the assistant's content array to providerMessages.
    // testScenario2: Prior tool results are batched into a single user-role message with one tool_result block per tool_use id, and a null HttpResponse returns null.
    // testScenario3: A tool result count that doesn't match the tool call count throws AIAnthropicResponseHandlerException.
    // testScenario4: A non-success status throws AIAnthropicResponseHandlerException - exposing Anthropic's error type and message for a JSON body, falling back to the raw body otherwise.
    // testScenario5: An unexpected failure (malformed JSON on a success status) is caught and rethrown as AIAnthropicResponseHandlerException with the original exception as its cause.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = true;
        settings.DisableExceptionLogging__c = false;
        settings.AIProviderSuccessStatusCodes__c = '200';
        upsert settings;
    }

    @IsTest static void testScenario1() {

        String responseBody = JSON.serialize(new Map<String, Object>{
            'content' => new List<Object>{
                new Map<String, Object>{ 'type' => 'text', 'text' => 'Looking that up.' },
                new Map<String, Object>{ 'type' => 'tool_use', 'id' => 'toolu_01', 'name' => 'getAccount', 'input' => new Map<String, Object>{ 'accountName' => 'Acme' } },
                new Map<String, Object>{ 'type' => 'text', 'text' => 'One moment.' }
            },
            'usage' => new Map<String, Object>{ 'input_tokens' => 120, 'output_tokens' => 30 }
        });

        List<Map<String, Object>> providerMessages = new List<Map<String, Object>>();

        Test.startTest();
            AIProvider.Response agentResponse = new AIAnthropicResponseHandler().handleResponse(providerMessages, buildHttpResponse(200, responseBody), null, null);
        Test.stopTest();

        Assert.areEqual('Looking that up.\nOne moment.', agentResponse.textContent, 'Text blocks should be joined with a newline.');
        Assert.areEqual(1, agentResponse.toolCalls.size(), 'The tool_use block should become one tool call.');
        Assert.areEqual('toolu_01', agentResponse.toolCalls[0].id, 'Tool call id should echo the tool_use block id.');
        Assert.areEqual('getAccount', agentResponse.toolCalls[0].name, 'Tool call name should echo the tool_use block name.');
        Assert.areEqual('Acme', agentResponse.toolCalls[0].arguments.get('accountName'), 'Tool call arguments should be the tool_use block input.');
        Assert.areEqual(150, agentResponse.totalTokens, 'Total tokens should be input tokens plus output tokens.');
        Assert.areEqual(1, providerMessages.size(), 'The assistant turn should be appended to providerMessages.');
        Assert.areEqual('assistant', providerMessages[0].get('role'), 'The appended message should be assistant-role.');
        Assert.areEqual(3, ((List<Object>) providerMessages[0].get('content')).size(), 'The assistant content array should be appended as-is.');
    }

    @IsTest static void testScenario2() {

        List<AIProvider.ToolCall> previousToolCalls = new List<AIProvider.ToolCall>{ buildToolCall('toolu_01'), buildToolCall('toolu_02') };
        List<Object> previousToolResults = new List<Object>{ 'plain text result', new Map<String, Object>{ 'Name' => 'Acme' } };
        List<Map<String, Object>> providerMessages = new List<Map<String, Object>>();

        Test.startTest();
            AIProvider.Response agentResponse = new AIAnthropicResponseHandler().handleResponse(providerMessages, null, previousToolCalls, previousToolResults);
        Test.stopTest();

        Assert.isNull(agentResponse, 'A null HttpResponse should return null.');
        Assert.areEqual(1, providerMessages.size(), 'Every tool result should be batched into a single message.');
        Assert.areEqual('user', providerMessages[0].get('role'), 'Tool results should go back as a user-role message.');

        List<Object> toolResultBlocks = (List<Object>) providerMessages[0].get('content');
        Assert.areEqual(2, toolResultBlocks.size(), 'There should be one tool_result block per tool call.');

        Map<String, Object> firstBlock = (Map<String, Object>) toolResultBlocks[0];
        Map<String, Object> secondBlock = (Map<String, Object>) toolResultBlocks[1];
        Assert.areEqual('tool_result', firstBlock.get('type'), 'Each block should be a tool_result block.');
        Assert.areEqual('toolu_01', firstBlock.get('tool_use_id'), 'tool_use_id should echo the matching tool call id.');
        Assert.areEqual('plain text result', firstBlock.get('content'), 'A String result should be passed through unchanged.');
        Assert.areEqual('toolu_02', secondBlock.get('tool_use_id'), 'tool_use_id should echo the matching tool call id.');
        Assert.areEqual(JSON.serialize(new Map<String, Object>{ 'Name' => 'Acme' }), secondBlock.get('content'), 'A non-String result should be serialized to JSON.');
    }

    @IsTest static void testScenario3() {

        List<AIProvider.ToolCall> previousToolCalls = new List<AIProvider.ToolCall>{ buildToolCall('toolu_01'), buildToolCall('toolu_02') };
        List<Object> previousToolResults = new List<Object>{ 'only one result' };

        Test.startTest();
            try {
                new AIAnthropicResponseHandler().handleResponse(new List<Map<String, Object>>(), null, previousToolCalls, previousToolResults);
                Assert.fail('A tool result count that doesn\'t match the tool call count should have thrown.');
            } catch (AIAnthropicResponseHandler.AIAnthropicResponseHandlerException ex) {
                Assert.isTrue(ex.getMessage().contains('does not match tool call count'), 'Error should explain the count mismatch.');
            }
        Test.stopTest();
    }

    @IsTest static void testScenario4() {

        String jsonErrorBody = JSON.serialize(new Map<String, Object>{
            'type' => 'error',
            'error' => new Map<String, Object>{ 'type' => 'invalid_request_error', 'message' => 'max_tokens is required' }
        });

        Test.startTest();

            try {
                new AIAnthropicResponseHandler().handleResponse(new List<Map<String, Object>>(), buildHttpResponse(400, jsonErrorBody), null, null);
                Assert.fail('A non-success status should have thrown.');
            } catch (AIAnthropicResponseHandler.AIAnthropicResponseHandlerException ex) {
                Assert.areEqual('AI provider returned HTTP 400: invalid_request_error - max_tokens is required', ex.getMessage(), 'Error should expose Anthropic\'s error type and message.');
            }

            try {
                new AIAnthropicResponseHandler().handleResponse(new List<Map<String, Object>>(), buildHttpResponse(503, 'Service Unavailable'), null, null);
                Assert.fail('A non-success status should have thrown.');
            } catch (AIAnthropicResponseHandler.AIAnthropicResponseHandlerException ex) {
                Assert.areEqual('AI provider returned HTTP 503: Service Unavailable', ex.getMessage(), 'Error should fall back to the raw body when it isn\'t JSON.');
            }

        Test.stopTest();
    }

    @IsTest static void testScenario5() {

        Test.startTest();
            try {
                new AIAnthropicResponseHandler().handleResponse(new List<Map<String, Object>>(), buildHttpResponse(200, '{ not valid json'), null, null);
                Assert.fail('A malformed success body should have thrown.');
            } catch (AIAnthropicResponseHandler.AIAnthropicResponseHandlerException ex) {
                Assert.isTrue(ex.getMessage().startsWith('Failed to handle the Anthropic response: '), 'Error should explain the response could not be handled.');
                Assert.isInstanceOfType(ex.getCause(), JSONException.class, 'The original exception should be preserved as the cause.');
            }
        Test.stopTest();
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