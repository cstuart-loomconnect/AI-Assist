/*
Class Name: AIAssistUserDefaultsTest

=================================================================
=================================================================

Description: Testing utility for the AIAssistUserDefaults class.

=================================================================
=================================================================
Applicable Classes:

AIAssistUserDefaults: Coverage 100%

Version      Date               Author                   Description
1.0          2026-09-14         Chandler Stuart          Initial development
*/

@IsTest private class AIAssistUserDefaultsTest {

    // testScenario1: Building defaults for a User produces an AIUserSettings__c populated with the seeded default values.
    // testScenario2: Building defaults for a User links the record to that User via User__c.

    @IsTest static void testScenario1() {

        User user = AIAssistTestDataFactory.createStandardUsers('Standard', 1, true)[0];

        Test.startTest();
            AIUserSettings__c settings = AIAssistUserDefaults.build(user);
        Test.stopTest();

        Assert.areEqual(true, settings.IsActive__c, 'IsActive__c should default to true.');
        Assert.areEqual(false, settings.DebugModeEnabled__c, 'DebugModeEnabled__c should default to false.');
        Assert.areEqual(false, settings.TermsAcknowledged__c, 'TermsAcknowledged__c should default to false.');
        Assert.areEqual(false, settings.WorkflowActionsEnabled__c, 'WorkflowActionsEnabled__c should default to false.');
        Assert.areEqual(false, settings.ConversationExportEnabled__c, 'ConversationExportEnabled__c should default to false.');
        Assert.isNull(settings.MaxTokensPer24Hours__c, 'MaxTokensPer24Hours__c should default to null.');
        Assert.isNull(settings.MaxConcurrentConversations__c, 'MaxConcurrentConversations__c should default to null.');
        Assert.isNull(settings.MaxConversationsPer24Hours__c, 'MaxConversationsPer24Hours__c should default to null.');
        Assert.areEqual(AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY, settings.UsageLimitReachedBehavior__c, 'UsageLimitReachedBehavior__c should default to Block New Conversations Only.');
        Assert.areEqual(AIAssistApplicationConstants.VISIBILITY_MY_CONVERSATIONS_ONLY, settings.ConversationVisibilityScope__c, 'ConversationVisibilityScope__c should default to My Conversations Only.');
        Assert.areEqual( AIAssistApplicationConstants.CHANNEL_RECORD_PAGE_CHAT + AIAssistApplicationConstants.DELIMITER_MULTI_SELECT_SEPARATOR + AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, settings.AllowedChannels__c, 'AllowedChannels__c should default to Record Page Chat and Utility Bar.');
    }

    @IsTest static void testScenario2() {

        User user = AIAssistTestDataFactory.createStandardUsers('Standard', 1, true)[0];

        Test.startTest();
            AIUserSettings__c settings = AIAssistUserDefaults.build(user);
        Test.stopTest();

        Assert.areEqual(user.Id, settings.User__c, 'The generated settings record should be linked to the User it was built for.');
    }
}