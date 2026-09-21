/*
Class Name: AIPiiFieldRegistry

=================================================================
=================================================================

Description: Read-only lookup layer over the already-synced AIPIIFieldMetadata__c data.
Answers "is this field PII?" and "what type of PII is it?" with plain SOQL - zero callouts,
zero classification logic of its own, since AIPiiFieldTypeClassifier already made that call
during AIPiiRegistryWorker's sync. Results are cached per object API name for the duration
of the transaction so processing many fields (or many rows) on the same object costs one
query total, not one per field.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPiiFieldRegistry {

    @TestVisible private static Map<String, Map<String, String>> piiFieldTypesByObject = new Map<String, Map<String, String>>();

    public static String getFieldType(String objectApiName, String fieldApiName){
        try {

            if (String.isBlank(objectApiName) || String.isBlank(fieldApiName)) return null;

            if (!piiFieldTypesByObject.containsKey(objectApiName)) { getPiiFieldTypes(objectApiName); } // Get Pii field for SObject

            return piiFieldTypesByObject.get(objectApiName).get(fieldApiName);

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIPiiFieldRegistry', 'getFieldType');
            return null;
        }
    }

    public static Boolean isPiiField(String objectApiName, String fieldApiName){
        try {

            if (String.isBlank(objectApiName) || String.isBlank(fieldApiName)) return false;

            if (!piiFieldTypesByObject.containsKey(objectApiName)) { getPiiFieldTypes(objectApiName); } // Get Pii field for SObject

            return piiFieldTypesByObject.get(objectApiName).containsKey(fieldApiName);

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIPiiFieldRegistry', 'isPiiField');
            return false;
        }
    }

    // Bulk-friendly - one query per unique object API name per transaction, cached for every subsequent call against that object.
    public static Map<String, String> getPiiFieldTypes(String objectApiName){
        try {

            if (String.isBlank(objectApiName)) return new Map<String, String>();

            if (!piiFieldTypesByObject.containsKey(objectApiName)) {

                Map<String, String> fieldTypesByFieldApiName = new Map<String, String>();

                for (AIPIIFieldMetadata__c fieldMetadata : [ SELECT FieldAPIName__c, PIIFieldType__c FROM AIPIIFieldMetadata__c WHERE PIIRegistry__r.ObjectAPIName__c =:objectApiName AND IsPII__c = TRUE]) {
                    fieldTypesByFieldApiName.put(fieldMetadata.FieldAPIName__c, fieldMetadata.PIIFieldType__c);
                }

                piiFieldTypesByObject.put(objectApiName, fieldTypesByFieldApiName);
            }

            return piiFieldTypesByObject.get(objectApiName);

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIPiiFieldRegistry', 'getPiiFieldTypes');
            return new Map<String, String>();
        }
    }
}