/*
Class Name: AIPiiRegistryWorker

=================================================================
=================================================================

Description: Future worker that syncs a single AIPIIRegistry__c object's field metadata.
Queries the Tooling API's FieldDefinition object for that object's fields, upserts one
AIPIIFieldMetadata__c row per field (matched on FieldKey__c), and updates the parent
registry's SyncStatus__c / LastSynced__c. One future call is made per object - callers must
respect the org's @future call ceiling when dispatching multiple objects in one transaction.
The Tooling API version called is read from AIAssistSettings__c.ToolingAPIVersion__c so it
can be bumped after an org API version upgrade without a code change.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPiiRegistryWorker {

    // Test-only override so Platform Limit exhaustion can be simulated deterministically, since the real Limits values always start fresh in a future method's own transaction.
    @TestVisible private static Boolean isTestCalloutLimitReached = false;

    @future(callout=true)
    public static void refreshPIIRegistry(Id registryId) {
        try {

            AIPIIRegistry__c registry = [SELECT Id, ObjectAPIName__c, MaxFieldsToQuery__c FROM AIPIIRegistry__c WHERE Id =:registryId LIMIT 1];

            // No DML happens before the callout below - Salesforce blocks a callout once any DML has been issued in the same transaction ("uncommitted work pending"), so the In Progress transition is skipped and the registry goes straight from Queued to its final Synced/Failed state.

            // Defend against ever reaching this point with no callout headroom left in the transaction - fail fast with a clear message rather than letting the callout throw.
            if (isTestCalloutLimitReached || Limits.getCallouts() >= Limits.getLimitCallouts()) throw new CalloutException('No callouts remaining in this transaction - skipping Tooling API sync for ' + registry.ObjectAPIName__c + '.');

            // Always bound the query, even when MaxFieldsToQuery__c is blank, so a sync can never pull an unbounded number of fields for one object.
            Integer maxFieldsToQuery = registry.MaxFieldsToQuery__c != null ? Integer.valueOf(registry.MaxFieldsToQuery__c) : AIAssistApplicationConstants.DEFAULT_MAX_PII_FIELDS_TO_QUERY;

            String toolingAPIVersion = AIAssistSettingsService.getSettings().ToolingAPIVersion__c;
            if (String.isBlank(toolingAPIVersion)) toolingAPIVersion = AIAssistApplicationConstants.DEFAULT_TOOLING_API_VERSION; 

            // Query the Tooling API's FieldDefinition object for every field on the given object. FieldDefinition isn't queryable through standard SOQL, so this goes through a REST callout to the org's own Tooling API instead.
            String query = 'SELECT QualifiedApiName, Label, DataType, ComplianceGroup FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName = \'' + String.escapeSingleQuotes(registry.ObjectAPIName__c) + '\''  + ' LIMIT ' + maxFieldsToQuery;

            HttpRequest request = new HttpRequest();
            request.setEndpoint(Url.getOrgDomainUrl().toExternalForm() + '/services/data/v' + toolingAPIVersion + '/tooling/query/?q=' + EncodingUtil.urlEncode(query, 'UTF-8'));
            request.setMethod('GET');
            request.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());

            HttpResponse response = new Http().send(request);

            if (response.getStatusCode() != 200) throw new CalloutException('Tooling API query failed with status ' + response.getStatusCode() + ': ' + response.getBody());

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
                    String fieldLabel = (String) fieldDefinition.get('Label');
                    String dataType = (String) fieldDefinition.get('DataType');

                    fieldMetadataToUpsert.add(new AIPIIFieldMetadata__c(
                        PIIRegistry__c = registry.Id,
                        FieldKey__c = registry.ObjectAPIName__c + '.' + fieldApiName,
                        FieldAPIName__c = fieldApiName,
                        FieldLabel__c = fieldLabel,
                        DataType__c = dataType,
                        ComplianceGroup__c = complianceGroup,
                        IsPII__c = String.isNotBlank(complianceGroup), // Derived - true whenever a Compliance Group classification is present.
                        PIIFieldType__c = AIPiiFieldTypeClassifier.classify(fieldApiName, fieldLabel, dataType, complianceGroup)
                    ));
                }

                if (!fieldMetadataToUpsert.isEmpty()) {
                    Database.UpsertResult[] upsertResults = Database.upsert(fieldMetadataToUpsert, AIPIIFieldMetadata__c.FieldKey__c, false);
                    AIPlatformLogManager.logExceptions(upsertResults, 'AIPiiRegistryWorker', 'refreshPIIRegistry');
                }
            }

            Database.SaveResult registrySyncedResult = Database.update(new AIPIIRegistry__c(
                Id = registry.Id,
                SyncStatus__c = AIAssistApplicationConstants.PII_SYNC_STATUS_SYNCED,
                LastSynced__c = Datetime.now(),
                CacheResetDate__c = null // Clear so a past-due reset doesn't re-trigger every run once synced.
            ), false);
            AIPlatformLogManager.logExceptions(new List<Database.SaveResult>{ registrySyncedResult }, 'AIPiiRegistryWorker', 'refreshPIIRegistry');

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIPiiRegistryWorker', 'refreshPIIRegistry');
            try {
                Database.SaveResult registryFailedResult = Database.update(new AIPIIRegistry__c(Id = registryId, SyncStatus__c = AIAssistApplicationConstants.PII_SYNC_STATUS_FAILED), false);
                AIPlatformLogManager.logExceptions(new List<Database.SaveResult>{ registryFailedResult }, 'AIPiiRegistryWorker', 'refreshPIIRegistry');
            } catch (Exception innerException) {
                AIPlatformLogManager.logException(innerException, 'AIPiiRegistryWorker', 'refreshPIIRegistry');
            }
        }
    }
}