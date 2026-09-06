/*
Class Name: AIPiiRegistryWorker

=================================================================
=================================================================

Description: Future worker that syncs a single AIPIIRegistry__c object's field metadata.
Queries the Tooling API's FieldDefinition object for that object's fields, upserts one
AIPIIFieldMetadata__c row per field (matched on FieldKey__c), and updates the parent
registry's SyncStatus__c / LastSynced__c. One future call is made per object - callers must
respect the org's @future call ceiling when dispatching multiple objects in one transaction.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPiiRegistryWorker {

    @future(callout=true)
    public static void refreshPIIRegistry(Id registryId) {
        try {

            AIPIIRegistry__c registry = [SELECT Id, ObjectAPIName__c, MaxFieldsToQuery__c FROM AIPIIRegistry__c WHERE Id =:registryId LIMIT 1];

            update new AIPIIRegistry__c(
                Id = registry.Id,
                SyncStatus__c = AIAssistApplicationConstants.PII_SYNC_STATUS_IN_PROGRESS
            );

            // Query the Tooling API's FieldDefinition object for every field on the given object. FieldDefinition isn't queryable through standard SOQL, so this goes through a REST callout to the org's own Tooling API instead.
            String query = 'SELECT QualifiedApiName, Label, DataType, ComplianceGroup FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName = \'' + String.escapeSingleQuotes(registry.ObjectAPIName__c) + '\''
                            + (registry.MaxFieldsToQuery__c != null ? ' LIMIT ' + Integer.valueOf(registry.MaxFieldsToQuery__c) : '');

            HttpRequest request = new HttpRequest();
            request.setEndpoint(Url.getOrgDomainUrl().toExternalForm() + '/services/data/v62.0/tooling/query/?q=' + EncodingUtil.urlEncode(query, 'UTF-8'));
            request.setMethod('GET');
            request.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());

            HttpResponse response = new Http().send(request);

            if (response.getStatusCode() != 200) {
                throw new CalloutException('Tooling API query failed with status ' + response.getStatusCode() + ': ' + response.getBody());
            }

            Map<String, Object> parsedResponse = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            List<Object> fieldDefinitions = (List<Object>) parsedResponse.get('records');

            // Upsert one AIPIIFieldMetadata__c per field returned by the Tooling API, matched on FieldKey__c (Object API Name + Field API Name).
            if (fieldDefinitions != null && !fieldDefinitions.isEmpty()) {

                List<AIPIIFieldMetadata__c> fieldMetadataToUpsert = new List<AIPIIFieldMetadata__c>();

                for (Object fieldDefinitionRaw : fieldDefinitions) {

                    Map<String, Object> fieldDefinition = (Map<String, Object>) fieldDefinitionRaw;

                    String fieldApiName = (String) fieldDefinition.get('QualifiedApiName');
                    if (String.isBlank(fieldApiName)) continue;

                    String complianceGroup = (String) fieldDefinition.get('ComplianceGroup');

                    fieldMetadataToUpsert.add(new AIPIIFieldMetadata__c(
                        PIIRegistry__c = registry.Id,
                        FieldKey__c = registry.ObjectAPIName__c + '.' + fieldApiName,
                        FieldAPIName__c = fieldApiName,
                        FieldLabel__c = (String) fieldDefinition.get('Label'),
                        DataType__c = (String) fieldDefinition.get('DataType'),
                        ComplianceGroup__c = complianceGroup,
                        IsPII__c = String.isNotBlank(complianceGroup) // Derived - true whenever a Compliance Group classification is present.
                    ));
                }

                if (!fieldMetadataToUpsert.isEmpty()) {
                    Database.UpsertResult[] upsertResults = Database.upsert(fieldMetadataToUpsert, AIPIIFieldMetadata__c.FieldKey__c, false);
                    AIPlatformLogManager.logExceptions(upsertResults, 'AIPiiRegistryWorker', 'refreshPIIRegistry');
                }
            }

            update new AIPIIRegistry__c(
                Id = registry.Id,
                SyncStatus__c = AIAssistApplicationConstants.PII_SYNC_STATUS_SYNCED,
                LastSynced__c = Datetime.now(),
                CacheResetDate__c = null // Clear so a past-due reset doesn't re-trigger every run once synced.
            );

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIPiiRegistryWorker', 'refreshPIIRegistry');
            try {
                update new AIPIIRegistry__c(Id = registryId, SyncStatus__c = AIAssistApplicationConstants.PII_SYNC_STATUS_FAILED);
            } catch (Exception innerException) {
                AIPlatformLogManager.logException(innerException, 'AIPiiRegistryWorker', 'refreshPIIRegistry');
            }
        }
    }
}