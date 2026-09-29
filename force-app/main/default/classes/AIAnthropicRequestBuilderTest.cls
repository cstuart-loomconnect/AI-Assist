/*
Class Name: AIAnthropicRequestBuilderTest

=================================================================
=================================================================

Description: Testing utility for AIAnthropicRequestBuilder.

=================================================================
=================================================================
Applicable Classes:

AIAnthropicRequestBuilder: Coverage 100%

Version      Date               Author                   Description
1.0          2026-09-26         Chandler Stuart          Initial development
1.1          2026-09-27         Chandler Stuart          Canonical types moved from AIAgentManager to AIProvider.
*/

@IsTest private class AIAnthropicRequestBuilderTest {

    // testScenario1: A fully populated request builds model, max_tokens, messages, temperature, a top-level system field, and one flat { name, description, input_schema } entry per tool.
    // testScenario2: A request with only the required fields omits temperature, system and tools entirely - a blank system prompt and an empty tool list are treated the same as null.
    // testScenario3: A null request is caught and rethrown as AIAnthropicRequestBuilderException.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        Map<String, Object> inputSchema = new Map<String, Object>{
            'type' => 'object',
            'properties' => new Map<String, Object>{ 'accountName' => new Map<String, Object>{ 'type' => 'string' } }
        };

        AIProvider.Request request = buildRequest();
        request.temperature = 0.7;
        request.systemPromptText = 'You are a helpful Salesforce assistant.';
        request.tools = new List<AIProvider.ToolDefinition>{ buildToolDefinition('getAccount', inputSchema), buildToolDefinition('getContact', new Map<String, Object>()) };

        Test.startTest();
            Map<String, Object> requestBody = new AIAnthropicRequestBuilder().buildRequestBody(request);
        Test.stopTest();

        Assert.areEqual('claude-sonnet-5', requestBody.get('model'), 'model should be the request\'s model identifier.');
        Assert.areEqual(1024, requestBody.get('max_tokens'), 'max_tokens should be the request\'s max output tokens.');
        Assert.areEqual(request.messages, requestBody.get('messages'), 'messages should be passed through unchanged.');
        Assert.areEqual(0.7, requestBody.get('temperature'), 'temperature should be set when the request has one.');
        Assert.areEqual('You are a helpful Salesforce assistant.', requestBody.get('system'), 'The system prompt should be a top-level system field.');

        List<Object> toolDefinitions = (List<Object>) requestBody.get('tools');
        Assert.areEqual(2, toolDefinitions.size(), 'There should be one tool definition per tool.');

        Map<String, Object> firstTool = (Map<String, Object>) toolDefinitions[0];
        Assert.areEqual('getAccount', firstTool.get('name'), 'Tool name should echo the tool definition name.');
        Assert.areEqual('Description for getAccount', firstTool.get('description'), 'Tool description should echo the tool definition description.');
        Assert.areEqual(inputSchema, firstTool.get('input_schema'), 'input_schema should be the tool definition input schema.');
        Assert.isFalse(firstTool.containsKey('function'), 'Anthropic tools should be flat, with no OpenAI-style function wrapper.');
        Assert.areEqual('getContact', ((Map<String, Object>) toolDefinitions[1]).get('name'), 'Tool order should be preserved.');
    }

    @IsTest static void testScenario2() {

        AIProvider.Request requestWithNulls = buildRequest();

        AIProvider.Request requestWithBlanks = buildRequest();
        requestWithBlanks.systemPromptText = '   ';
        requestWithBlanks.tools = new List<AIProvider.ToolDefinition>();

        Test.startTest();
            Map<String, Object> requestBodyWithNulls = new AIAnthropicRequestBuilder().buildRequestBody(requestWithNulls);
            Map<String, Object> requestBodyWithBlanks = new AIAnthropicRequestBuilder().buildRequestBody(requestWithBlanks);
        Test.stopTest();

        for (Map<String, Object> requestBody : new List<Map<String, Object>>{ requestBodyWithNulls, requestBodyWithBlanks }) {
            Assert.areEqual(new Set<String>{ 'model', 'max_tokens', 'messages' }, requestBody.keySet(), 'Only the required fields should be present.');
            Assert.isFalse(requestBody.containsKey('temperature'), 'temperature should be omitted, never sent as null.');
            Assert.isFalse(requestBody.containsKey('system'), 'system should be omitted when the system prompt is null or blank.');
            Assert.isFalse(requestBody.containsKey('tools'), 'tools should be omitted when there are no tools.');
        }
    }

    @IsTest static void testScenario3() {

        Test.startTest();
            try {
                new AIAnthropicRequestBuilder().buildRequestBody(null);
                Assert.fail('A null request should have thrown.');
            } catch (AIAnthropicRequestBuilder.AIAnthropicRequestBuilderException ex) {
                Assert.isTrue(ex.getMessage().startsWith('Failed to build the Anthropic request body: '), 'Error should explain the request body could not be built.');
                Assert.isInstanceOfType(ex.getCause(), NullPointerException.class, 'The original exception should be preserved as the cause.');
            }
        Test.stopTest();
    }

    private static AIProvider.Request buildRequest() {
        AIProvider.Request request = new AIProvider.Request();
        request.modelIdentifier = 'claude-sonnet-5';
        request.maxOutputTokens = 1024;
        request.messages = new List<Map<String, Object>>{ new Map<String, Object>{ 'role' => 'user', 'content' => 'Find the Acme account.' } };
        return request;
    }

    private static AIProvider.ToolDefinition buildToolDefinition(String toolName, Map<String, Object> inputSchema) {
        AIProvider.ToolDefinition tool = new AIProvider.ToolDefinition();
        tool.name = toolName;
        tool.description = 'Description for ' + toolName;
        tool.inputSchema = inputSchema;
        return tool;
    }
}