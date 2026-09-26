/*
Class Name: AIPiiMappingService

=================================================================
=================================================================

Description: Pure storage for the real-value-to-fake-value PII mapping built up over the
life of one conversation. Knows nothing about PII itself - it just persists whatever pairs
AIPiiPseudonymizationService hands it and reads them back later, keyed by conversation. The
mapping is stored as JSON in a single AIPIIMapping__c row per conversation. Reads and the
mapping itself are cached per conversation for the life of the transaction.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development

*/

public without sharing class AIPiiMappingService {

    @TestVisible private static Map<Id, Map<String, String>> conversationIdToMapping = new Map<Id, Map<String, String>>();
    @TestVisible private static Map<Id, Map<String, String>> conversationIdToReverseMapping = new Map<Id, Map<String, String>>();

    @TestVisible private static Map<Id, AIPIIMapping__c> conversationIdToPIIMapping = new Map<Id, AIPIIMapping__c>();


    // Looks up the fake value previously mapped to a real value for this conversation, if any.
    public static String getFakeValueForRealValue(Id conversationId, String realValue) {
        if (conversationId == null || String.isBlank(realValue)) return null;
        return getMapping(conversationId).get(realValue);
    }

    // Looks up the real value behind a previously issued fake value for this conversation, if any.
    public static String getRealValueForFakeValue(Id conversationId, String fakeValue) {
        if (conversationId == null || String.isBlank(fakeValue)) return null;
        return getReverseMapping(conversationId).get(fakeValue);
    }

    // Fake value -> real value for the conversation, built by inverting the forward mapping.
    private static Map<String, String> getReverseMapping(Id conversationId) {
        try {

            if (conversationId == null || conversationId.getSobjectType() != AIConversation__c.SObjectType) return new Map<String, String>();

            if (!conversationIdToReverseMapping.containsKey(conversationId)) {
                
                Map<String, String> reverse = new Map<String, String>();
                Map<String, String> mapping = getMapping(conversationId);
            
                for (String realValue : mapping.keySet()) { reverse.put(mapping.get(realValue), realValue); }
            
                conversationIdToReverseMapping.put(conversationId, reverse);
            }

            return conversationIdToReverseMapping.get(conversationId);

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIPiiMappingService', 'getReverseMapping');
            return new Map<String, String>();
        }
    }
   

    // Get AI PII Mapping SObject. Keyed by the ConversationId
    private static AIPIIMapping__c getMappingRecord(Id conversationId) {
        try {

            if (conversationId == null || conversationId.getSobjectType() != AIConversation__c.SObjectType) return null;

            if (conversationIdToPIIMapping == null || !conversationIdToPIIMapping.containsKey(conversationId)) {
                List<AIPIIMapping__c> existing = [SELECT Id, MappingJson__c FROM AIPIIMapping__c WHERE AIConversation__c =:conversationId LIMIT 1];
                conversationIdToPIIMapping.put(conversationId, existing.isEmpty() ? null : existing[0]);
            }

            return conversationIdToPIIMapping.get(conversationId);

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIPiiMappingService', 'getMappingRecord');
            return null;
        }
    }

    // Real value -> fake value for the conversation.
    public static Map<String, String> getMapping(Id conversationId) {
        try {

            if (conversationId == null || conversationId.getSobjectType() != AIConversation__c.SObjectType) return new Map<String, String>();

            if (!conversationIdToMapping.containsKey(conversationId)) {
                AIPIIMapping__c existing = getMappingRecord(conversationId);
                conversationIdToMapping.put(conversationId, parseMappingJson(existing == null ? null : existing.MappingJson__c));
            }

            return conversationIdToMapping.get(conversationId);

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIPiiMappingService', 'getMapping');
            return new Map<String, String>();
        }
    }
        
    // Deserializes the stored MappingJson__c into a real-value-to-fake-value map, dropping blank entries.
    private static Map<String, String> parseMappingJson(String mappingJson) {
        try {

            if (String.isBlank(mappingJson)) return new Map<String, String>();

            Map<String, Object> realToFakeUntypedJSON = (Map<String, Object>) JSON.deserializeUntyped(mappingJson);
            Map<String, String> realToFakeValues = new Map<String, String>();

            for (String realValue : realToFakeUntypedJSON.keySet()) {
                if ( String.isBlank((String) realToFakeUntypedJSON.get(realValue)) ) continue;
                realToFakeValues.put(realValue, (String) realToFakeUntypedJSON.get(realValue));
            }

            return !realToFakeValues.isEmpty() ? realToFakeValues : new Map<String, String>();

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIPiiMappingService', 'parseMappingJson');
            return new Map<String, String>();
        }
    }

    // Adds one real/fake pairing to the conversation's mapping. No-ops if the real value is already mapped.
    public static Boolean addMapping(Id conversationId, String realValue, String fakeValue) {
        try {

            if (conversationId == null || conversationId.getSobjectType() != AIConversation__c.SObjectType || String.isBlank(realValue) || String.isBlank(fakeValue)) return false;
            if (getMapping(conversationId).containsKey(realValue)) return false;

            AIPIIMapping__c existing = getMappingRecord(conversationId);

            Map<String, Object> pairs = (existing != null && String.isNotBlank(existing.MappingJson__c)) ? (Map<String, Object>) JSON.deserializeUntyped(existing.MappingJson__c) : new Map<String, Object>();

            pairs.put(realValue, fakeValue);

            // Re-serialise the full map back to JSON for storage.
            String updatedJson = JSON.serialize(pairs);

            if (existing != null) {
                // Update the existing mapping record with the merged JSON.
                Database.SaveResult updateResult = Database.update( new AIPIIMapping__c(Id = existing.Id, MappingJson__c = updatedJson), false );
                if (!updateResult.isSuccess()) {
                    AIPlatformLogManager.logCustomMessage('Failed to update AIPIIMapping__c ' + existing.Id + ': ' + updateResult.getErrors(), null, 'AIPiiMappingService', 'addMapping', null);
                    return false;
                }
                // Keep the cached record's JSON current so a second pairing in the same transaction merges onto it instead of a stale copy.
                existing.MappingJson__c = updatedJson;
            } else {
                // No mapping record exists yet for this conversation, so create one.
                AIPIIMapping__c inserted = new AIPIIMapping__c(AIConversation__c = conversationId, MappingJson__c = updatedJson);
                Database.SaveResult insertResult = Database.insert(inserted, false);
                if (!insertResult.isSuccess()) {
                    AIPlatformLogManager.logCustomMessage('Failed to insert AIPIIMapping__c for Conversation ' + conversationId + ': ' + insertResult.getErrors(), null, 'AIPiiMappingService', 'addMapping', null);
                    return false;
                }
                // Keep the record cache authoritative so a second pairing in the same transaction updates this row instead of inserting a duplicate.
                conversationIdToPIIMapping.put(conversationId, inserted);
            }

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIPiiMappingService', 'addMapping');
            return false;
        }

        // Keep the transaction-scoped cache authoritative so a get() immediately after this add reflects it without a re-query.
        getMapping(conversationId).put(realValue, fakeValue);
        getReverseMapping(conversationId).put(fakeValue, realValue);

        return true;
    }
}