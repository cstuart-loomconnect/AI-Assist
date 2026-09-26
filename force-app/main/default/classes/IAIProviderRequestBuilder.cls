/*
Class Name: IAIProviderRequestBuilder

=================================================================
=================================================================

Description: Contract for shaping one AI provider's request body, implemented per provider
(e.g. AIAnthropicRequestBuilder) - kept separate from IAIProviderResponseHandler since building
a request and handling a response are different jobs. Endpoint path and API version header
aren't part of this contract - they vary per deployment (e.g. Azure OpenAI vs. OpenAI directly),
not per provider brand, so they live on AIModelConfiguration__c instead.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-26     Chandler Stuart          Initial development
*/

public interface IAIProviderRequestBuilder {

    // Converts the canonical request into this provider's exact JSON-ready body.
    Map<String, Object> buildRequestBody(AIAgentManager.Request request);
}