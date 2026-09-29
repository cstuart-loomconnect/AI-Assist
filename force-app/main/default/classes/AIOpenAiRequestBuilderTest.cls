/*
Class Name: AIOpenAiRequestBuilderTest

=================================================================
=================================================================

Description: Testing utility for AIOpenAiRequestBuilder.

=================================================================
=================================================================
Applicable Classes:

AIOpenAiRequestBuilder: Coverage 100%

Version      Date               Author                   Description
1.0          2026-09-27         Chandler Stuart          Initial development
1.1          2026-09-27         Chandler Stuart          Canonical types moved from AIAgentManager to AIProvider.
*/

@IsTest private class AIOpenAiRequestBuilderTest {

    // testScenario1: A fully populated request builds model, max_tokens, messages (system-role message first), temperature, and one { type: "function", function: { name, description, parameters } } entry per tool.
    // testScenario2: A request with only the required fields omits temperature and tools entirely and adds no system message - a blank system prompt and an empty tool list are treated the same as null.
    // testScenario3: A null request is caught and rethrown as AIOpenAiRequestBuilderException.

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
            Map<String, Object> requestBody = new AIOpenAiRequestBuilder().buildRequestBody(request);
        Test.stopTest();

        Assert.areEqual('gpt-5', requestBody.get('model'), 'model should be the request\'s model identifier.');
        Assert.areEqual(1024, requestBody.get('max_tokens'), 'max_tokens should be the request\'s max output tokens.');
        Assert.areEqual(0.7, requestBody.get('temperature'), 'temperature should be set when the request has one.');
        Assert.isFalse(requestBody.containsKey('system'), 'OpenAI has no top-level system field - the system prompt should be a message instead.');

        List<Map<String, Object>> messages = (List<Map<String, Object>>) requestBody.get('messages');
        Assert.areEqual(2, messages.size(), 'messages should be the system message followed by the request\'s messages.');
        Assert.areEqual('system', messages[0].get('role'), 'The first message should be a system-role message.');
        Assert.areEqual('You are a helpful Salesforce assistant.', messages[0].get('content'), 'The system message content should be the system prompt.');
        Assert.areEqual(request.messages[0], messages[1], 'The request\'s messages should follow the system message unchanged.');

        List<Object> toolDefinitions = (List<Object>) requestBody.get('tools');
        Assert.areEqual(2, toolDefinitions.size(), 'There should be one tool definition per tool.');

        Map<String, Object> firstTool = (Map<String, Object>) toolDefinitions[0];
        Assert.areEqual('function', firstTool.get('type'), 'Each tool should have type "function".');

        Map<String, Object> firstToolFunction = (Map<String, Object>) firstTool.get('function');
        Assert.areEqual('getAccount', firstToolFunction.get('name'), 'Tool name should echo the tool definition name.');
        Assert.areEqual('Description for getAccount', firstToolFunction.get('description'), 'Tool description should echo the tool definition description.');
        Assert.areEqual(inputSchema, firstToolFunction.get('parameters'), 'parameters should be the tool definition input schema.');
        Assert.isFalse(firstTool.containsKey('name'), 'OpenAI tools should be wrapped in a function object, not flat like Anthropic.');
        Assert.areEqual('getContact', ((Map<String, Object>) ((Map<String, Object>) toolDefinitions[1]).get('function')).get('name'), 'Tool order should be preserved.');
    }

    @IsTest static void testScenario2() {

        AIProvider.Request requestWithNulls = buildRequest();

        AIProvider.Request requestWithBlanks = buildRequest();
        requestWithBlanks.systemPromptText = '   ';
        requestWithBlanks.tools = new List<AIProvider.ToolDefinition>();

        Test.startTest();
            Map<String, Object> requestBodyWithNulls = new AIOpenAiRequestBuilder().buildRequestBody(requestWithNulls);
            Map<String, Object> requestBodyWithBlanks = new AIOpenAiRequestBuilder().buildRequestBody(requestWithBlanks);
        Test.stopTest();

        for (Map<String, Object> requestBody : new List<Map<String, Object>>{ requestBodyWithNulls, requestBodyWithBlanks }) {
            Assert.areEqual(new Set<String>{ 'model', 'max_tokens', 'messages' }, requestBody.keySet(), 'Only the required fields should be present.');
            Assert.isFalse(requestBody.containsKey('temperature'), 'temperature should be omitted, never sent as null.');
            Assert.isFalse(requestBody.containsKey('tools'), 'tools should be omitted when there are no tools.');
            Assert.areEqual(requestWithNulls.messages, requestBody.get('messages'), 'No system message should be added when the system prompt is null or blank.');
        }
    }

    @IsTest static void testScenario3() {

        Test.startTest();
            try {
                new AIOpenAiRequestBuilder().buildRequestBody(null);
                Assert.fail('A null request should have thrown.');
            } catch (AIOpenAiRequestBuilder.AIOpenAiRequestBuilderException ex) {
                Assert.isTrue(ex.getMessage().startsWith('Failed to build the OpenAI request body: '), 'Error should explain the request body could not be built.');
                Assert.isInstanceOfType(ex.getCause(), NullPointerException.class, 'The original exception should be preserved as the cause.');
            }
        Test.stopTest();
    }

    private static AIProvider.Request buildRequest() {
        AIProvider.Request request = new AIProvider.Request();
        request.modelIdentifier = 'gpt-5';
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