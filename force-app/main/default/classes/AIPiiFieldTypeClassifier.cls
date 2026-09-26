/*
Class Name: AIPiiFieldTypeClassifier

=================================================================
=================================================================

Description: Classifies a field's PII type (Name, Email, Bank Account, NI Number, NHS
Number, etc.) from its API name, label, data type, and Compliance Group. Called once per
field by AIPiiRegistryWorker during the nightly Tooling API sync; result is cached on
AIPIIFieldMetadata__c.PIIFieldType__c.

Matching rules are defined in AIPiiFieldType__mdt, editable in Setup without deployment.
If no keyword rule matches, falls back to the Field Type flagged
IsComplianceGroupFallback__c for the field's Compliance Group instead of returning "Other".

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPiiFieldTypeClassifier {

    public class AIPiiFieldTypeClassifierException extends Exception {}

    private static List<AIPiiFieldType__mdt> cachedFieldTypes;
    private static Map<Id, AIPiiComplianceGroup__mdt> cachedComplianceGroupsById;

    // Test-only seams so unit tests can inject in-memory Custom Metadata rather than depending on real deployed records.
    @TestVisible private static void setFieldTypesForTest(List<AIPiiFieldType__mdt> fieldTypes) {
        cachedFieldTypes = fieldTypes;
    }

    @TestVisible private static void setComplianceGroupsForTest(Map<Id, AIPiiComplianceGroup__mdt> complianceGroupsById) {
        cachedComplianceGroupsById = complianceGroupsById;
    }

    public static String classify(String fieldApiName, String fieldLabel, String dataType, String complianceGroup) {
        try {

            if (String.isBlank(fieldApiName) || String.isBlank(fieldLabel) || String.isBlank(dataType) || String.isBlank(complianceGroup)) return null;

            // Stripped down to bare letters/digits (no spaces, underscores, hyphens, or case) so "Social_Security_Number", "SSN Number", "ssn-number" and "SocialSecurityNumber" all normalize to the same shape for matching.
            String normalisedFieldName = fieldApiName.toLowerCase().replaceAll('[^a-z0-9]', '') + ' ' + fieldLabel.toLowerCase().replaceAll('[^a-z0-9]', '');
            String normalisedApiName = fieldApiName.toLowerCase();
            String normalisedDataType = dataType.toLowerCase();

            AIPiiFieldType__mdt complianceGroupFallback = null;
            List<AIPiiFieldType__mdt> fieldTypes = getFieldTypes();

            if (fieldTypes == null || fieldTypes.isEmpty()) throw new AIPiiFieldTypeClassifierException('No AIPiiFieldType__mdt metadata found');

            for (AIPiiFieldType__mdt fieldType : fieldTypes) {

                if (String.isBlank(fieldType.Keyword__c)) continue;

                String cleanedMatchField = String.isBlank(fieldType.MatchField__c) ? '' : fieldType.MatchField__c.trim();

                for (String keyword : fieldType.Keyword__c.split(',')) {

                    String cleanedKeyword = keyword.trim().toLowerCase();

                    if (String.isBlank(cleanedKeyword)) continue;

                    Boolean isFieldMatch = false;

                    if (cleanedMatchField.equalsIgnoreCase(AIAssistApplicationConstants.PII_MATCH_FIELD_API_NAME_EXACT)) {
                        isFieldMatch = normalisedApiName.equalsIgnoreCase(cleanedKeyword);
                    } else if (cleanedMatchField.equalsIgnoreCase(AIAssistApplicationConstants.PII_MATCH_FIELD_DATA_TYPE_CONTAINS)) {
                        isFieldMatch = normalisedDataType.contains(cleanedKeyword);
                    } else if (cleanedMatchField.equalsIgnoreCase(AIAssistApplicationConstants.PII_MATCH_FIELD_NAME_OR_LABEL_CONTAINS)) {
                        isFieldMatch = normalisedFieldName.contains(cleanedKeyword);
                    }

                    if (isFieldMatch) {
                        return fieldType.PIIFieldType__c;
                    }
                }

                // No keyword shape matched this Field Type, but remember it if it's the designated fallback
                // representative for the field's own Compliance Group, in case nothing else matches either.
                if (complianceGroupFallback == null && fieldType.IsComplianceGroupFallback__c && String.isNotBlank(complianceGroup) && fieldType.ComplianceGroup__c != null && complianceGroupMatches(fieldType.ComplianceGroup__c, complianceGroup)) {
                    complianceGroupFallback = fieldType;
                }
            }

            if (complianceGroupFallback != null) {
                return complianceGroupFallback.PIIFieldType__c;
            }

            // No specific shape matched and no Field Type claims this Compliance Group as its fallback, but Salesforce Data Classification still flagged this field with a Compliance Group - treat it as PII
            return AIAssistApplicationConstants.PII_FIELD_TYPE_OTHER;

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIPiiFieldTypeClassifier', 'classify');
            return null;
        }
    }

    private static List<AIPiiFieldType__mdt> getFieldTypes() {
        try {

            if (cachedFieldTypes == null) {

                List<AIPiiFieldType__mdt> fieldTypes  = [SELECT Keyword__c, MatchField__c, PIIFieldType__c, ComplianceGroup__c, IsComplianceGroupFallback__c, DisplayOrder__c
                                                        FROM AIPiiFieldType__mdt
                                                        WHERE Active__c = true
                                                        ORDER BY DisplayOrder__c ASC];

                if (fieldTypes != null && !fieldTypes.isEmpty()) cachedFieldTypes = fieldTypes;

            }

            return cachedFieldTypes;

        } catch (Exception ex ) {
            AIPlatformLogManager.logException(ex, 'AIPiiFieldTypeClassifier', 'getFieldTypes');
            return new List<AIPiiFieldType__mdt>();
        }
    }

    private static Boolean complianceGroupMatches(Id complianceGroupId, String complianceGroup) {
        try {

            AIPiiComplianceGroup__mdt complianceGroupRecord = getComplianceGroupsById().get(complianceGroupId);
            return complianceGroupRecord != null && complianceGroupRecord.Active__c && complianceGroup.equalsIgnoreCase(complianceGroupRecord.MasterLabel);

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIPiiFieldTypeClassifier', 'complianceGroupMatches');
            return false;
        }
    }

    private static Map<Id, AIPiiComplianceGroup__mdt> getComplianceGroupsById() {
        try {

            if (cachedComplianceGroupsById == null) {

                List<AIPiiComplianceGroup__mdt> complianceGroups = [SELECT MasterLabel, Active__c FROM AIPiiComplianceGroup__mdt];

                cachedComplianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>(complianceGroups);

            }

            return cachedComplianceGroupsById;

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIPiiFieldTypeClassifier', 'getComplianceGroupsById');
            return new Map<Id, AIPiiComplianceGroup__mdt>();
        }
    }

}