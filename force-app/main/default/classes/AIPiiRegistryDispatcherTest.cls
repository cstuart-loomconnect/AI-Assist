/*
Class Name: AIPiiRegistryDispatcherTest

=================================================================
=================================================================

Description: Testing utility for the AIPiiRegistryDispatcher scheduled job.

=================================================================
=================================================================
Applicable Classes:

AIPiiRegistryDispatcher: Coverage 100%

Version      Date               Author                   Description
1.0          2026-09-14         Chandler Stuart          Initial development
*/

@IsTest private class AIPiiRegistryDispatcherTest {

    // testScenario1: Registries never synced, previously Failed, or past their Cache Reset Date are marked Queued and dispatched; inactive and not-yet-due registries are left untouched.
    // testScenario2: The number of registries processed in a single run is capped by AIAssistSettings__c.MaxPIIRegistryObjects__c.
    // testScenario3: The number of registries processed is further capped by the org's remaining @future call limit, even when MaxPIIRegistryObjects__c allows more.
    // testScenario4: When no @future calls remain in the transaction, the dispatcher exits without changing any registries.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.MaxPIIRegistryObjects__c = 10;
        upsert settings;

        List<AIPIIRegistry__c> registries = AIAssistTestDataFactory.createAIPIIRegistries(5, 'Opportunity', false);

        // registries[0] is left with default field values - never synced.
        registries[1].SyncStatus__c = AIAssistApplicationConstants.PII_SYNC_STATUS_FAILED;
        registries[2].SyncStatus__c = AIAssistApplicationConstants.PII_SYNC_STATUS_SYNCED;
        registries[2].LastSynced__c = Datetime.now();
        registries[2].CacheResetDate__c = Date.today().addDays(-1); // Due via Cache Reset Date, even though already Synced.
        registries[3].SyncStatus__c = AIAssistApplicationConstants.PII_SYNC_STATUS_SYNCED;
        registries[3].LastSynced__c = Datetime.now(); // Not due - synced recently with no Cache Reset Date.
        registries[4].Active__c = false; // Not due - inactive, even though never synced.

        insert registries;

        // Called directly (rather than within Test.startTest/stopTest) so the assertions below inspect the Queued state the dispatcher leaves behind, before the pending @future calls run.
        new AIPiiRegistryDispatcher().execute(null);

        Map<Id, AIPIIRegistry__c> updated = new Map<Id, AIPIIRegistry__c>(
            [SELECT Id, SyncStatus__c FROM AIPIIRegistry__c WHERE Id IN :registries]
        );

        Assert.areEqual(AIAssistApplicationConstants.PII_SYNC_STATUS_QUEUED, updated.get(registries[0].Id).SyncStatus__c, 'A never-synced registry should be queued.');
        Assert.areEqual(AIAssistApplicationConstants.PII_SYNC_STATUS_QUEUED, updated.get(registries[1].Id).SyncStatus__c, 'A previously Failed registry should be queued.');
        Assert.areEqual(AIAssistApplicationConstants.PII_SYNC_STATUS_QUEUED, updated.get(registries[2].Id).SyncStatus__c, 'A registry past its Cache Reset Date should be queued regardless of prior status.');
        Assert.areEqual(AIAssistApplicationConstants.PII_SYNC_STATUS_SYNCED, updated.get(registries[3].Id).SyncStatus__c, 'A recently synced registry with no pending Cache Reset Date should not be queued.');
        Assert.isFalse(AIAssistApplicationConstants.PII_SYNC_STATUS_QUEUED.equals(updated.get(registries[4].Id).SyncStatus__c), 'An inactive registry should not be queued even if never synced.');
    }

    @IsTest static void testScenario2() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.MaxPIIRegistryObjects__c = 2;
        upsert settings;

        List<AIPIIRegistry__c> registries = AIAssistTestDataFactory.createAIPIIRegistries(5, 'Account', true);

        new AIPiiRegistryDispatcher().execute(null);

        Integer queuedCount = [SELECT COUNT() FROM AIPIIRegistry__c WHERE Id IN :registries AND SyncStatus__c =:AIAssistApplicationConstants.PII_SYNC_STATUS_QUEUED];

        Assert.areEqual(2, queuedCount, 'Only MaxPIIRegistryObjects__c registries should be queued in a single run.');
    }

    @IsTest static void testScenario3() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.MaxPIIRegistryObjects__c = 10;
        upsert settings;

        List<AIPIIRegistry__c> registries = AIAssistTestDataFactory.createAIPIIRegistries(5, 'Contact', true);

        // Consume all but 2 of the org's @future call allowance before the dispatcher runs, so the platform limit - not the setting - becomes the binding cap.
        Integer futureCallsToConsume = Limits.getLimitFutureCalls() - 2;
        for (Integer i = 0; i < futureCallsToConsume; i++) {
            AIPiiRegistryWorker.refreshPIIRegistry(registries[0].Id);
        }

        new AIPiiRegistryDispatcher().execute(null);

        Integer queuedCount = [SELECT COUNT() FROM AIPIIRegistry__c WHERE Id IN :registries AND SyncStatus__c =:AIAssistApplicationConstants.PII_SYNC_STATUS_QUEUED];

        Assert.areEqual(2, queuedCount, 'Only as many registries as remaining @future calls should be queued, even though MaxPIIRegistryObjects__c allows more.');
    }

    @IsTest static void testScenario4() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.MaxPIIRegistryObjects__c = 10;
        upsert settings;

        List<AIPIIRegistry__c> registries = AIAssistTestDataFactory.createAIPIIRegistries(3, 'Lead', true);

        // Consume every @future call the transaction is allowed to make.
        for (Integer i = 0; i < Limits.getLimitFutureCalls(); i++) {
            AIPiiRegistryWorker.refreshPIIRegistry(registries[0].Id);
        }

        new AIPiiRegistryDispatcher().execute(null);

        Integer queuedCount = [SELECT COUNT() FROM AIPIIRegistry__c WHERE Id IN :registries AND SyncStatus__c =:AIAssistApplicationConstants.PII_SYNC_STATUS_QUEUED];

        Assert.areEqual(0, queuedCount, 'No registries should be queued once the @future call allowance is exhausted.');
    }
}