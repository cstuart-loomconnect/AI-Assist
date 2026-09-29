/*
Class Name: AIPiiRegistryWorkerTest

=================================================================
=================================================================

Description: Testing utility for the AIPiiRegistryWorker future worker.

=================================================================
=================================================================
Applicable Classes:

AIPiiRegistryWorker: Coverage 100%

Version      Date               Author                   Description
1.0          2026-09-14         Chandler Stuart          Initial development
*/

@IsTest private class AIPiiRegistryWorkerTest {

    // testScenario1: A successful sync upserts one AIPIIFieldMetadata__c per returned field (deriving IsPII__c from ComplianceGroup, skipping blank API names) and marks the registry Synced.
    // testScenario2: A non-200 Tooling API response marks the registry Failed and logs the exception.
    // testScenario3: The Tooling API callout uses AIAssistSettings__c.ToolingAPIVersion__c when it's set.
    // testScenario4: The Tooling API callout falls back to the code default API version when ToolingAPIVersion__c is blank.
    // testScenario5: The Tooling API query is bounded by AIPIIRegistry__c.MaxFieldsToQuery__c when it's set.
    // testScenario6: The Tooling API query falls back to the code default field ceiling when MaxFieldsToQuery__c is blank, so a sync can never be unbounded.
    // testScenario7: Platform Limit guard - when no callout headroom remains in the transaction, the worker skips the callout entirely and marks the registry Failed.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        upsert settings;
    }

    private class ToolingAPIMock implements HttpCalloutMock {

        public Integer statusCode = 200;
        public String responseBody = '{"records":[]}';
        public HttpRequest capturedRequest;

        public HttpResponse respond(HttpRequest request) {

            capturedRequest = request;

            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setBody(responseBody);
            return response;
        }
    }

    private static String fieldDefinitionsBody(List<Map<String, Object>> fields) {
        return JSON.serialize(new Map<String, Object>{ 'records' => fields });
    }

    @IsTest static void testScenario1() {

        AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(1, 'Account', true)[0];

        ToolingAPIMock mock = new ToolingAPIMock();
        mock.responseBody = fieldDefinitionsBody(new List<Map<String, Object>>{
            new Map<String, Object>{ 'QualifiedApiName' => 'Name', 'Label' => 'Account Name', 'DataType' => 'string', 'ComplianceGroup' => 'Name' },
            new Map<String, Object>{ 'QualifiedApiName' => 'Description', 'Label' => 'Description', 'DataType' => 'textarea', 'ComplianceGroup' => null },
            new Map<String, Object>{ 'QualifiedApiName' => '', 'Label' => 'Should be skipped', 'DataType' => 'string', 'ComplianceGroup' => null }
        });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
            AIPiiRegistryWorker.refreshPIIRegistry(registry.Id);
        Test.stopTest();

        AIPIIRegistry__c updated = [SELECT SyncStatus__c, LastSynced__c, CacheResetDate__c FROM AIPIIRegistry__c WHERE Id = :registry.Id];
        Assert.areEqual(AIAssistApplicationConstants.PII_SYNC_STATUS_SYNCED, updated.SyncStatus__c, 'A successful sync should mark the registry Synced.');
        Assert.isNotNull(updated.LastSynced__c, 'LastSynced__c should be set after a successful sync.');
        Assert.isNull(updated.CacheResetDate__c, 'CacheResetDate__c should be cleared after a successful sync.');

        Map<String, AIPIIFieldMetadata__c> fieldMetadataByKey = new Map<String, AIPIIFieldMetadata__c>();
        for (AIPIIFieldMetadata__c fieldMetadata : [SELECT FieldKey__c, IsPII__c FROM AIPIIFieldMetadata__c WHERE PIIRegistry__c = :registry.Id]) {
            fieldMetadataByKey.put(fieldMetadata.FieldKey__c, fieldMetadata);
        }

        Assert.areEqual(2, fieldMetadataByKey.size(), 'One AIPIIFieldMetadata__c should be upserted per field with a non-blank API name.');
        Assert.isTrue(fieldMetadataByKey.get('Account.Name').IsPII__c, 'A field with a Compliance Group should be marked IsPII__c.');
        Assert.isFalse(fieldMetadataByKey.get('Account.Description').IsPII__c, 'A field with no Compliance Group should not be marked IsPII__c.');
    }

    @IsTest static void testScenario2() {

        AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(1, 'Contact', true)[0];

        ToolingAPIMock mock = new ToolingAPIMock();
        mock.statusCode = 500;
        mock.responseBody = 'Internal Server Error';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
            AIPiiRegistryWorker.refreshPIIRegistry(registry.Id);
        Test.stopTest();

        AIPIIRegistry__c updated = [SELECT SyncStatus__c FROM AIPIIRegistry__c WHERE Id = :registry.Id];
        Assert.areEqual(AIAssistApplicationConstants.PII_SYNC_STATUS_FAILED, updated.SyncStatus__c, 'A non-200 Tooling API response should mark the registry Failed.');

        Integer platformLogCount = [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'AIPiiRegistryWorker' AND MethodName__c = 'refreshPIIRegistry'];
        Assert.areEqual(1, platformLogCount, 'The callout failure should be logged to AIPlatformLog__c.');
    }

    @IsTest static void testScenario3() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.ToolingAPIVersion__c = '58.0';
        upsert settings;

        AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(1, 'Lead', true)[0];

        ToolingAPIMock mock = new ToolingAPIMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
            AIPiiRegistryWorker.refreshPIIRegistry(registry.Id);
        Test.stopTest();

        Assert.isNotNull(mock.capturedRequest, 'The Tooling API callout should have been made.');
        Assert.isTrue(mock.capturedRequest.getEndpoint().contains('/services/data/v58.0/tooling/query/'), 'The callout should use the API version configured on AIAssistSettings__c.');
    }

    @IsTest static void testScenario4() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.ToolingAPIVersion__c = null;
        upsert settings;

        AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(1, 'Case', true)[0];

        ToolingAPIMock mock = new ToolingAPIMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
            AIPiiRegistryWorker.refreshPIIRegistry(registry.Id);
        Test.stopTest();

        Assert.isNotNull(mock.capturedRequest, 'The Tooling API callout should have been made.');
        Assert.isTrue(
            mock.capturedRequest.getEndpoint().contains('/services/data/v' + AIAssistApplicationConstants.DEFAULT_TOOLING_API_VERSION + '/tooling/query/'),
            'A blank ToolingAPIVersion__c should fall back to the code default API version.'
        );
    }

    @IsTest static void testScenario5() {

        AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(1, 'Opportunity', false)[0];
        registry.MaxFieldsToQuery__c = 50;
        insert registry;

        ToolingAPIMock mock = new ToolingAPIMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
            AIPiiRegistryWorker.refreshPIIRegistry(registry.Id);
        Test.stopTest();

        String decodedQuery = EncodingUtil.urlDecode(mock.capturedRequest.getEndpoint(), 'UTF-8');
        Assert.isTrue(decodedQuery.contains('LIMIT 50'), 'The Tooling API query should be bounded by MaxFieldsToQuery__c when it is set.');
    }

    @IsTest static void testScenario6() {

        AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(1, 'Task', true)[0];

        ToolingAPIMock mock = new ToolingAPIMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
            AIPiiRegistryWorker.refreshPIIRegistry(registry.Id);
        Test.stopTest();

        String decodedQuery = EncodingUtil.urlDecode(mock.capturedRequest.getEndpoint(), 'UTF-8');
        Assert.isTrue(
            decodedQuery.contains('LIMIT ' + AIAssistApplicationConstants.DEFAULT_MAX_PII_FIELDS_TO_QUERY),
            'A blank MaxFieldsToQuery__c should fall back to the code default field ceiling rather than leaving the query unbounded.'
        );
    }

    @IsTest static void testScenario7() {

        AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(1, 'Event', true)[0];

        ToolingAPIMock mock = new ToolingAPIMock();
        Test.setMock(HttpCalloutMock.class, mock);

        AIPiiRegistryWorker.isTestCalloutLimitReached = true;

        Test.startTest();
            AIPiiRegistryWorker.refreshPIIRegistry(registry.Id);
        Test.stopTest();

        Assert.isNull(mock.capturedRequest, 'No callout should be attempted once the Platform Limit guard reports no remaining callout headroom.');

        AIPIIRegistry__c updated = [SELECT SyncStatus__c FROM AIPIIRegistry__c WHERE Id = :registry.Id];
        Assert.areEqual(AIAssistApplicationConstants.PII_SYNC_STATUS_FAILED, updated.SyncStatus__c, 'Exhausted callout headroom should mark the registry Failed rather than let the callout throw.');
    }
}