/*
Class Name: AiDataSourceResultProcessor

=================================================================
=================================================================

Description: Flattens raw SObject query results into masked Map/List structures safe to hand
to the AI.

Flow: 
[1] bulk-describe every distinct SObjectType in the batch, 
[2] for each record, check FLS per field (when USER_MODE), 
[3] mask PII values via AIPiiPseudonymizationService, 
[4] recurse into parent lookups (max 4 deep) and child subqueries (max 3 deep). Fails closed on any error - omits or redacts rather than risk exposing real data.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-21     Chandler Stuart          Initial development
*/

public without sharing class AiDataSourceResultProcessor {

    @TestVisible private static Id currentConversationId;

    // Caller must set this immediately before process() - otherwise PII gets masked against the wrong conversation's mapping.
    public static void setCurrentConversationId(Id conversationId) {
        currentConversationId = conversationId;
    }

    // Entry point - bulk-describes the batch by SObjectType, then flattens and masks each record under the given AccessLevel (defaults to USER_MODE).
    public static List<Object> process(List<SObject> records, AccessLevel accessLevel) {
        try {

            List<Object> processedRecords = new List<Object>();

            if (records == null) return processedRecords;

            System.AccessLevel effectiveAccessLevel = accessLevel == null ? System.AccessLevel.USER_MODE : accessLevel;

            // Grouping the whole batch by SObjectType up front means every distinct type in it is described in a single bulk Schema.describeSObjects() call, not one getDescribe() call per record. The resulting cache is then reused for every recursive parent/child call too.
            Map<Schema.SObjectType, Schema.DescribeSObjectResult> sObjectTypeToDescribeResult = bulkDescribeByType(records);

            for (SObject record : records) {
                processedRecords.add(
                    flattenRecord(record, effectiveAccessLevel, 0, 0, sObjectTypeToDescribeResult)
                );
            }

            return processedRecords;

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AiDataSourceResultProcessor', 'process');
            return new List<Object>();
        }
    }

    // Flattens a single SObject's populated fields (masking PII and checking FLS as it goes) plus any populated parent lookups and child subqueries, recursively, up to the depth caps.
    private static Map<String, Object> flattenRecord(SObject record, AccessLevel accessLevel, Integer parentDepth, Integer childDepth, Map<Schema.SObjectType, Schema.DescribeSObjectResult> sObjectTypeToDescribeResult) {
        try {

            Map<String, Object> fieldApiNameToFlattenedValue = new Map<String, Object>();

            if (record == null) return fieldApiNameToFlattenedValue;

            Schema.DescribeSObjectResult describeResult = resolveDescribeResult(record.getSObjectType(), sObjectTypeToDescribeResult);
            String objectApiName = describeResult.getName();
            Map<String, Object> fieldApiNameToValue = record.getPopulatedFieldsAsMap();

            for (String fieldApiName : fieldApiNameToValue.keySet()) {

                Object rawValue = fieldApiNameToValue.get(fieldApiName);

                if (!isFieldAccessible(describeResult, fieldApiName, accessLevel)) continue; // Not visible to the running user - omit rather than expose.

                if (rawValue instanceof SObject) {

                    // A populated field whose value is itself an SObject is a traversed parent relationship (e.g. Account.Owner), not a plain field value.
                    if (parentDepth >= AIAssistApplicationConstants.DATA_SOURCE_RESULT_MAX_PARENT_DEPTH) continue; // Depth cap reached - omit rather than keep climbing.
                    fieldApiNameToFlattenedValue.put(fieldApiName, flattenRecord((SObject) rawValue, accessLevel, parentDepth + 1, childDepth, sObjectTypeToDescribeResult));
                } else {
                    fieldApiNameToFlattenedValue.put(fieldApiName, maskIfPii(objectApiName, fieldApiName, rawValue));
                }

            }

            if (childDepth < AIAssistApplicationConstants.DATA_SOURCE_RESULT_MAX_CHILD_DEPTH) {

                // record.getSObjects(relationshipName) throws for any of an object's ~70+ possible child relationships that weren't part of this query's subqueries, rather than returning null -
                // checking every relationship that way is expensive and noisy. Serializing once and checking key presence tells us which ones were actually queried without any of that trial and error.
                Set<String> queriedRelationshipNames = getQueriedChildRelationshipNames(record);

                for (Schema.ChildRelationship childRelationship : describeResult.getChildRelationships()) {

                    String relationshipName = childRelationship.getRelationshipName();

                    if (String.isBlank(relationshipName) || !queriedRelationshipNames.contains(relationshipName)) continue;

                    List<SObject> children = record.getSObjects(relationshipName);
                    if (children == null) continue;

                    List<Object> flattenedChildren = new List<Object>();
                    for (SObject child : children) { flattenedChildren.add(flattenRecord(child, accessLevel, parentDepth, childDepth + 1, sObjectTypeToDescribeResult)); }

                    fieldApiNameToFlattenedValue.put(relationshipName, flattenedChildren);

                }

            }

            return fieldApiNameToFlattenedValue;

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AiDataSourceResultProcessor', 'flattenRecord');
            return new Map<String, Object>();
        }
    }


    // JSON.serialize() on an SObject only includes a child relationship key when that relationship was actually part of the query's subqueries - a cheap, one-shot way to know which relationships are safe to call getSObjects() on. Fails closed to "no relationships queried" on any error.
    private static Set<String> getQueriedChildRelationshipNames(SObject record) {
        try {

            Map<String, Object> serializedRecord = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(record));
            return serializedRecord.keySet();

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AiDataSourceResultProcessor', 'getQueriedChildRelationshipNames');
            return new Set<String>();
        }
    }

    // Groups records by SObjectType and describes every distinct type found in a single bulk Schema.describeSObjects() call.
    private static Map<Schema.SObjectType, Schema.DescribeSObjectResult> bulkDescribeByType(List<SObject> records) {
        try {

            Map<Schema.SObjectType, Schema.DescribeSObjectResult> sObjectTypeToDescribeResult = new Map<Schema.SObjectType, Schema.DescribeSObjectResult>();
            if (records == null || records.isEmpty()) return sObjectTypeToDescribeResult;

            Set<String> distinctObjectApiNames = new Set<String>();
            for (SObject record : records) {
                if (record != null) distinctObjectApiNames.add(record.getSObjectType().getDescribe().getName());
            }

            // Schema.describeSObjects() only takes a List<String> of object API names in this org's API version, not a List<Schema.SObjectType>.
            List<Schema.DescribeSObjectResult> describeResults = Schema.describeSObjects(new List<String>(distinctObjectApiNames));

            for (Schema.DescribeSObjectResult describeResult : describeResults) { sObjectTypeToDescribeResult.put(describeResult.getSObjectType(), describeResult); }

            return sObjectTypeToDescribeResult;

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AiDataSourceResultProcessor', 'bulkDescribeByType');
            return new Map<Schema.SObjectType, Schema.DescribeSObjectResult>();
        }
    }

    // Falls back to describing a single type on demand - used for parent/child SObjectTypes discovered only while recursing, which bulkDescribeByType couldn't have known about up front.
    private static Schema.DescribeSObjectResult resolveDescribeResult(Schema.SObjectType sObjectType, Map<Schema.SObjectType, Schema.DescribeSObjectResult> sObjectTypeToDescribeResult) {

        if (!sObjectTypeToDescribeResult.containsKey(sObjectType)) { sObjectTypeToDescribeResult.put(sObjectType, sObjectType.getDescribe()); }

        return sObjectTypeToDescribeResult.get(sObjectType);
    }

    // Non-String values are never PII by definition; a String value is only masked if AIPiiFieldRegistry has this field registered as PII.
    private static Object maskIfPii(String objectApiName, String fieldApiName, Object rawValue) {
        try {

            if (String.isBlank(objectApiName) || String.isBlank(fieldApiName) || rawValue == null) return rawValue;
            if (!(rawValue instanceof String) || String.isBlank((String) rawValue)) return rawValue;
            if (!AIPiiFieldRegistry.isPiiField(objectApiName, fieldApiName)) return rawValue;

            return AIPiiPseudonymizationService.pseudonymize(currentConversationId, objectApiName, fieldApiName, (String) rawValue);

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AiDataSourceResultProcessor', 'maskIfPii');
            return AIAssistApplicationConstants.DATA_SOURCE_RESULT_REDACTED_ERROR_VALUE; 
        }
    }

    // System context already ran the query bypassing FLS by design, so only user context is checked here. Fails closed - an unresolvable field or a describe error hides the field rather than risk exposing it.
    private static Boolean isFieldAccessible(Schema.DescribeSObjectResult describeResult, String fieldApiName, AccessLevel accessLevel) {
        try {

            if (accessLevel == System.AccessLevel.SYSTEM_MODE) return true;

            Schema.SObjectField fieldToken = resolveFieldToken(describeResult, fieldApiName);

            if (fieldToken == null) return false;

            return fieldToken.getDescribe().isAccessible();

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AiDataSourceResultProcessor', 'isFieldAccessible');
            return false;
        }
    }

    // A populated parent relationship (e.g. "Account" on Contact) shows up in getPopulatedFieldsAsMap() under its relationship name, not its lookup field's API name (e.g. "AccountId") -
    // fall back to matching on relationship name so parent traversal is checked against the lookup field's own FLS rather than being treated as an unresolvable field.
    private static Schema.SObjectField resolveFieldToken(Schema.DescribeSObjectResult describeResult, String fieldApiName) {

        Schema.SObjectField fieldToken = describeResult.fields.getMap().get(fieldApiName);
        if (fieldToken != null) return fieldToken;

        for (Schema.SObjectField candidateFieldToken : describeResult.fields.getMap().values()) {
            if (fieldApiName.equalsIgnoreCase(candidateFieldToken.getDescribe().getRelationshipName())) return candidateFieldToken;
        }

        return null;
    }
}