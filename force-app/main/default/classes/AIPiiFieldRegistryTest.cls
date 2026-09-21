/*
Class Name: AIPiiFieldRegistryTest

=================================================================
=================================================================

Description: Testing utility for the AIPiiFieldRegistry read-only lookup layer.

=================================================================
=================================================================
Applicable Classes:

AIPiiFieldRegistry: Coverage 100%

Version      Date               Author                   Description
1.0          2026-09-15         Chandler Stuart          Initial development
*/

@IsTest private class AIPiiFieldRegistryTest {

    // testScenario1: isPiiField/getFieldType return true/the stored type for a field flagged IsPII__c.
    // testScenario2: isPiiField/getFieldType return false/null for a field on the same object not flagged IsPII__c.
    // testScenario3: An unknown object or field returns false/null rather than throwing.
    // testScenario4: Repeated lookups against the same object reuse the cached result instead of querying again.

    @TestSetup static void setup() {

        AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(1, 'Contact', true)[0];

        AIAssistTestDataFactory.createAIPIIFieldMetadata(registry.Id, 'Contact', 'Email', 'Email', true, AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL, true);
        AIAssistTestDataFactory.createAIPIIFieldMetadata(registry.Id, 'Contact', 'Description', 'Description', false, null, true);
    }

    @IsTest static void testScenario1() {

        Test.startTest();
            Boolean isPii = AIPiiFieldRegistry.isPiiField('Contact', 'Email');
            String fieldType = AIPiiFieldRegistry.getFieldType('Contact', 'Email');
        Test.stopTest();

        Assert.isTrue(isPii, 'A field flagged IsPII__c should be reported as PII.');
        Assert.areEqual(AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL, fieldType, 'getFieldType should return the stored PIIFieldType__c.');
    }

    @IsTest static void testScenario2() {

        Test.startTest();
            Boolean isPii = AIPiiFieldRegistry.isPiiField('Contact', 'Description');
            String fieldType = AIPiiFieldRegistry.getFieldType('Contact', 'Description');
        Test.stopTest();

        Assert.isFalse(isPii, 'A field not flagged IsPII__c should not be reported as PII.');
        Assert.isNull(fieldType, 'getFieldType should return null for a field not flagged IsPII__c.');
    }

    @IsTest static void testScenario3() {

        Test.startTest();
            Boolean isPiiUnknownObject = AIPiiFieldRegistry.isPiiField('Account', 'Email');
            Boolean isPiiUnknownField = AIPiiFieldRegistry.isPiiField('Contact', 'SomeFieldThatDoesNotExist__c');
            String fieldTypeBlankArgs = AIPiiFieldRegistry.getFieldType(null, null);
        Test.stopTest();

        Assert.isFalse(isPiiUnknownObject, 'An object with no synced PII metadata should report false rather than throw.');
        Assert.isFalse(isPiiUnknownField, 'An unrecognized field on a known object should report false.');
        Assert.isNull(fieldTypeBlankArgs, 'Blank object/field arguments should return null rather than throw.');
    }

    @IsTest static void testScenario4() {

        Test.startTest();
            AIPiiFieldRegistry.isPiiField('Contact', 'Email');
            Integer queriesAfterFirstCall = Limits.getQueries();
            AIPiiFieldRegistry.isPiiField('Contact', 'Description');
            AIPiiFieldRegistry.getFieldType('Contact', 'Email');
            Integer queriesAfterRepeatedCalls = Limits.getQueries();
        Test.stopTest();

        Assert.areEqual(queriesAfterFirstCall, queriesAfterRepeatedCalls, 'Repeated lookups against an already-queried object should be served from the transaction-scoped cache.');
    }
}