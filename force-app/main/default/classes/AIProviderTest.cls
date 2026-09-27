/*
Class Name: AIProviderTest

=================================================================
=================================================================

Description: Testing utility for the AIProvider class.

=================================================================
=================================================================
Applicable Classes:

AIProvider: Coverage 100%

Version      Date               Author                   Description
1.0          2026-09-27         Chandler Stuart          Initial development
*/

@IsTest private class AIProviderTest {

    // testScenario1: Each supported provider resolves to its own request builder and response handler, matched case-insensitively.
    // testScenario2: A blank or unknown provider is unsupported, and asking for its builder or handler throws AIProviderException.
    // testScenario3: stringifyToolResult passes a String through untouched and JSON-serializes anything else.

    @IsTest static void testScenario1() {

        Test.startTest();
            Boolean isAnthropicSupported = AIProvider.isSupported(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC.toUpperCase());
            IAIProviderRequestBuilder anthropicRequestBuilder = AIProvider.getRequestBuilder(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC);
            IAIProviderResponseHandler anthropicResponseHandler = AIProvider.getResponseHandler(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC);
            IAIProviderRequestBuilder openAiRequestBuilder = AIProvider.getRequestBuilder(AIAssistApplicationConstants.AI_PROVIDER_OPEN_AI.toLowerCase());
            IAIProviderResponseHandler openAiResponseHandler = AIProvider.getResponseHandler(AIAssistApplicationConstants.AI_PROVIDER_OPEN_AI);
        Test.stopTest();

        Assert.isTrue(isAnthropicSupported, 'Anthropic should be supported, whatever its case.');
        Assert.isTrue(anthropicRequestBuilder instanceof AIAnthropicRequestBuilder, 'Anthropic should use AIAnthropicRequestBuilder.');
        Assert.isTrue(anthropicResponseHandler instanceof AIAnthropicResponseHandler, 'Anthropic should use AIAnthropicResponseHandler.');
        Assert.isTrue(openAiRequestBuilder instanceof AIOpenAiRequestBuilder, 'Open AI should use AIOpenAiRequestBuilder, whatever its case.');
        Assert.isTrue(openAiResponseHandler instanceof AIOpenAiResponseHandler, 'Open AI should use AIOpenAiResponseHandler.');
    }

    @IsTest static void testScenario2() {

        Boolean isRequestBuilderRejected = false;
        Boolean isResponseHandlerRejected = false;

        Test.startTest();
            Boolean isBlankSupported = AIProvider.isSupported(null);
            Boolean isUnknownSupported = AIProvider.isSupported('Unknown Provider');

            try {
                AIProvider.getRequestBuilder('Unknown Provider');
            } catch (AIProvider.AIProviderException ex) {
                isRequestBuilderRejected = true;
            }

            try {
                AIProvider.getResponseHandler(null);
            } catch (AIProvider.AIProviderException ex) {
                isResponseHandlerRejected = true;
            }
        Test.stopTest();

        Assert.isFalse(isBlankSupported, 'A blank provider should not be supported.');
        Assert.isFalse(isUnknownSupported, 'An unknown provider should not be supported.');
        Assert.isTrue(isRequestBuilderRejected, 'An unknown provider should have no request builder.');
        Assert.isTrue(isResponseHandlerRejected, 'A blank provider should have no response handler.');
    }

    @IsTest static void testScenario3() {

        Test.startTest();
            String stringResult = AIProvider.stringifyToolResult('Plain text result');
            String listResult = AIProvider.stringifyToolResult(new List<Object>{ new Map<String, Object>{ 'Name' => 'Acme' } });
        Test.stopTest();

        Assert.areEqual('Plain text result', stringResult, 'A String should pass through untouched.');
        Assert.areEqual('[{"Name":"Acme"}]', listResult, 'Anything else should be JSON-serialized.');
    }
}