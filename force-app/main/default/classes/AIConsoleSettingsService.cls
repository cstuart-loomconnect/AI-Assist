/*
Class Name: AIConsoleSettingsService

=================================================================
=================================================================

Description: The AI Settings tab:

App Settings  (aiAppSettings)   - AIAssistSettings__c org defaults.
UI Settings   (aiUiSettings)    - AIAssistUISettings__c at Org default, Profile or User level. A value is
                                  "Overridden" when the level's row differs from what it would inherit;
                                  "Reset" puts the inherited value back.
User Settings (aiUserSettings)  - each user's AIUserSettings__c row (created by AIAssistUserTrigger when
                                  their AI Assist User Type is set - never created here).
Usage Terms   (aiUsageTerms)    - the current terms version, the policy URL, who has signed, and
                                  publishing a new version (everyone signs again in the chat window).
PII Registry  (aiPiiRegistry)   - AIPIIRegistry__c objects in scope and their PII fields; Sync runs
                                  AIPiiRegistryDispatcher / AIPiiRegistryWorker as the schedule does.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-29     Chandler Stuart          Initial development
*/

public with sharing class AIConsoleSettingsService {

    // =============================================================
    // App Settings
    // =============================================================

    public static AIConsoleDataStructure.AppSettingsView getAppSettings() {

        AIAssistSettings__c settings = AIAssistSettingsService.readAppSettings();
        AIConsoleDataStructure.AppSettingsView view = new AIConsoleDataStructure.AppSettingsView();

        view.isApplicationActive = settings.IsApplicationActive__c != false;
        view.defaultModel = settings.DefaultModelConfiguration__c;
        view.calloutTimeout = settings.CalloutTimeoutMilliseconds__c;
        view.processingLockMinutes = settings.ProcessingLockMinutes__c;
        view.successCodes = splitCodes(settings.AIProviderSuccessStatusCodes__c);
        view.retryCodes = splitCodes(settings.RetryableStatusCodes__c);
        view.defaultMaxIterations = settings.DefaultMaxToolCallingIterations__c;
        view.iterationsCap = settings.MaxToolCallingIterationsCap__c;
        view.callsPerIteration = settings.MaxToolCallsPerIteration__c;
        view.globalTokenBudget = settings.GlobalTokenBudgetPerDay__c;
        view.tokensToday = AITokenUsageService.getGlobalUsage(System.today(), System.today());
        view.isExceptionLoggingEnabled = settings.IsExceptionLoggingEnabled__c != false;
        view.isPlatformLoggingEnabled = settings.IsPlatformLoggingEnabled__c != false;
        view.auditLoggingRecordId = settings.AuditLoggingRecordId__c;
        view.maxPiiRegistryObjects = settings.MaxPIIRegistryObjects__c;
        view.toolingApiVersion = settings.ToolingAPIVersion__c;
        view.emailTemplateId = settings.AIAcknowledgeEmailTemplateId__c;

        for (AIModelConfiguration__c model : [ SELECT Name, DeveloperName__c FROM AIModelConfiguration__c WHERE IsActive__c = true ORDER BY Name ]) {
            view.modelOptions.add(new AIConsoleDataStructure.Option(model.Name + ' (' + model.DeveloperName__c + ')', model.DeveloperName__c));
        }

        view.agentOptions.add(new AIConsoleDataStructure.Option('None · log every agent', ''));
        for (AIAgent__c agent : [ SELECT Id, Name FROM AIAgent__c ORDER BY Name LIMIT 200 ]) view.agentOptions.add(new AIConsoleDataStructure.Option(agent.Name, agent.Id));

        view.emailTemplateOptions.add(new AIConsoleDataStructure.Option('None', ''));
        for (EmailTemplate template : [ SELECT Id, Name FROM EmailTemplate WHERE IsActive = true ORDER BY Name LIMIT 300 ]) view.emailTemplateOptions.add(new AIConsoleDataStructure.Option(template.Name, template.Id));

        List<AIAssistSettings__c> orgRows = [ SELECT LastModifiedBy.Name, LastModifiedDate FROM AIAssistSettings__c WHERE SetupOwnerId = :UserInfo.getOrganizationId() LIMIT 1 ];
        if (!orgRows.isEmpty()) view.lastChangedLabel = 'Last changed by ' + orgRows[0].LastModifiedBy.Name + ', ' + AIConsoleUtility.dayLabel(orgRows[0].LastModifiedDate);

        return view;
    }

    public static AIConsoleDataStructure.AppSettingsView saveAppSettings(AIConsoleDataStructure.AppSettingsView view) {

        if (view == null) throw new AIConsoleDataStructure.AIConsoleException('Nothing to save.');
        if (view.calloutTimeout != null && (view.calloutTimeout < 1000 || view.calloutTimeout > 120000)) throw new AIConsoleDataStructure.AIConsoleException('Callout Timeout must be between 1,000 and 120,000 ms.');
        if (view.iterationsCap != null && view.defaultMaxIterations != null && view.defaultMaxIterations > view.iterationsCap) throw new AIConsoleDataStructure.AIConsoleException('Default Max Iterations can\'t be above the Iterations Cap.');

        List<String> allCodes = new List<String>();
        allCodes.addAll(view.successCodes == null ? new List<String>() : view.successCodes);
        allCodes.addAll(view.retryCodes == null ? new List<String>() : view.retryCodes);
        for (String code : allCodes) {
            if (!Pattern.matches('[1-5][0-9][0-9]', code.trim())) throw new AIConsoleDataStructure.AIConsoleException(code + ' isn\'t an HTTP status code.');
        }

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        if (settings.Id == null) settings.SetupOwnerId = UserInfo.getOrganizationId();

        settings.IsApplicationActive__c = view.isApplicationActive == true;
        settings.DefaultModelConfiguration__c = String.isBlank(view.defaultModel) ? null : view.defaultModel;
        settings.CalloutTimeoutMilliseconds__c = view.calloutTimeout;
        settings.ProcessingLockMinutes__c = view.processingLockMinutes;
        settings.AIProviderSuccessStatusCodes__c = view.successCodes == null ? null : String.join(view.successCodes, ',');
        settings.RetryableStatusCodes__c = view.retryCodes == null ? null : String.join(view.retryCodes, ',');
        settings.DefaultMaxToolCallingIterations__c = view.defaultMaxIterations;
        settings.MaxToolCallingIterationsCap__c = view.iterationsCap;
        settings.MaxToolCallsPerIteration__c = view.callsPerIteration;
        settings.GlobalTokenBudgetPerDay__c = view.globalTokenBudget;
        settings.IsExceptionLoggingEnabled__c = view.isExceptionLoggingEnabled != false;
        settings.IsPlatformLoggingEnabled__c = view.isPlatformLoggingEnabled != false;
        settings.AuditLoggingRecordId__c = String.isBlank(view.auditLoggingRecordId) ? null : view.auditLoggingRecordId;
        settings.MaxPIIRegistryObjects__c = view.maxPiiRegistryObjects;
        settings.ToolingAPIVersion__c = view.toolingApiVersion;
        settings.AIAcknowledgeEmailTemplateId__c = String.isBlank(view.emailTemplateId) ? null : view.emailTemplateId;

        upsert settings;
        return getAppSettings();
    }

    private static List<String> splitCodes(String codes) {
        List<String> result = new List<String>();
        if (String.isBlank(codes)) return result;
        for (String code : codes.split(',')) if (String.isNotBlank(code)) result.add(code.trim());
        return result;
    }

    // =============================================================
    // UI Settings
    // =============================================================

    private static final List<String> UI_FIELDS = new List<String>{
        'IsMaintenanceMode__c', 'IsUserInitiatedChatEnabled__c', 'IsFeedbackEnabled__c', 'AllowInlineWorkflowActions__c', 'SuggestedActionsDisplay__c',
        'TypingIndicatorEnabled__c', 'ShowExecutionTraceToUser__c', 'ShowTimestampOnMessages__c', 'MaxVisibleMessageHistory__c'
    };

    private static final Map<String, String> UI_HELP = new Map<String, String>{
        'IsMaintenanceMode__c' => 'Shows a maintenance screen instead of the chat.',
        'IsUserInitiatedChatEnabled__c' => 'Users can start new conversations. Off, open ones can still carry on.',
        'IsFeedbackEnabled__c' => 'Thumbs up and down under replies.',
        'AllowInlineWorkflowActions__c' => 'Suggested actions can be run from the chat.',
        'SuggestedActionsDisplay__c' => 'How suggested actions look.',
        'TypingIndicatorEnabled__c' => 'Dots while a reply is being written.',
        'ShowExecutionTraceToUser__c' => 'Users see each step while the agent works.',
        'ShowTimestampOnMessages__c' => 'A time under each message.',
        'MaxVisibleMessageHistory__c' => 'Messages shown before “Show earlier messages”.'
    };

    public static AIConsoleDataStructure.UiSettingsView getUiSettings(String level, String ownerId) {

        String resolvedLevel = level == AIConsoleConstants.LEVEL_PROFILE || level == AIConsoleConstants.LEVEL_USER ? level : AIConsoleConstants.LEVEL_ORG;

        AIConsoleDataStructure.UiSettingsView view = new AIConsoleDataStructure.UiSettingsView();
        view.level = resolvedLevel;

        if (resolvedLevel == AIConsoleConstants.LEVEL_PROFILE) {
            for (Profile profile : [ SELECT Id, Name FROM Profile ORDER BY Name LIMIT 500 ]) view.ownerOptions.add(new AIConsoleDataStructure.Option(profile.Name, profile.Id));
        } else if (resolvedLevel == AIConsoleConstants.LEVEL_USER) {
            for (User aiUser : [ SELECT Id, Name FROM User WHERE IsActive = true AND AIAssistUserType__c != null ORDER BY Name LIMIT 500 ]) view.ownerOptions.add(new AIConsoleDataStructure.Option(aiUser.Name, aiUser.Id));
        }

        if (resolvedLevel == AIConsoleConstants.LEVEL_ORG) {
            view.ownerId = UserInfo.getOrganizationId();
            view.ownerName = 'Org default';
        } else {
            view.ownerId = String.isBlank(ownerId) && !view.ownerOptions.isEmpty() ? view.ownerOptions[0].value : ownerId;
            for (AIConsoleDataStructure.Option option : view.ownerOptions) if (option.value == view.ownerId) view.ownerName = option.label;
        }

        if (String.isBlank(view.ownerId)) return view;

        if (resolvedLevel == AIConsoleConstants.LEVEL_PROFILE) view.userCount = [ SELECT COUNT() FROM User WHERE ProfileId = :view.ownerId AND IsActive = true ];

        // No org row yet - show the field defaults, which is what the chat window uses (AIAssistSettingsService.readUiSettings).
        AIAssistUISettings__c orgDefaults = AIAssistUISettings__c.getOrgDefaults();
        if (orgDefaults == null || orgDefaults.Id == null) orgDefaults = (AIAssistUISettings__c) AIAssistUISettings__c.SObjectType.newSObject(null, true);
        AIAssistUISettings__c inherited = orgDefaults;
        String inheritedFrom = 'Org default';
        AIAssistUISettings__c profileRow;

        if (resolvedLevel == AIConsoleConstants.LEVEL_USER) {
            List<User> owners = [ SELECT ProfileId FROM User WHERE Id = :view.ownerId LIMIT 1 ];
            if (!owners.isEmpty()) {
                profileRow = levelRow(owners[0].ProfileId);
                if (profileRow != null) inherited = AIAssistUISettings__c.getInstance(owners[0].ProfileId);
            }
        }

        AIAssistUISettings__c ownRow = resolvedLevel == AIConsoleConstants.LEVEL_ORG ? orgDefaults : levelRow(view.ownerId);

        Map<String, Schema.SObjectField> fields = Schema.SObjectType.AIAssistUISettings__c.fields.getMap();

        for (String fieldName : UI_FIELDS) {

            Schema.DescribeFieldResult describe = fields.get(fieldName.toLowerCase()).getDescribe();
            Object inheritedValue = normaliseUiValue(fieldName, inherited.get(fieldName));
            Object ownValue = ownRow == null ? inheritedValue : normaliseUiValue(fieldName, ownRow.get(fieldName));

            AIConsoleDataStructure.UiSettingRow row = new AIConsoleDataStructure.UiSettingRow();
            row.key = fieldName;
            row.label = describe.getLabel();
            row.help = UI_HELP.get(fieldName);
            row.type = fieldName == 'SuggestedActionsDisplay__c' ? 'radio' : (describe.getType() == Schema.DisplayType.BOOLEAN ? 'toggle' : 'number');
            row.value = ownValue;
            row.isOverridden = resolvedLevel != AIConsoleConstants.LEVEL_ORG && ownRow != null && ownValue != inheritedValue;

            String rowSource = inheritedFrom;
            if (resolvedLevel == AIConsoleConstants.LEVEL_USER && profileRow != null && normaliseUiValue(fieldName, profileRow.get(fieldName)) != normaliseUiValue(fieldName, orgDefaults.get(fieldName))) rowSource = 'Profile';
            row.sourceLabel = rowSource;
            row.inheritedLabel = displayValue(row.type, inheritedValue);
            row.inheritedValue = inheritedValue;

            if (row.type == 'radio') {
                row.options.add(new AIConsoleDataStructure.Option(AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_CARDS, AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_CARDS));
                row.options.add(new AIConsoleDataStructure.Option(AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_INLINE_BUTTONS, AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_INLINE_BUTTONS));
            }

            if (row.isOverridden) view.overriddenCount++;
            view.rows.add(row);
        }

        return view;
    }

    // values: field API name -> value, for every row on screen. A level with no row yet gets one.
    public static AIConsoleDataStructure.UiSettingsView saveUiSettings(String level, String ownerId, Map<String, Object> values) {

        String resolvedOwner = level == AIConsoleConstants.LEVEL_ORG || String.isBlank(level) ? UserInfo.getOrganizationId() : ownerId;
        if (String.isBlank(resolvedOwner)) throw new AIConsoleDataStructure.AIConsoleException('Pick a ' + level + ' first.');

        AIAssistUISettings__c row = level == AIConsoleConstants.LEVEL_ORG || String.isBlank(level) ? AIAssistUISettings__c.getOrgDefaults() : levelRow(resolvedOwner);
        if (row == null) row = new AIAssistUISettings__c(SetupOwnerId = resolvedOwner);
        if (row.Id == null) row.SetupOwnerId = resolvedOwner;

        for (String fieldName : UI_FIELDS) {
            if (!values.containsKey(fieldName)) continue;
            Object value = values.get(fieldName);

            if (fieldName == 'SuggestedActionsDisplay__c') {
                row.put(fieldName, value == AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_INLINE_BUTTONS ? AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_INLINE_BUTTONS : AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_CARDS);
            } else if (fieldName == 'MaxVisibleMessageHistory__c') {
                Decimal pageSize = value == null || String.isBlank(String.valueOf(value)) ? null : Decimal.valueOf(String.valueOf(value));
                if (pageSize != null && (pageSize < 1 || pageSize > 200)) throw new AIConsoleDataStructure.AIConsoleException('Max Visible Message History must be between 1 and 200.');
                row.put(fieldName, pageSize);
            } else {
                row.put(fieldName, value == true || String.valueOf(value) == 'true');
            }
        }

        upsert row;
        return getUiSettings(level, resolvedOwner);
    }

    private static AIAssistUISettings__c levelRow(String ownerId) {
        List<AIAssistUISettings__c> rows = [ SELECT Id, SetupOwnerId, IsMaintenanceMode__c, IsUserInitiatedChatEnabled__c, IsFeedbackEnabled__c, AllowInlineWorkflowActions__c, SuggestedActionsDisplay__c,
                                                    TypingIndicatorEnabled__c, ShowExecutionTraceToUser__c, ShowTimestampOnMessages__c, MaxVisibleMessageHistory__c
                                             FROM AIAssistUISettings__c WHERE SetupOwnerId = :ownerId LIMIT 1 ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static Object normaliseUiValue(String fieldName, Object value) {
        if (fieldName == 'SuggestedActionsDisplay__c') {
            String text = value == null ? '' : String.valueOf(value).trim();
            return text.equalsIgnoreCase(AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_INLINE_BUTTONS) ? AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_INLINE_BUTTONS : AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_CARDS;
        }
        if (fieldName == 'MaxVisibleMessageHistory__c') return value == null ? null : ((Decimal) value).intValue();
        return value == true;
    }

    private static String displayValue(String type, Object value) {
        if (type == 'toggle') return value == true ? 'On' : 'Off';
        return value == null ? 'blank' : String.valueOf(value);
    }

    // =============================================================
    // User Settings
    // =============================================================

    public static List<AIConsoleDataStructure.UserSettingsRow> getUserSettingsList(String searchText) {

        String currentVersion = getCurrentTermsVersion();
        String search = String.isBlank(searchText) ? '%' : '%' + searchText.trim() + '%';
        List<AIConsoleDataStructure.UserSettingsRow> rows = new List<AIConsoleDataStructure.UserSettingsRow>();

        for (AIUserSettings__c settings : [ SELECT Id, User__c, User__r.Name, User__r.AIAssistUserType__c, User__r.IsActive, AllowedChannels__c, MaxTokensPer24Hours__c, UsageLimitReachedBehavior__c,
                                                   TermsVersionAcknowledged__c, IsActive__c
                                            FROM AIUserSettings__c WHERE User__r.Name LIKE :search ORDER BY IsActive__c DESC, User__r.Name ASC LIMIT 500 ]) {

            Boolean isActive = settings.IsActive__c == true && settings.User__r?.IsActive == true && String.isNotBlank(settings.User__r?.AIAssistUserType__c);

            AIConsoleDataStructure.UserSettingsRow row = new AIConsoleDataStructure.UserSettingsRow();
            row.id = settings.Id;
            row.userId = settings.User__c;
            row.userName = settings.User__r?.Name;
            row.userType = settings.User__r?.AIAssistUserType__c;
            row.isInactive = !isActive;
            row.channelsLabel = isActive ? channelsLabel(settings.AllowedChannels__c) : '—';
            row.maxTokens = isActive ? settings.MaxTokensPer24Hours__c : null;
            row.limitBehavior = isActive ? settings.UsageLimitReachedBehavior__c : '—';
            row.termsLabel = String.isBlank(settings.TermsVersionAcknowledged__c) ? 'Not signed' : 'v' + settings.TermsVersionAcknowledged__c;
            row.termsOutOfDate = isActive && settings.TermsVersionAcknowledged__c != currentVersion;
            if (row.termsOutOfDate) row.termsLabel = (String.isBlank(settings.TermsVersionAcknowledged__c) ? 'Not signed' : 'v' + settings.TermsVersionAcknowledged__c) + ' · re-sign due';
            rows.add(row);
        }

        return rows;
    }

    public static AIConsoleDataStructure.UserSettingsView getUserSettings(Id settingsId) {

        List<AIUserSettings__c> rows = [ SELECT Id, User__c, User__r.Name, User__r.AIAssistUserType__c, IsActive__c, AllowedChannels__c, ConversationVisibilityScope__c, MaxTokensPer24Hours__c,
                                                MaxConversationsPer24Hours__c, MaxConcurrentConversations__c, UsageLimitReachedBehavior__c, WorkflowActionsEnabled__c,
                                                ConversationExportEnabled__c, DebugModeEnabled__c, TermsVersionAcknowledged__c, TermsAcknowledgedDate__c
                                         FROM AIUserSettings__c WHERE Id = :settingsId LIMIT 1 ];
        if (rows.isEmpty()) throw new AIConsoleDataStructure.AIConsoleException('Those user settings no longer exist.');

        AIUserSettings__c settings = rows[0];
        AIConsoleDataStructure.UserSettingsView view = new AIConsoleDataStructure.UserSettingsView();
        view.id = settings.Id;
        view.userId = settings.User__c;
        view.userName = settings.User__r?.Name;
        view.initials = AIConsoleUtility.initials(view.userName);
        view.userType = String.isBlank(settings.User__r?.AIAssistUserType__c) ? 'No type' : settings.User__r.AIAssistUserType__c;
        view.isActive = settings.IsActive__c == true;
        view.allowedChannels = String.isBlank(settings.AllowedChannels__c) ? new List<String>() : settings.AllowedChannels__c.split(AIAssistApplicationConstants.DELIMITER_MULTI_SELECT_SEPARATOR);
        view.channelOptions = AIConsoleAgentService.picklistOptions(AIUserSettings__c.AllowedChannels__c);
        view.visibilityScope = settings.ConversationVisibilityScope__c;
        view.visibilityOptions = AIConsoleAgentService.picklistOptions(AIUserSettings__c.ConversationVisibilityScope__c);
        view.maxTokens = settings.MaxTokensPer24Hours__c;
        view.maxConversations = settings.MaxConversationsPer24Hours__c;
        view.maxConcurrent = settings.MaxConcurrentConversations__c;
        view.limitBehavior = settings.UsageLimitReachedBehavior__c;
        view.limitBehaviorOptions = AIConsoleAgentService.picklistOptions(AIUserSettings__c.UsageLimitReachedBehavior__c);
        view.workflowActionsEnabled = settings.WorkflowActionsEnabled__c != false;
        view.exportEnabled = settings.ConversationExportEnabled__c == true;
        view.debugModeEnabled = settings.DebugModeEnabled__c == true;

        Decimal tokensToday = AITokenUsageService.getUserUsage(settings.User__c, System.today(), System.today());
        Datetime todayStart = Datetime.newInstance(System.today(), Time.newInstance(0, 0, 0, 0));
        Integer conversationsToday = [ SELECT COUNT() FROM AIConversation__c WHERE OwnerId = :settings.User__c AND CreatedDate >= :todayStart ];
        view.usedTodayLabel = 'Used today: ' + AIConsoleUtility.formatNumber(tokensToday) + ' tokens · ' + conversationsToday + (conversationsToday == 1 ? ' conversation' : ' conversations');

        view.termsLabel = String.isBlank(settings.TermsVersionAcknowledged__c) ? 'Terms: not signed yet'
            : 'Terms: version ' + settings.TermsVersionAcknowledged__c + (settings.TermsAcknowledgedDate__c == null ? '' : ', signed ' + settings.TermsAcknowledgedDate__c.format('d MMM yyyy') + ' at ' + settings.TermsAcknowledgedDate__c.format('HH:mm'));

        return view;
    }

    public static AIConsoleDataStructure.UserSettingsView saveUserSettings(AIConsoleDataStructure.UserSettingsView view) {

        if (view == null || view.id == null) throw new AIConsoleDataStructure.AIConsoleException('Pick a user first.');

        for (Decimal limitValue : new List<Decimal>{ view.maxTokens, view.maxConversations, view.maxConcurrent }) {
            if (limitValue != null && limitValue < 0) throw new AIConsoleDataStructure.AIConsoleException('Limits can\'t be negative.');
        }

        update new AIUserSettings__c(
            Id = view.id,
            AllowedChannels__c = view.allowedChannels == null || view.allowedChannels.isEmpty() ? null : String.join(view.allowedChannels, AIAssistApplicationConstants.DELIMITER_MULTI_SELECT_SEPARATOR),
            ConversationVisibilityScope__c = view.visibilityScope,
            MaxTokensPer24Hours__c = view.maxTokens,
            MaxConversationsPer24Hours__c = view.maxConversations,
            MaxConcurrentConversations__c = view.maxConcurrent,
            UsageLimitReachedBehavior__c = view.limitBehavior,
            WorkflowActionsEnabled__c = view.workflowActionsEnabled == true,
            ConversationExportEnabled__c = view.exportEnabled == true,
            DebugModeEnabled__c = view.debugModeEnabled == true
        );

        return getUserSettings(view.id);
    }

    private static String channelsLabel(String channels) {
        if (String.isBlank(channels)) return 'All 3';
        List<String> values = channels.split(AIAssistApplicationConstants.DELIMITER_MULTI_SELECT_SEPARATOR);
        if (values.size() >= 3) return 'All 3';
        List<String> shortNames = new List<String>();
        for (String value : values) shortNames.add(value.removeEnd(' Chat'));
        return String.join(shortNames, ', ');
    }

    // =============================================================
    // Usage Terms
    // =============================================================

    public static String getCurrentTermsVersion() {
        String version = AIAssistSettings__c.getOrgDefaults().CurrentTermsVersion__c;
        return String.isBlank(version) ? AIAssistApplicationConstants.DEFAULT_TERMS_VERSION : version.trim();
    }

    public static AIConsoleDataStructure.TermsView getTerms() {

        AIConsoleDataStructure.TermsView view = new AIConsoleDataStructure.TermsView();
        view.currentVersion = getCurrentTermsVersion();
        view.nextVersion = nextVersion(view.currentVersion);
        view.policyUrl = AIAssistSettings__c.getOrgDefaults().AIUsagePolicyUrl__c;

        List<String> olderNames = new List<String>();
        for (AIUserSettings__c settings : [ SELECT User__r.Name, TermsVersionAcknowledged__c FROM AIUserSettings__c WHERE IsActive__c = true AND User__r.IsActive = true AND User__r.AIAssistUserType__c != null ORDER BY User__r.Name ]) {
            view.totalUsers++;
            if (settings.TermsVersionAcknowledged__c == view.currentVersion) view.signedCount++;
            else olderNames.add(settings.User__r.Name);
        }

        view.olderCount = olderNames.size();
        view.percent = view.totalUsers == 0 ? 0 : AIConsoleUtility.percent(view.signedCount, view.totalUsers);
        if (!olderNames.isEmpty()) {
            view.olderUsersLabel = olderNames.size() <= 2 ? String.join(olderNames, ' and ')
                : olderNames[0] + ', ' + olderNames[1] + ' and ' + (olderNames.size() - 2) + ' more';
        }

        for (AITermsAcknowledgment__c acknowledgment : [ SELECT Id, User__c, User__r.Name, TermsVersion__c, SignatureText__c, AcknowledgedDate__c, CreatedDate, LoginHistoryId__c
                                                          FROM AITermsAcknowledgment__c ORDER BY AcknowledgedDate__c DESC NULLS LAST, CreatedDate DESC LIMIT 100 ]) {
            Datetime signedAt = acknowledgment.AcknowledgedDate__c == null ? acknowledgment.CreatedDate : acknowledgment.AcknowledgedDate__c;

            AIConsoleDataStructure.Acknowledgment row = new AIConsoleDataStructure.Acknowledgment();
            row.id = acknowledgment.Id;
            row.userId = acknowledgment.User__c;
            row.userName = acknowledgment.User__r?.Name;
            row.version = acknowledgment.TermsVersion__c;
            row.signature = acknowledgment.SignatureText__c;
            row.acknowledgedLabel = signedAt.date() >= System.today().addDays(-1) ? AIConsoleUtility.dateTimeLabel(signedAt) : signedAt.format('d MMM yyyy, HH:mm');
            row.loginHistoryId = acknowledgment.LoginHistoryId__c;
            view.acknowledgments.add(row);
        }

        return view;
    }

    public static AIConsoleDataStructure.TermsView savePolicyUrl(String policyUrl) {

        String url = policyUrl == null ? null : policyUrl.trim();
        if (String.isNotBlank(url) && !url.startsWithIgnoreCase('https://')) throw new AIConsoleDataStructure.AIConsoleException('The AI Usage Policy URL must start with https://.');

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        if (settings.Id == null) settings.SetupOwnerId = UserInfo.getOrganizationId();
        settings.AIUsagePolicyUrl__c = String.isBlank(url) ? null : url;
        upsert settings;

        return getTerms();
    }

    // Everyone signs again before their next message - the chat window compares each user's acknowledged version with this one.
    public static AIConsoleDataStructure.TermsView publishNewVersion() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        if (settings.Id == null) settings.SetupOwnerId = UserInfo.getOrganizationId();
        settings.CurrentTermsVersion__c = nextVersion(getCurrentTermsVersion());
        upsert settings;

        return getTerms();
    }

    // 3 -> 4, 1.0 -> 2.0, anything else gets ".1" added.
    public static String nextVersion(String version) {
        if (String.isBlank(version)) return '1';
        if (Pattern.matches('\\d+', version)) return String.valueOf(Integer.valueOf(version) + 1);
        if (Pattern.matches('\\d+\\.\\d+', version)) return (Integer.valueOf(version.substringBefore('.')) + 1) + '.0';
        return version + '.1';
    }

    // =============================================================
    // PII Registry
    // =============================================================

    public static AIConsoleDataStructure.PiiRegistryView getPiiRegistry() {

        AIConsoleDataStructure.PiiRegistryView view = new AIConsoleDataStructure.PiiRegistryView();
        Decimal maxObjects = AIAssistSettings__c.getOrgDefaults().MaxPIIRegistryObjects__c;
        view.maxObjects = maxObjects == null ? null : maxObjects.intValue();

        List<AIPIIRegistry__c> registries = [ SELECT Id, ObjectAPIName__c, SyncStatus__c, FieldCount__c, LastSynced__c, Active__c FROM AIPIIRegistry__c ORDER BY ObjectAPIName__c LIMIT 200 ];
        Set<Id> registryIds = new Map<Id, AIPIIRegistry__c>(registries).keySet();

        Map<Id, Integer> piiByRegistry = new Map<Id, Integer>();
        for (AggregateResult row : [ SELECT PIIRegistry__c registryId, COUNT(Id) total FROM AIPIIFieldMetadata__c WHERE PIIRegistry__c IN :registryIds AND IsPII__c = true GROUP BY PIIRegistry__c ]) {
            piiByRegistry.put((Id) row.get('registryId'), (Integer) row.get('total'));
        }

        String latestFailure = latestPiiSyncError();

        // Failed first, then the rest by name - what needs fixing sits at the top.
        List<AIConsoleDataStructure.PiiObjectRow> failedRows = new List<AIConsoleDataStructure.PiiObjectRow>();
        List<AIConsoleDataStructure.PiiObjectRow> otherRows = new List<AIConsoleDataStructure.PiiObjectRow>();

        for (AIPIIRegistry__c registry : registries) {
            AIConsoleDataStructure.PiiObjectRow row = new AIConsoleDataStructure.PiiObjectRow();
            row.id = registry.Id;
            row.objectApiName = registry.ObjectAPIName__c;
            row.objectLabel = AIConsoleUtility.objectLabel(registry.ObjectAPIName__c);
            row.syncStatus = String.isBlank(registry.SyncStatus__c) ? AIAssistApplicationConstants.PII_SYNC_STATUS_NOT_SYNCED : registry.SyncStatus__c;
            row.syncVariant = syncVariant(row.syncStatus);
            row.isActive = registry.Active__c == true;
            row.isFailed = row.syncStatus == AIAssistApplicationConstants.PII_SYNC_STATUS_FAILED;

            Boolean isRunning = row.syncStatus == AIAssistApplicationConstants.PII_SYNC_STATUS_IN_PROGRESS || row.syncStatus == AIAssistApplicationConstants.PII_SYNC_STATUS_QUEUED;
            row.fieldCount = isRunning ? null : AIConsoleUtility.toInteger(registry.FieldCount__c);
            row.piiCount = isRunning ? null : (piiByRegistry.containsKey(registry.Id) ? piiByRegistry.get(registry.Id) : 0);
            row.lastSyncedLabel = isRunning ? 'Running now' : (registry.LastSynced__c == null ? 'Never' : AIConsoleUtility.shortDateTimeLabel(registry.LastSynced__c));

            if (row.isFailed) {
                row.failureMessage = latestFailure;
                failedRows.add(row);
                view.failed.add(row);
            } else {
                otherRows.add(row);
            }
        }

        view.objects.addAll(failedRows);
        view.objects.addAll(otherRows);
        view.objectCount = registries.size();
        return view;
    }

    public static List<AIConsoleDataStructure.PiiFieldRow> getPiiFields(Id registryId) {

        List<AIConsoleDataStructure.PiiFieldRow> rows = new List<AIConsoleDataStructure.PiiFieldRow>();
        for (AIPIIFieldMetadata__c field : [ SELECT FieldLabel__c, FieldAPIName__c, DataType__c, PIIFieldType__c, ComplianceGroup__c FROM AIPIIFieldMetadata__c
                                             WHERE PIIRegistry__c = :registryId AND IsPII__c = true ORDER BY FieldLabel__c LIMIT 500 ]) {
            AIConsoleDataStructure.PiiFieldRow row = new AIConsoleDataStructure.PiiFieldRow();
            row.label = field.FieldLabel__c;
            row.apiName = field.FieldAPIName__c;
            row.dataType = String.isBlank(field.DataType__c) ? '—' : field.DataType__c.toLowerCase().capitalize();
            row.piiType = field.PIIFieldType__c;
            row.complianceGroup = field.ComplianceGroup__c;
            rows.add(row);
        }
        return rows;
    }

    // One object ("Retry" / "Resync") or every active one ("Sync all now").
    public static AIConsoleDataStructure.PiiRegistryView syncPii(Id registryId) {

        List<AIPIIRegistry__c> registries = registryId == null
            ? [ SELECT Id FROM AIPIIRegistry__c WHERE Active__c = true ORDER BY LastSynced__c ASC NULLS FIRST ]
            : [ SELECT Id FROM AIPIIRegistry__c WHERE Id = :registryId AND Active__c = true ];
        if (registries.isEmpty()) throw new AIConsoleDataStructure.AIConsoleException(registryId == null ? 'No active objects to sync.' : 'That object isn\'t active, so it can\'t be synced.');

        Decimal configuredMax = AIAssistSettings__c.getOrgDefaults().MaxPIIRegistryObjects__c;
        Integer maxThisRun = Math.min(configuredMax == null ? registries.size() : configuredMax.intValue(), Limits.getLimitFutureCalls() - Limits.getFutureCalls());

        List<AIPIIRegistry__c> toQueue = new List<AIPIIRegistry__c>();
        for (AIPIIRegistry__c registry : registries) {
            if (toQueue.size() >= maxThisRun) break;
            toQueue.add(new AIPIIRegistry__c(Id = registry.Id, SyncStatus__c = AIAssistApplicationConstants.PII_SYNC_STATUS_QUEUED));
        }
        update toQueue;

        for (AIPIIRegistry__c registry : toQueue) AIPiiRegistryWorker.refreshPIIRegistry(registry.Id);
        return getPiiRegistry();
    }

    public static AIConsoleDataStructure.PiiRegistryView addPiiObject(String objectApiName) {

        if (String.isBlank(objectApiName) || Schema.getGlobalDescribe().get(objectApiName) == null) throw new AIConsoleDataStructure.AIConsoleException('Pick an object.');

        Integer existing = [ SELECT COUNT() FROM AIPIIRegistry__c WHERE ObjectAPIName__c = :objectApiName ];
        if (existing > 0) throw new AIConsoleDataStructure.AIConsoleException(objectApiName + ' is already in the registry.');

        AIPIIRegistry__c registry = new AIPIIRegistry__c(
            Name = AIConsoleUtility.objectLabel(objectApiName).left(80),
            ObjectAPIName__c = objectApiName,
            Active__c = true,
            SyncStatus__c = AIAssistApplicationConstants.PII_SYNC_STATUS_QUEUED
        );
        insert registry;

        AIPiiRegistryWorker.refreshPIIRegistry(registry.Id);
        return getPiiRegistry();
    }

    private static String latestPiiSyncError() {
        List<AIPlatformLog__c> logs = [ SELECT ExceptionMessage__c FROM AIPlatformLog__c WHERE ClassName__c LIKE 'AIPiiRegistry%' ORDER BY CreatedDate DESC LIMIT 1 ];
        return logs.isEmpty() ? null : logs[0].ExceptionMessage__c;
    }

    private static String syncVariant(String status) {
        if (status == AIAssistApplicationConstants.PII_SYNC_STATUS_SYNCED) return 'ok';
        if (status == AIAssistApplicationConstants.PII_SYNC_STATUS_FAILED) return 'err';
        if (status == AIAssistApplicationConstants.PII_SYNC_STATUS_IN_PROGRESS || status == AIAssistApplicationConstants.PII_SYNC_STATUS_QUEUED) return 'info';
        return '';
    }
}
