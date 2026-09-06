/*
Class Name: AIAssistUserDefaults

=================================================================
=================================================================

Description: Builds a fully populated AIUserSettings__c record for a User at creation
time. Seed values are set explicitly here so the starting configuration lives in one
place, grouped into sections that mirror logical areas of the settings object. These
apply only at creation - nothing re-applies them afterwards.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/
public without sharing class AIAssistUserDefaults {

    public static AIUserSettings__c build(User user) {
        return new AIAssistUser().toSObject(user);
    }

    public class AIAssistUser {

        public Boolean isActive = true;
        public LimitsSection limits = new LimitsSection();
        public AccessSection access = new AccessSection();
        public WorkflowSection workflow = new WorkflowSection();
        public ComplianceSection compliance = new ComplianceSection();

        public AIUserSettings__c toSObject(User user) {
            return new AIUserSettings__c(
                User__c = user.Id,
                IsActive__c = isActive,
                AllowedChannels__c = access.allowedChannels,
                DebugModeEnabled__c = workflow.debugModeEnabled,
                TermsAcknowledged__c = compliance.termsAcknowledged,
                MaxTokensPer24Hours__c = limits.maxTokensPer24Hours,
                WorkflowActionsEnabled__c = workflow.workflowActionsEnabled,
                UsageLimitReachedBehavior__c = limits.usageLimitReachedBehavior,
                MaxConcurrentConversations__c = limits.maxConcurrentConversations,
                MaxConversationsPer24Hours__c = limits.maxConversationsPer24Hours,
                ConversationExportEnabled__c = workflow.conversationExportEnabled,
                ConversationVisibilityScope__c = access.conversationVisibilityScope 
            );
        }
    }

    // Who can see conversations and where the assistant can be used.
    public class AccessSection {
        public String conversationVisibilityScope = AIAssistApplicationConstants.VISIBILITY_MY_CONVERSATIONS_ONLY;
        public String allowedChannels = AIAssistApplicationConstants.CHANNEL_RECORD_PAGE_CHAT + AIAssistApplicationConstants.DELIMITER_MULTI_SELECT_SEPARATOR + AIAssistApplicationConstants.CHANNEL_UTILITY_BAR;
    }

    // Feature toggles that affect how the assistant behaves day-to-day.
    public class WorkflowSection {
        public Boolean debugModeEnabled = false;
        public Boolean workflowActionsEnabled = false;
        public Boolean conversationExportEnabled = false;
    }

    // Acknowledgement state.
    public class ComplianceSection {
        public Boolean termsAcknowledged = false;
        public String termsAcknowLedgedStatus = AIAssistApplicationConstants.TERMS_ACKNOWLEDGED_STATUS_NOT_SENT;
    }

    // Rate and usage limits.
    public class LimitsSection {
        public Decimal maxTokensPer24Hours = null;
        public Decimal maxConcurrentConversations = null;
        public Decimal maxConversationsPer24Hours = null;
        public String usageLimitReachedBehavior = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY;
    }
}