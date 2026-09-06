/*
Class Name: AIAssistGlobalUtility

=================================================================
=================================================================

Description: This class provides global utility methods for the AI Assist Platform.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIAssistGlobalUtility {
   
    public static void generatePublicId(List<SObject> records) {
        try {
        
            if (records == null || records.isEmpty()) return;

            Map<Schema.SObjectType, Boolean> hasPublicIdFieldByType = new Map<Schema.SObjectType, Boolean>();

            for (SObject record : records) {
                
                Schema.SObjectType sObjectType = record.getSObjectType();

                if (!hasPublicIdFieldByType.containsKey(sObjectType)) {
                    Boolean hasField = sObjectType.getDescribe().fields.getMap().containsKey(AIAssistApplicationConstants.PUBLIC_ID_FIELD_API_NAME);
                    hasPublicIdFieldByType.put(sObjectType, hasField);
                }

                if (!hasPublicIdFieldByType.get(sObjectType)) continue; // Field doesn't exist on this object.
                if (record.get(AIAssistApplicationConstants.PUBLIC_ID_FIELD_API_NAME) != null) continue; // Already populated.

                String seed = String.valueOf(Datetime.now().getTime()) + String.valueOf(Crypto.getRandomLong());
                String hex = EncodingUtil.convertToHex(Crypto.generateDigest('MD5', Blob.valueOf(seed))); // 32 chars

                String publicId = hex.substring(0, 8) + '-' + hex.substring(8, 12) + '-' + hex.substring(12, 16) + '-' + hex.substring(16, 20) + '-' + hex.substring(20, 32); // 36 chars

                record.put(AIAssistApplicationConstants.PUBLIC_ID_FIELD_API_NAME, publicId);
            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIAssistGlobalUtility', 'generatePublicId');
        }
    }

    public static void generateDeveloperName(List<SObject> records) {
        try {

            if (records == null || records.isEmpty()) return;

            Map<Schema.SObjectType, Boolean> hasDeveloperNameFieldByType = new Map<Schema.SObjectType, Boolean>();

            for (SObject record : records) {

                Schema.SObjectType sObjectType = record.getSObjectType();

                if (!hasDeveloperNameFieldByType.containsKey(sObjectType)) {
                    Boolean hasField = sObjectType.getDescribe().fields.getMap().containsKey(AIAssistApplicationConstants.DEVELOPER_NAME_FIELD_API_NAME);
                    hasDeveloperNameFieldByType.put(sObjectType, hasField);
                }

                if (!hasDeveloperNameFieldByType.get(sObjectType)) continue; // Field doesn't exist on this object.
                if (record.get(AIAssistApplicationConstants.DEVELOPER_NAME_FIELD_API_NAME) != null) continue; // Already populated.

                Object rawValue = record.get(AIAssistApplicationConstants.DEVELOPER_NAME_SOURCE_FIELD_API_NAME);
                if (rawValue == null) continue; // Nothing to derive a Developer Name from yet.

                String developerName = String.valueOf(rawValue).trim().replaceAll('[^a-zA-Z0-9]+', '_');
                if (String.isBlank(developerName)) continue;

                record.put(AIAssistApplicationConstants.DEVELOPER_NAME_FIELD_API_NAME, developerName);
            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIAssistGlobalUtility', 'generateDeveloperName');
        }
    }
}