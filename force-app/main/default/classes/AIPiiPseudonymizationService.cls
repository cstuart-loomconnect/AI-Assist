/*
Class Name: AIPiiPseudonymizationService

=================================================================
=================================================================

Description: Masks PII before it reaches an LLM and restores it after, using AIPiiFieldRegistry
(field type), AIPiiDataMaskingRule__mdt (fake value), and AIPiiMappingService (pairing memory).

Only SubstituteFromList is safe - other cases (RandomizeByPattern, missing rule, empty list)
fall back to a generic redacted value and log the misconfiguration.

Every fake value is unique within a conversation - a substitute already paired with another real value
(or equal to a real value) is skipped, since two real values sharing one fake value can't be restored
correctly. Once a rule's list is used up, the conversation falls back to the unique redacted value.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
1.1          Chandler Stuart          Substitutes already used in the conversation are skipped, so two real values never share a fake value.

*/

public without sharing class AIPiiPseudonymizationService {

    @TestVisible private static Map<String, AIPiiDataMaskingRule__mdt> maskingRuleByFieldType;

    // If the field isn't PII, the real value is returned unchanged. Otherwise returns the fake value already mapped for this conversation, or generates and remembers a new one.
    public static String pseudonymize(Id conversationId, String objectApiName, String fieldApiName, String realValue) {
        try {

            if (conversationId == null || conversationId.getSobjectType() != AIConversation__c.SObjectType || String.isBlank(objectApiName) || String.isBlank(fieldApiName) || String.isBlank(realValue)  ) return '';

            String fieldType = AIPiiFieldRegistry.getFieldType(objectApiName, fieldApiName);
            if (String.isBlank(fieldType)) return realValue;

            String existingFakeValue = AIPiiMappingService.getFakeValueForRealValue(conversationId, realValue);
            if (String.isNotBlank(existingFakeValue)) return existingFakeValue;

            String fakeValue = generateFakeValue(conversationId, fieldType);

            // Remember the real-to-fake pairing so it can be reversed later and reused for repeated values in this conversation
            AIPiiMappingService.addMapping(conversationId, realValue, fakeValue);

            return fakeValue;

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIPiiPseudonymizationService', 'pseudonymize');
            return '';
        }
    }

    // Reverses a single fake value back to the real value it was generated from, for restoring an LLM's response before it's shown to the user. Returns the input unchanged if it isn't a known fake value for this conversation.
    public static String restoreRealValue(Id conversationId, String fakeValue) {
        try {

            if (String.isBlank(fakeValue)) return fakeValue;
            String realValue = AIPiiMappingService.getRealValueForFakeValue(conversationId, fakeValue);
            return realValue != null ? realValue : fakeValue;

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIPiiPseudonymizationService', 'restoreRealValue');
            return '';
        }
    }

    // Only SubstituteFromList is trusted to produce a fake value; any other strategy, a misconfigured/empty rule, or a list with every value already used in this conversation falls back to a generic redacted value.
    private static String generateFakeValue(Id conversationId, String fieldType) {
        try {

            AIPiiDataMaskingRule__mdt rule = getMaskingRuleByFieldType().get(fieldType);

            if (rule != null && rule.Active__c && rule.Strategy__c == AIAssistApplicationConstants.PII_MASKING_STRATEGY_SUBSTITUTE_FROM_LIST) {

                // Both sides of every existing pairing - reusing a fake value, or picking one that's another record's real value, would make restoring ambiguous.
                Map<String, String> fakeValueByRealValue = AIPiiMappingService.getMapping(conversationId);
                Set<String> valuesInUse = new Set<String>(fakeValueByRealValue.values());
                valuesInUse.addAll(fakeValueByRealValue.keySet());

                String fakeValue = pickSubstituteValue(rule.SubstituteValues__c, valuesInUse);
                if (fakeValue != null) return fakeValue;

                AIPlatformLogManager.logCustomMessage( 'Every substitute value for PII field type "' + fieldType + '" is already used in this conversation - falling back to a generic redacted value. Add more values to the Masking Rule.', null, 'AIPiiPseudonymizationService', 'generateFakeValue', conversationId );

            } else {
                AIPlatformLogManager.logCustomMessage( 'No usable Substitute From List masking rule for PII field type "' + fieldType + '" - falling back to a generic redacted value.', null, 'AIPiiPseudonymizationService', 'generateFakeValue', null );
            }

            // A random suffix keeps each fallback unique so distinct real values never collide on the same fake value.
            return 'REDACTED-' + randomDigits(10);

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIPiiPseudonymizationService', 'generateFakeValue');
            return '';
        }
    }

    // Cached per transaction since masking rules don't change mid-conversation and this can be called once per PII field on a message.
    private static Map<String, AIPiiDataMaskingRule__mdt> getMaskingRuleByFieldType() {
        try {

            if (maskingRuleByFieldType == null) {

            maskingRuleByFieldType = new Map<String, AIPiiDataMaskingRule__mdt>();

            for (AIPiiFieldType__mdt fieldType : [SELECT PIIFieldType__c, MaskingRule__r.Strategy__c, MaskingRule__r.SubstituteValues__c, MaskingRule__r.Active__c
                                                   FROM AIPiiFieldType__mdt 
                                                   WHERE Active__c = true
                                                    AND MaskingRule__c != null]) {
                maskingRuleByFieldType.put(fieldType.PIIFieldType__c, fieldType.MaskingRule__r);
            }
        }

        return maskingRuleByFieldType;

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIPiiPseudonymizationService', 'getMaskingRuleByFieldType');
            return new Map<String, AIPiiDataMaskingRule__mdt>();
        }
    }

    // Math.random() rather than Crypto.getRandomInteger() - these values only need to look plausible, and getRandomInteger() can return negative Integers that would need extra guarding against a negative array index.
    private static Integer randomInt(Integer upperBoundExclusive) {
        return Integer.valueOf(Math.floor(Math.random() * upperBoundExclusive));
    }

    private static String randomDigits(Integer length) {
        String digits = '';
        for (Integer i = 0; i < length; i++) { digits += String.valueOf(Integer.valueOf(Math.floor(Math.random() * 10))); }
        return digits;
    }

    // Random pick from a Masking Rule's SubstituteValues__c, skipping any value in valuesInUse. Returns null if nothing is left to pick.
    private static String pickSubstituteValue(String substituteValuesCsv, Set<String> valuesInUse) {

        List<String> substituteValues = new List<String>();
        for (String candidate : String.isBlank(substituteValuesCsv) ? new List<String>() : substituteValuesCsv.split(',')) {
            if (String.isBlank(candidate) || valuesInUse.contains(candidate.trim())) continue;
            substituteValues.add(candidate.trim());
        }

        return substituteValues.isEmpty() ? null : substituteValues[randomInt(substituteValues.size())];
    }

}