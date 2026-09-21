/*
Class Name: AITermsAcknowledgmentTriggerTest

=================================================================
=================================================================

Description: Testing utility for the AI Terms Acknowledgment Trigger.

=================================================================
=================================================================
Applicable Classes:

AITermsAcknowledgmentTrigger: Coverage 100%
AITermsAcknowledgmentTriggerHandler: Coverage 87%

Version      Date               Author                   Description
1.0          2026-09-10         Chandler Stuart          Initial development
*/

@IsTest private class AITermsAcknowledgmentTriggerTest {

    // testScenario1: Bulk inserting two AITermsAcknowledgment__c records for the same User updates that User's AIUserSettings__c using only the latest acknowledgment in the batch.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = true;
        settings.DisableExceptionLogging__c = false;
        upsert settings;

        User testUser = AIAssistTestDataFactory.createStandardUsers('', 1, true)[0];
        AIAssistTestDataFactory.createAIUserSettings(testUser.Id, true);
    }

    @IsTest static void testScenario1() {

        Id testUserId = [SELECT User__c FROM AIUserSettings__c LIMIT 1].User__c;

        AITermsAcknowledgment__c olderAcknowledgment = AIAssistTestDataFactory.createAITermsAcknowledgments(testUserId, Date.today().addDays(-1), 1, false)[0];
        olderAcknowledgment.TermsVersion__c = '1.0';

        AITermsAcknowledgment__c newerAcknowledgment = AIAssistTestDataFactory.createAITermsAcknowledgments(testUserId, Date.today(), 1, false)[0];
        newerAcknowledgment.TermsVersion__c = '2.0';

        Test.startTest();
            insert new List<AITermsAcknowledgment__c>{ olderAcknowledgment, newerAcknowledgment };
        Test.stopTest();

        AIUserSettings__c updatedSettings = [SELECT TermsAcknowledged__c, TermsVersionAcknowledged__c, TermsAcknowledgedDate__c FROM AIUserSettings__c WHERE User__c = :testUserId];

        Assert.isTrue(updatedSettings.TermsAcknowledged__c, 'TermsAcknowledged__c should be set to true.');
        Assert.areEqual('2.0', updatedSettings.TermsVersionAcknowledged__c, 'Only the latest acknowledgment in the batch should be reflected.');
        Assert.areEqual(Date.today(), updatedSettings.TermsAcknowledgedDate__c, 'TermsAcknowledgedDate__c should be the latest acknowledgment\'s date.');
    }
}