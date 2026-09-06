/*
Class Name: AIPiiRegistryDispatcher

=================================================================
=================================================================

Description: Scheduled job that finds AI PII Registry objects due a sync - never synced,
past their Cache Reset Date, or previously Failed - marks them Queued, and dispatches
AIPiiRegistryWorker for each one. Capped per run by AIAssistSettings__c.MaxPIIRegistryObjects__c,
which should be kept at or below the org's @future call ceiling per transaction.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPiiRegistryDispatcher implements Schedulable {

    public void execute(SchedulableContext context) {
        try {

            List<AIPIIRegistry__c> registriesToQueue = new List<AIPIIRegistry__c>(); 
            Integer maxObjectsPerRun = Integer.valueOf(AIAssistSettingsService.getSettings().MaxPIIRegistryObjects__c);

            List<AIPIIRegistry__c> registriesDueForSync = [SELECT Id, ObjectAPIName__c FROM AIPIIRegistry__c WHERE Active__c = TRUE 
                                                            AND ( LastSynced__c = null OR SyncStatus__c = :AIAssistApplicationConstants.PII_SYNC_STATUS_FAILED OR (CacheResetDate__c != null AND CacheResetDate__c <= TODAY))
                                                            ORDER BY LastSynced__c ASC NULLS FIRST
                                                            LIMIT :maxObjectsPerRun
                                                        ];

            if (registriesDueForSync.isEmpty()) return;

            for (AIPIIRegistry__c registry : registriesDueForSync) {
                registriesToQueue.add(new AIPIIRegistry__c(
                    Id = registry.Id,
                    SyncStatus__c = AIAssistApplicationConstants.PII_SYNC_STATUS_QUEUED
                ));
            }

            Database.SaveResult[] updateResults = Database.update(registriesToQueue, false);
            AIPlatformLogManager.logExceptions(updateResults, 'AIPiiRegistryDispatcher', 'execute');

            for (AIPIIRegistry__c registry : registriesDueForSync) {
                AIPiiRegistryWorker.refreshPIIRegistry(registry.Id);
            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIPiiRegistryDispatcher', 'execute');
        }
    }
}