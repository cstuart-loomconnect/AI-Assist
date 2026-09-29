/*
Class Name: AIChatUsageService

=================================================================
=================================================================

Description: The usage meter shown in the chat window and the three UsageLimitReachedBehavior__c
modes (notify only, block new messages, block new conversations only). Sits on top of
AITokenUsageService for the token count itself - this class only adds the AIUserSettings__c limits
and decides what the window should show once one is reached.

Mirrors AIConversationMessageService.isWithinUsageLimits so the window can warn before the user
hits a refusal: the same LAST_N_DAYS:1 window, the same behaviour per UsageLimitReachedBehavior__c.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-28     Chandler Stuart          Split out of AIChatController.
*/

public with sharing class AIChatUsageService {

    public static AIChatDataStructure.UsageState buildUsageState(AIUserSettings__c userSettings) {

        AIChatDataStructure.UsageState usage = new AIChatDataStructure.UsageState();
        Id userId = UserInfo.getUserId();

        usage.tokensUsed = AITokenUsageService.getUserUsage(userId, Date.today().addDays(-1), Date.today());

        if (userSettings == null || !userSettings.IsActive__c) return usage;

        usage.tokenLimit = userSettings.MaxTokensPer24Hours__c;
        usage.behavior = userSettings.UsageLimitReachedBehavior__c;

        Boolean isTokenLimitReached = usage.tokenLimit != null && usage.tokensUsed >= usage.tokenLimit;

        Boolean isConversationLimitReached = false;
        if (userSettings.MaxConversationsPer24Hours__c != null) {
            Integer conversationsLast24Hours = [ SELECT COUNT() FROM AIConversation__c WHERE OwnerId = :userId AND CreatedDate = LAST_N_DAYS:1 ];
            isConversationLimitReached = conversationsLast24Hours >= userSettings.MaxConversationsPer24Hours__c;
        }

        Boolean isConcurrentLimitReached = false;
        if (userSettings.MaxConcurrentConversations__c != null) {
            Integer activeConversations = [ SELECT COUNT() FROM AIConversation__c WHERE OwnerId = :userId AND Status__c = :AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE ];
            isConcurrentLimitReached = activeConversations >= userSettings.MaxConcurrentConversations__c;
        }

        Boolean isAnyLimitReached = isTokenLimitReached || isConversationLimitReached || isConcurrentLimitReached;

        if (usage.behavior == AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY) {
            usage.notifyOnly = isAnyLimitReached;
        } else if (usage.behavior == AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES) {
            usage.blockMessages = isTokenLimitReached;
            usage.blockNewConversations = isAnyLimitReached;
        } else if (usage.behavior == AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY) {
            usage.blockNewConversations = isAnyLimitReached;
        }

        usage.limitReached = usage.notifyOnly || usage.blockMessages || usage.blockNewConversations;
        if (usage.limitReached) usage.resetsInMinutes = getMinutesUntilUsageResets(userId, usage.tokenLimit, isTokenLimitReached);

        return usage;
    }

    // LAST_N_DAYS:1 covers yesterday and today, so yesterday's usage drops off at midnight. If today's usage alone is already over the token limit, it takes until the midnight after.
    private static Integer getMinutesUntilUsageResets(Id userId, Decimal tokenLimit, Boolean isTokenLimitReached) {

        Datetime nextMidnight = Datetime.newInstance(Date.today().addDays(1), Time.newInstance(0, 0, 0, 0));
        Long minutesUntilMidnight = (nextMidnight.getTime() - System.now().getTime()) / 60000;

        if (isTokenLimitReached && tokenLimit != null && AITokenUsageService.getUserUsage(userId, Date.today(), Date.today()) >= tokenLimit) minutesUntilMidnight += 24 * 60;

        return Math.max(1, minutesUntilMidnight.intValue());
    }
}