/*
Class Name: AIPiiPseudonymizationServiceTest

=================================================================
=================================================================

Description: Testing utility for the AIPiiPseudonymizationService orchestration layer.

=================================================================
=================================================================
Applicable Classes:

AIPiiPseudonymizationService: Coverage 100%

Version      Date               Author                   Description
1.0          2026-09-15         Chandler Stuart          Initial development
1.1          2026-09-27         Chandler Stuart          Added testScenario8 - fake values unique per conversation.
*/

@IsTest private class AIPiiPseudonymizationServiceTest {

    // testScenario1: A non-PII field's value passes through unchanged, and no mapping is stored.
    // testScenario2: A PII field's value is pseudonymized to one of its Masking Rule's substitute values, the pairing is remembered, and restoreRealValue reverses it.
    // testScenario3: Pseudonymizing the same real value twice for the same conversation returns the same fake value both times.
    // testScenario4: restoreRealValue on a value with no known mapping returns the input unchanged.
    // testScenario5: A blank real value passes through unchanged without being classified or mapped.
    // testScenario6: Every PII field type generates a value from its own Masking Rule's substitute list and round-trips through restoreRealValue.
    // testScenario7: A field type with a RandomizeByPattern Masking Rule, or with no active Masking Rule at all, falls back to a generic redacted value instead of leaking real PII - and that fallback still round-trips.
    // testScenario8: Distinct real values in one conversation never share a fake value - once the substitute list is used up, the next value falls back to a unique redacted value, and every value still restores to its own real value.

    @TestSetup static void setup() {

        AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(1, 'Contact', true)[0];
        AIAssistTestDataFactory.createAIPIIFieldMetadata(registry.Id, 'Contact', 'Email', 'Email', true, AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL, true);
        AIAssistTestDataFactory.createAIPIIFieldMetadata(registry.Id, 'Contact', 'Description', 'Description', false, null, true);
        AIAssistTestDataFactory.createAIPIIFieldMetadata(registry.Id, 'Contact', 'Name', 'Name', true, AIAssistApplicationConstants.PII_FIELD_TYPE_NAME, true);
        AIAssistTestDataFactory.createAIPIIFieldMetadata(registry.Id, 'Contact', 'Phone', 'Phone', true, AIAssistApplicationConstants.PII_FIELD_TYPE_PHONE, true);
        AIAssistTestDataFactory.createAIPIIFieldMetadata(registry.Id, 'Contact', 'SSN__c', 'SSN', true, AIAssistApplicationConstants.PII_FIELD_TYPE_SSN, true);
        AIAssistTestDataFactory.createAIPIIFieldMetadata(registry.Id, 'Contact', 'CreditCard__c', 'Credit Card', true, AIAssistApplicationConstants.PII_FIELD_TYPE_CREDIT_CARD, true);
        AIAssistTestDataFactory.createAIPIIFieldMetadata(registry.Id, 'Contact', 'Confidential__c', 'Confidential', true, AIAssistApplicationConstants.PII_FIELD_TYPE_OTHER, true);
    }

    private static Id createConversationId() {
        Id agentId = AIAssistTestDataFactory.createAIAgents(1, true)[0].Id;
        return AIAssistTestDataFactory.createAIConversations(agentId, 1, true)[0].Id;
    }

    private static AIPiiDataMaskingRule__mdt substituteFromListRule(String substituteValuesCsv) {
        return new AIPiiDataMaskingRule__mdt(
            Strategy__c = AIAssistApplicationConstants.PII_MASKING_STRATEGY_SUBSTITUTE_FROM_LIST,
            SubstituteValues__c = substituteValuesCsv,
            Active__c = true
        );
    }

    @IsTest static void testScenario1() {

        Id conversationId = createConversationId();

        Test.startTest();
            String result = AIPiiPseudonymizationService.pseudonymize(conversationId, 'Contact', 'Description', 'Some non-PII text');
        Test.stopTest();

        Assert.areEqual('Some non-PII text', result, 'A non-PII field value should pass through unchanged.');
        Integer mappingCount = [SELECT COUNT() FROM AIPIIMapping__c WHERE AIConversation__c = :conversationId];
        Assert.areEqual(0, mappingCount, 'No mapping should be stored for a non-PII field.');
    }

    @IsTest static void testScenario2() {

        Id conversationId = createConversationId();

        AIPiiPseudonymizationService.maskingRuleByFieldType = new Map<String, AIPiiDataMaskingRule__mdt>{
            AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL => substituteFromListRule('alex.rivera@example.com,jordan.chen@example.com')
        };

        Test.startTest();
            String fakeValue = AIPiiPseudonymizationService.pseudonymize(conversationId, 'Contact', 'Email', 'jane.doe@realcompany.com');
        Test.stopTest();

        Assert.areNotEqual('jane.doe@realcompany.com', fakeValue, 'A PII field value should be pseudonymized to something different from the real value.');
        Assert.isTrue(new Set<String>{ 'alex.rivera@example.com', 'jordan.chen@example.com' }.contains(fakeValue), 'The fake value should come from the Masking Rule\'s substitute list.');

        String restored = AIPiiPseudonymizationService.restoreRealValue(conversationId, fakeValue);
        Assert.areEqual('jane.doe@realcompany.com', restored, 'restoreRealValue should reverse a fake value back to the original real value.');
    }

    @IsTest static void testScenario3() {

        Id conversationId = createConversationId();

        AIPiiPseudonymizationService.maskingRuleByFieldType = new Map<String, AIPiiDataMaskingRule__mdt>{
            AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL => substituteFromListRule('alex.rivera@example.com,jordan.chen@example.com')
        };

        Test.startTest();
            String firstFakeValue = AIPiiPseudonymizationService.pseudonymize(conversationId, 'Contact', 'Email', 'jane.doe@realcompany.com');
            String secondFakeValue = AIPiiPseudonymizationService.pseudonymize(conversationId, 'Contact', 'Email', 'jane.doe@realcompany.com');
        Test.stopTest();

        Assert.areEqual(firstFakeValue, secondFakeValue, 'Pseudonymizing the same real value twice in one conversation should return the same fake value both times.');
    }

    @IsTest static void testScenario4() {

        Id conversationId = createConversationId();

        Test.startTest();
            String result = AIPiiPseudonymizationService.restoreRealValue(conversationId, 'not-a-known-fake-value@example.com');
        Test.stopTest();

        Assert.areEqual('not-a-known-fake-value@example.com', result, 'restoreRealValue should return the input unchanged when it has no known mapping.');
    }

    @IsTest static void testScenario5() {

        Id conversationId = createConversationId();

        Test.startTest();
            String result = AIPiiPseudonymizationService.pseudonymize(conversationId, 'Contact', 'Email', '');
        Test.stopTest();

        Assert.areEqual('', result, 'A blank real value should pass through unchanged.');
        Integer mappingCount = [SELECT COUNT() FROM AIPIIMapping__c WHERE AIConversation__c = :conversationId];
        Assert.areEqual(0, mappingCount, 'A blank real value should never be mapped.');
    }

    @IsTest static void testScenario6() {

        Id conversationId = createConversationId();

        Map<String, String> substituteValuesCsvByFieldType = new Map<String, String>{
            AIAssistApplicationConstants.PII_FIELD_TYPE_NAME => 'Alex Rivera,Jordan Chen',
            AIAssistApplicationConstants.PII_FIELD_TYPE_PHONE => '555-100-0100,555-200-0200',
            AIAssistApplicationConstants.PII_FIELD_TYPE_SSN => '000-00-0000,111-11-1111',
            AIAssistApplicationConstants.PII_FIELD_TYPE_CREDIT_CARD => '0000 0000 0000 0000,1111 1111 1111 1111'
        };

        AIPiiPseudonymizationService.maskingRuleByFieldType = new Map<String, AIPiiDataMaskingRule__mdt>();
        for (String fieldType : substituteValuesCsvByFieldType.keySet()) {
            AIPiiPseudonymizationService.maskingRuleByFieldType.put(fieldType, substituteFromListRule(substituteValuesCsvByFieldType.get(fieldType)));
        }

        Map<String, String> realValueByFieldApiName = new Map<String, String>{
            'Name' => 'Jane Doe',
            'Phone' => '415-555-0100',
            'SSN__c' => '123-45-6789',
            'CreditCard__c' => '4111 1111 1111 1111'
        };

        Map<String, String> fieldApiNameToFieldType = new Map<String, String>{
            'Name' => AIAssistApplicationConstants.PII_FIELD_TYPE_NAME,
            'Phone' => AIAssistApplicationConstants.PII_FIELD_TYPE_PHONE,
            'SSN__c' => AIAssistApplicationConstants.PII_FIELD_TYPE_SSN,
            'CreditCard__c' => AIAssistApplicationConstants.PII_FIELD_TYPE_CREDIT_CARD
        };

        Test.startTest();
            for (String fieldApiName : realValueByFieldApiName.keySet()) {

                String realValue = realValueByFieldApiName.get(fieldApiName);
                String fieldType = fieldApiNameToFieldType.get(fieldApiName);
                String fakeValue = AIPiiPseudonymizationService.pseudonymize(conversationId, 'Contact', fieldApiName, realValue);

                Set<String> allowedFakeValues = new Set<String>(substituteValuesCsvByFieldType.get(fieldType).split(','));
                Assert.isTrue(allowedFakeValues.contains(fakeValue), fieldApiName + ' should generate a fake value from its own Masking Rule\'s substitute list.');
                Assert.areEqual(realValue, AIPiiPseudonymizationService.restoreRealValue(conversationId, fakeValue), fieldApiName + ' fake value should restore back to its real value.');
            }
        Test.stopTest();
    }

    @IsTest static void testScenario7() {

        Id conversationId = createConversationId();

        AIPiiPseudonymizationService.maskingRuleByFieldType = new Map<String, AIPiiDataMaskingRule__mdt>{
            AIAssistApplicationConstants.PII_FIELD_TYPE_OTHER => new AIPiiDataMaskingRule__mdt(
                Strategy__c = AIAssistApplicationConstants.PII_MASKING_STRATEGY_RANDOMIZE_BY_PATTERN,
                ReplacementPattern__c = '\\d',
                Redact__c = true,
                Active__c = true
            )
            // PII_FIELD_TYPE_SSN deliberately has no entry, simulating a Field Type with no active Masking Rule.
        };

        Test.startTest();
            String randomizeByPatternFieldFakeValue = AIPiiPseudonymizationService.pseudonymize(conversationId, 'Contact', 'Confidential__c', 'some confidential value');
            String noRuleFieldFakeValue = AIPiiPseudonymizationService.pseudonymize(conversationId, 'Contact', 'SSN__c', '123-45-6789');
        Test.stopTest();

        Assert.isTrue(randomizeByPatternFieldFakeValue.startsWith('REDACTED-'), 'A RandomizeByPattern Masking Rule can leave real characters intact and risks reverse-mapping collisions, so pseudonymization should fall back to a generic redacted value instead.');
        Assert.isTrue(noRuleFieldFakeValue.startsWith('REDACTED-'), 'A Field Type with no active Masking Rule should also fall back to a generic redacted value.');
        Assert.areNotEqual(randomizeByPatternFieldFakeValue, noRuleFieldFakeValue, 'Fallback values for different real values should not collide with each other.');

        Assert.areEqual('some confidential value', AIPiiPseudonymizationService.restoreRealValue(conversationId, randomizeByPatternFieldFakeValue), 'The fallback value should still round-trip back to its real value via the stored mapping.');
        Assert.areEqual('123-45-6789', AIPiiPseudonymizationService.restoreRealValue(conversationId, noRuleFieldFakeValue), 'The fallback value should still round-trip back to its real value via the stored mapping.');
    }
    @IsTest static void testScenario8() {

        Id conversationId = createConversationId();

        AIPiiPseudonymizationService.maskingRuleByFieldType = new Map<String, AIPiiDataMaskingRule__mdt>{
            AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL => substituteFromListRule('alex.rivera@example.com,jordan.chen@example.com')
        };

        Test.startTest();
            String firstFakeValue = AIPiiPseudonymizationService.pseudonymize(conversationId, 'Contact', 'Email', 'elena@realcompany.com');
            String secondFakeValue = AIPiiPseudonymizationService.pseudonymize(conversationId, 'Contact', 'Email', 'hannah@realcompany.com');
            String thirdFakeValue = AIPiiPseudonymizationService.pseudonymize(conversationId, 'Contact', 'Email', 'marcus@realcompany.com');
        Test.stopTest();

        Assert.areNotEqual(firstFakeValue, secondFakeValue, 'Two real values in one conversation should never share a fake value.');
        Assert.areEqual(new Set<String>{ 'alex.rivera@example.com', 'jordan.chen@example.com' }, new Set<String>{ firstFakeValue, secondFakeValue }, 'Both substitutes should be used before falling back.');
        Assert.isTrue(thirdFakeValue.startsWith('REDACTED-'), 'Once every substitute is used, the next value should fall back to a redacted value.');

        Assert.areEqual('elena@realcompany.com', AIPiiPseudonymizationService.restoreRealValue(conversationId, firstFakeValue));
        Assert.areEqual('hannah@realcompany.com', AIPiiPseudonymizationService.restoreRealValue(conversationId, secondFakeValue));
        Assert.areEqual('marcus@realcompany.com', AIPiiPseudonymizationService.restoreRealValue(conversationId, thirdFakeValue));
    }
}