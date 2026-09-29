/*
Class Name: AIChatStateService

=================================================================
=================================================================

Description: The settings behind AIChatController.ChatContext.state - maintenance, app inactive,
channel not allowed and terms version are all decided here. Also the canonical read of the running
user's AIUserSettings__c row (getUserSettings), since almost every other AIChatController service
needs it to build a UiSettings or UserState.

Reads app/UI settings through AIAssistSettingsService.readAppSettings() / readUiSettings()
rather than a per-transaction cache, so a settings change is always reflected on the next call - see
AIChatController for the full state machine this feeds into.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-28     Chandler Stuart          Split out of AIChatController.
1.1          2026-09-29     Chandler Stuart          getUserSettings reads the user's own AIUserSettings__c row without sharing - it's owned by the admin who set them up, so AI Assist Users never got their debug/export/channel/limit settings. IsUserInitiatedChatEnabled__c replaces DisableUserInitiatedChat__c.
*/

public with sharing class AIChatStateService {

    // No AIUserSettings__c row means the defaults apply everywhere this is read.
    public static AIUserSettings__c getUserSettings() {
        return new SystemContext().getOwnUserSettings(UserInfo.getUserId());
    }

    public static AIChatDataStructure.UiSettings buildUiSettings(AIAssistUISettings__c uiSettings) {

        AIChatDataStructure.UiSettings ui = new AIChatDataStructure.UiSettings();
        ui.showTimestamps = uiSettings.ShowTimestampOnMessages__c == true;
        ui.feedbackEnabled = uiSettings.IsFeedbackEnabled__c != false;
        ui.typingIndicatorEnabled = uiSettings.TypingIndicatorEnabled__c != false;
        ui.showExecutionTrace = uiSettings.ShowExecutionTraceToUser__c == true;
        ui.inlineActionsEnabled = uiSettings.AllowInlineWorkflowActions__c != false;
        ui.newChatsDisabled = uiSettings.IsUserInitiatedChatEnabled__c == false;

        Boolean isInlineButtons = uiSettings.SuggestedActionsDisplay__c != null && uiSettings.SuggestedActionsDisplay__c.trim().equalsIgnoreCase(AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_INLINE_BUTTONS);
        ui.suggestedActionsDisplay = isInlineButtons ? AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_INLINE_BUTTONS : AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_CARDS;

        Boolean hasPageSize = uiSettings.MaxVisibleMessageHistory__c != null && uiSettings.MaxVisibleMessageHistory__c >= 1;
        ui.messagePageSize = hasPageSize ? uiSettings.MaxVisibleMessageHistory__c.intValue() : AIAssistApplicationConstants.CHAT_DEFAULT_MESSAGE_PAGE_SIZE;

        return ui;
    }

    // No AIUserSettings__c row means the defaults - no debug, no export, Workflow Actions allowed (matching AIConversationMessageService, which treats no row as unrestricted).
    public static AIChatDataStructure.UserState buildUserState(AIUserSettings__c userSettings) {

        AIChatDataStructure.UserState user = new AIChatDataStructure.UserState();
        user.userId = UserInfo.getUserId();
        user.firstName = UserInfo.getFirstName();

        if (userSettings == null) return user;

        user.debugMode = userSettings.DebugModeEnabled__c == true;
        user.exportEnabled = userSettings.ConversationExportEnabled__c == true;
        user.workflowActionsEnabled = userSettings.WorkflowActionsEnabled__c != false;

        return user;
    }

    // Same rule as AIConversationMessageService: no row, no allow-list or no channel means allowed.
    public static Boolean isChannelAllowed(AIUserSettings__c userSettings, String channel) {

        if (userSettings == null || String.isBlank(userSettings.AllowedChannels__c) || String.isBlank(channel)) return true;
        return new Set<String>(userSettings.AllowedChannels__c.split(AIAssistApplicationConstants.DELIMITER_MULTI_SELECT_SEPARATOR)).contains(channel);
    }

    public static AIChatDataStructure.TermsState buildTermsState(AIAssistSettings__c appSettings) {

        AIChatDataStructure.TermsState terms = new AIChatDataStructure.TermsState();
        terms.version = getCurrentTermsVersion(appSettings);
        terms.policyUrl = appSettings.AIUsagePolicyUrl__c;

        Integer acknowledgments = [ SELECT COUNT() FROM AITermsAcknowledgment__c WHERE User__c = :UserInfo.getUserId() AND TermsVersion__c = :terms.version ];
        terms.required = acknowledgments == 0;

        return terms;
    }

    public static String getCurrentTermsVersion(AIAssistSettings__c appSettings) {
        return String.isBlank(appSettings.CurrentTermsVersion__c) ? AIAssistApplicationConstants.DEFAULT_TERMS_VERSION : appSettings.CurrentTermsVersion__c.trim();
    }

    // AIUserSettings__c is Private and each row is owned by whoever set the user's AI Assist User Type (AIAssistUserTriggerHandler's queueable), so an AI Assist User
    // can't see their own row through sharing - debug mode, export, channels and limits would silently never apply. Only the running user's own row is ever read here.
    // WITH SYSTEM_MODE because SOQL in this package's API version enforces object/field access, and AI Assist Users only get read on some AIUserSettings__c fields.
    private without sharing class SystemContext {

        public AIUserSettings__c getOwnUserSettings(Id userId) {

            List<AIUserSettings__c> settings = [ SELECT Id, IsActive__c, AllowedChannels__c, DebugModeEnabled__c, ConversationExportEnabled__c, WorkflowActionsEnabled__c,
                                                        MaxTokensPer24Hours__c, MaxConversationsPer24Hours__c, MaxConcurrentConversations__c, UsageLimitReachedBehavior__c
                                                 FROM AIUserSettings__c
                                                 WHERE User__c = :userId
                                                 WITH SYSTEM_MODE
                                                 LIMIT 1 ];

            return settings.isEmpty() ? null : settings[0];
        }
    }
}
