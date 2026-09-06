/*
Class Name: AITermsAcknowledgmentTriggerHandler

=================================================================
=================================================================

Description: Handler for managing AI Terms Acknowledgment events related to AI Assist,
performing the business logic that runs on the AI Terms Acknowledgment trigger.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AITermsAcknowledgmentTriggerHandler {

    private static Boolean isAfterInsertHandlerRunning = false;

    public static void handleAfterInsert(List<AITermsAcknowledgment__c> newAcknowledgments) {
        try {

            if (!isAfterInsertHandlerRunning) {

                isAfterInsertHandlerRunning = true;

                updateUserSettingsTermsAcknowledgment(newAcknowledgments);

            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AITermsAcknowledgmentTriggerHandler', 'handleAfterInsert');
        }
    }

    // Updates the acknowledging User's AIUserSettings__c: TermsAcknowledged__c, TermsVersionAcknowledged__c, and TermsAcknowledgedDate__c.
    private static void updateUserSettingsTermsAcknowledgment(List<AITermsAcknowledgment__c> acknowledgments) {
        try {

            Map<Id, AITermsAcknowledgment__c> latestAcknowledgmentByUserId = new Map<Id, AITermsAcknowledgment__c>(); // Keyed by User__c, keeping only the latest acknowledgment per user in this batch.

            for (AITermsAcknowledgment__c acknowledgment : acknowledgments) {

                if (acknowledgment.User__c == null) continue;

                AITermsAcknowledgment__c latestSoFar = latestAcknowledgmentByUserId.get(acknowledgment.User__c);

                if (latestSoFar == null || acknowledgment.AcknowledgedDate__c > latestSoFar.AcknowledgedDate__c) {
                    latestAcknowledgmentByUserId.put(acknowledgment.User__c, acknowledgment);
                }

            }

            if (latestAcknowledgmentByUserId.isEmpty()) return;

            List<AIUserSettings__c> settingsToUpdate = new List<AIUserSettings__c>();

            for (AIUserSettings__c settings : [SELECT Id, User__c FROM AIUserSettings__c WHERE User__c IN :latestAcknowledgmentByUserId.keySet()]) {

                AITermsAcknowledgment__c acknowledgment = latestAcknowledgmentByUserId.get(settings.User__c);

                settings.TermsAcknowledged__c = true;
                settings.TermsVersionAcknowledged__c = acknowledgment.TermsVersion__c;
                settings.TermsAcknowledgedDate__c = acknowledgment.AcknowledgedDate__c;

                settingsToUpdate.add(settings);

            }

            if (!settingsToUpdate.isEmpty()) {
                Database.SaveResult[] updateResults = Database.update(settingsToUpdate, false);
                AIPlatformLogManager.logExceptions(updateResults, 'AITermsAcknowledgmentTriggerHandler', 'updateUserSettingsTermsAcknowledgment');
            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AITermsAcknowledgmentTriggerHandler', 'updateUserSettingsTermsAcknowledgment');
        }
    }
}