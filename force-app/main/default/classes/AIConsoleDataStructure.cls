/*
Class Name: AIConsoleDataStructure

=================================================================
=================================================================

Description: The response shapes returned to the AI Assist console LWCs (aiTabPage and every section
component it loads), and the small pieces shared by every AIConsoleController service
(AIConsoleNavService, AIConsoleHomeService, AIConsoleListService, AIConsoleAgentService,
AIConsoleWizardService, AIConsoleLibraryService, AIConsoleSoqlBuilderService, AIConsoleActivityService,
AIConsoleSettingsService). Kept in one place so those services can pass the same wrapper types between
each other without depending on AIConsoleController itself.

AIConsoleException is the one exception type every service throws for a refusal the console should
show verbatim (a missing required field, a section the user can't open) - AIConsoleController unwraps
it without extra logging, since it isn't a failure.

Kept separate from AIChatDataStructure on purpose: the console and the chat window share no Apex.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-29     Chandler Stuart          Initial development
*/

public class AIConsoleDataStructure {

    public class AIConsoleException extends Exception {}

    // =============================================================
    // Shared
    // =============================================================

    public class Option {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String description;
        @AuraEnabled public Integer count;

        public Option() {} // For JSON.deserialize.

        public Option(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    // Where a click should take the user - a tab (AINavTab__mdt DeveloperName), optionally a section in it and a view within that section.
    public class NavTarget {
        @AuraEnabled public String tab;
        @AuraEnabled public String section;
        @AuraEnabled public String view;
        @AuraEnabled public String recordId;
        @AuraEnabled public Integer step;

        public NavTarget() {} // For JSON.deserialize.

        public NavTarget(String tab, String section, String view, String recordId) {
            this.tab = tab;
            this.section = section;
            this.view = view;
            this.recordId = recordId;
        }
    }

    // =============================================================
    // Navigation (AINavTab__mdt / AINavTabSection__mdt)
    // =============================================================

    public class TabConfig {
        @AuraEnabled public String tabName;
        @AuraEnabled public String label;
        @AuraEnabled public String description;
        @AuraEnabled public Boolean isActive = true;
        @AuraEnabled public Boolean isDefaultLanding = false;
        @AuraEnabled public String externalUrl;
        @AuraEnabled public Boolean openInNewTab = false;
        @AuraEnabled public List<SectionConfig> sections = new List<SectionConfig>();
        @AuraEnabled public List<TabLink> tabs = new List<TabLink>();
    }

    // Every active tab, so a section can link across tabs without knowing the org's namespace.
    public class TabLink {
        @AuraEnabled public String tabName;
        @AuraEnabled public String label;
        @AuraEnabled public String navItemApiName;
        @AuraEnabled public String externalUrl;
        @AuraEnabled public Boolean openInNewTab = false;
    }

    public class SectionConfig {
        @AuraEnabled public String developerName;
        @AuraEnabled public String label;
        @AuraEnabled public String sectionType;
        @AuraEnabled public String componentName;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String filterCriteria;
        @AuraEnabled public Integer maxRecords;
        @AuraEnabled public String icon;
        @AuraEnabled public String width;
        @AuraEnabled public Boolean collapsedByDefault = false;
        @AuraEnabled public String externalUrl;
        @AuraEnabled public Boolean openInNewTab = false;
        @AuraEnabled public String requiresPermissionSet;
        @AuraEnabled public Boolean isLocked = false;
        @AuraEnabled public Boolean hasBadge = false;
        @AuraEnabled public Integer badgeCount;
        @AuraEnabled public Integer displayOrder;
    }

    // =============================================================
    // Home
    // =============================================================

    public class HomeSummary {
        @AuraEnabled public String firstName;
        @AuraEnabled public String greeting;
        @AuraEnabled public String dateLabel;
        @AuraEnabled public Integer days;
        @AuraEnabled public Integer activeAgents = 0;
        @AuraEnabled public Integer testModeAgents = 0;
        @AuraEnabled public Integer draftAgents = 0;
        @AuraEnabled public Integer conversationsToday = 0;
        @AuraEnabled public Integer usersToday = 0;
        @AuraEnabled public Integer recordsToday = 0;
        @AuraEnabled public Integer helpfulPercent;
        @AuraEnabled public Integer ratingCount = 0;
        @AuraEnabled public Integer violationsLast7Days = 0;
        @AuraEnabled public Integer highViolations = 0;
        @AuraEnabled public Integer blockedViolations = 0;
        @AuraEnabled public Decimal tokensToday = 0;
        @AuraEnabled public Decimal tokenBudget;
        @AuraEnabled public Integer tokenPercent;
    }

    public class ConversationTrend {
        @AuraEnabled public List<TrendPoint> points = new List<TrendPoint>();
        @AuraEnabled public Integer maxValue = 0;
        @AuraEnabled public Integer scaleMax = 0;
        @AuraEnabled public Integer total = 0;
    }

    public class TrendPoint {
        @AuraEnabled public Date day;
        @AuraEnabled public String label;
        @AuraEnabled public Integer count = 0;
        @AuraEnabled public Boolean isToday = false;
    }

    public class AttentionItem {
        @AuraEnabled public String kind;
        @AuraEnabled public String title;
        @AuraEnabled public String detail;
        @AuraEnabled public NavTarget target;
    }

    // =============================================================
    // Generic lists (aiRecordList / aiConsoleTable)
    // =============================================================

    public class ListResult {
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String eyebrow;
        @AuraEnabled public String title;
        @AuraEnabled public String icon;
        @AuraEnabled public String primaryActionLabel;
        @AuraEnabled public String primaryAction;
        @AuraEnabled public String secondaryActionLabel;
        @AuraEnabled public String secondaryAction;
        @AuraEnabled public String bannerHtml;
        @AuraEnabled public NavTarget bannerTarget;
        @AuraEnabled public String bannerLinkLabel;
        @AuraEnabled public String countLabel;
        @AuraEnabled public String subtitle;
        @AuraEnabled public String footerNote;
        @AuraEnabled public String detailComponent;
        @AuraEnabled public String rowView;
        @AuraEnabled public NavTarget viewAll;
        @AuraEnabled public List<ListFilter> filters = new List<ListFilter>();
        @AuraEnabled public List<ListColumn> columns = new List<ListColumn>();
        @AuraEnabled public List<ListRow> rows = new List<ListRow>();
        @AuraEnabled public Integer totalCount = 0;
        @AuraEnabled public Boolean hasMore = false;
        @AuraEnabled public Boolean showHeader = true;
    }

    public class ListFilter {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public String type; // select | chips | checkbox
        @AuraEnabled public String value;
        @AuraEnabled public Boolean labelHidden = false;
        @AuraEnabled public Integer width;
        @AuraEnabled public List<Option> options = new List<Option>();
    }

    public class ListColumn {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean alignRight = false;
        @AuraEnabled public Boolean hideLabel = false;
        @AuraEnabled public String width;

        public ListColumn() {} // For JSON.deserialize.

        public ListColumn(String key, String label) {
            this.key = key;
            this.label = label;
        }

        public ListColumn(String key, String label, Boolean alignRight) {
            this(key, label);
            this.alignRight = alignRight;
        }
    }

    public class ListRow {
        @AuraEnabled public String id;
        @AuraEnabled public Boolean isWarning = false;
        @AuraEnabled public Boolean isError = false;
        @AuraEnabled public Boolean isMuted = false;
        @AuraEnabled public List<ListCell> cells = new List<ListCell>();
    }

    // type: text | link | badge | mono | warning | twoLine. A link cell opens its target (another tab/section) or, with no target, the row's own detail.
    public class ListCell {
        @AuraEnabled public String key;
        @AuraEnabled public String type = 'text';
        @AuraEnabled public String value;
        @AuraEnabled public String secondary;
        @AuraEnabled public String variant;
        @AuraEnabled public Boolean bold = false;
        @AuraEnabled public Boolean alignRight = false;
        @AuraEnabled public String extraBadge;
        @AuraEnabled public String extraBadgeVariant;
        @AuraEnabled public Integer violationCount;
        @AuraEnabled public NavTarget target;
        @AuraEnabled public String action;
        @AuraEnabled public String actionLabel;
    }

    // =============================================================
    // Agents
    // =============================================================

    public class AgentRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String objectType;
        @AuraEnabled public String modelName;
        @AuraEnabled public String statusLabel;
        @AuraEnabled public String statusVariant;
        @AuraEnabled public String setupLabel;
        @AuraEnabled public Boolean isSetupComplete = false;
        @AuraEnabled public Integer resumeStep;
        @AuraEnabled public Integer templateCount = 0;
        @AuraEnabled public Integer conversations30Days = 0;
        @AuraEnabled public Datetime lastEdited;
        @AuraEnabled public Boolean isActive = false;
        @AuraEnabled public Boolean isTestMode = false;
    }

    public class AgentList {
        @AuraEnabled public String title;
        @AuraEnabled public Integer totalCount = 0;
        @AuraEnabled public List<AgentRow> rows = new List<AgentRow>();
        @AuraEnabled public List<Option> views = new List<Option>();
    }

    public class AgentRecord {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String developerName;
        @AuraEnabled public String objectType;
        @AuraEnabled public Id modelId;
        @AuraEnabled public String modelName;
        @AuraEnabled public Id ownerId;
        @AuraEnabled public String ownerName;
        @AuraEnabled public Datetime setupLastEdited;
        @AuraEnabled public String statusLabel;
        @AuraEnabled public String statusVariant;
        @AuraEnabled public Boolean isSetupComplete = false;
        @AuraEnabled public Boolean isActive = false;
        @AuraEnabled public Boolean isTestMode = false;
        @AuraEnabled public Integer setupStep;
        @AuraEnabled public List<DetailField> details = new List<DetailField>();
        @AuraEnabled public Map<String, Integer> counts = new Map<String, Integer>();
        @AuraEnabled public List<AgentStat> stats = new List<AgentStat>();
        @AuraEnabled public List<RelatedLine> dataSources = new List<RelatedLine>();
        @AuraEnabled public List<RelatedLine> guardrails = new List<RelatedLine>();
    }

    // One inline-editable field on the agent record's Details card. editor: textarea | select | number.
    public class DetailField {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public String displayValue;
        @AuraEnabled public String value;
        @AuraEnabled public String editor;
        @AuraEnabled public Boolean fullWidth = false;
        @AuraEnabled public List<Option> options = new List<Option>();
        @AuraEnabled public Boolean isReadOnly = false;
    }

    public class AgentStat {
        @AuraEnabled public String value;
        @AuraEnabled public String label;

        public AgentStat() {} // For JSON.deserialize.

        public AgentStat(String value, String label) {
            this.value = value;
            this.label = label;
        }
    }

    public class RelatedLine {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String badge;
        @AuraEnabled public String badgeVariant;
        @AuraEnabled public String warning;
    }

    public class NewAgentOptions {
        @AuraEnabled public List<CloneSource> cloneSources = new List<CloneSource>();
        @AuraEnabled public List<DraftAgent> drafts = new List<DraftAgent>();
    }

    public class CloneSource {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Integer templates = 0;
        @AuraEnabled public Integer dataSources = 0;
        @AuraEnabled public Integer workflowActions = 0;
        @AuraEnabled public Integer violationRules = 0;
    }

    public class DraftAgent {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Integer step;
        @AuraEnabled public Datetime lastEdited;
    }

    public class CloneRequest {
        public Id sourceId;
        public String name;
        public Boolean copyTemplates = true;
        public Boolean copyDataSources = true;
        public Boolean copyWorkflowActions = true;
        public Boolean copyViolationRules = true;
    }

    // =============================================================
    // Agent Wizard
    // =============================================================

    public class WizardState {
        @AuraEnabled public Id agentId;
        @AuraEnabled public String agentName;
        @AuraEnabled public String statusLabel;
        @AuraEnabled public Datetime lastSaved;
        @AuraEnabled public Integer setupStep = 1;
        @AuraEnabled public Boolean isSetupComplete = false;
        @AuraEnabled public Boolean isActive = false;
        @AuraEnabled public Boolean isTestMode = false;
        @AuraEnabled public WizardBasics basics;
        @AuraEnabled public List<Option> objectOptions = new List<Option>();
        @AuraEnabled public List<ModelOption> modelOptions = new List<ModelOption>();
        @AuraEnabled public Integer orgDefaultIterations;
        @AuraEnabled public Integer iterationsCap;
        @AuraEnabled public String noMatchBehavior;
        @AuraEnabled public List<TemplateView> templates = new List<TemplateView>();
        @AuraEnabled public List<AssignedSource> dataSources = new List<AssignedSource>();
        @AuraEnabled public List<AssignedAction> workflowActions = new List<AssignedAction>();
        @AuraEnabled public List<RuleView> violationRules = new List<RuleView>();
        @AuraEnabled public ConversationRules conversationRules;
        @AuraEnabled public List<SummaryItem> summary = new List<SummaryItem>();
        @AuraEnabled public List<ReadinessCheck> checks = new List<ReadinessCheck>();
        @AuraEnabled public List<ReviewSection> review = new List<ReviewSection>();
        @AuraEnabled public List<String> warnings = new List<String>();
    }

    public class WizardBasics {
        @AuraEnabled public String name;
        @AuraEnabled public String developerName;
        @AuraEnabled public String objectType;
        @AuraEnabled public String description;
        @AuraEnabled public String persona;
        @AuraEnabled public String modelId;
        @AuraEnabled public Integer maxIterations;
        @AuraEnabled public String greeting;
        @AuraEnabled public String fallback;
    }

    public class ModelOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String developerName;
        @AuraEnabled public Boolean isOrgDefault = false;
        @AuraEnabled public String provider;
        @AuraEnabled public String modelIdentifier;
        @AuraEnabled public String detail;
    }

    public class TemplateView {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String developerName;
        @AuraEnabled public String description;
        @AuraEnabled public Boolean isActive = false;
        @AuraEnabled public String criteriaLogic = 'any';
        @AuraEnabled public List<Condition> conditions = new List<Condition>();
        @AuraEnabled public String criteriaSummary;
        @AuraEnabled public List<String> keywords = new List<String>();
        @AuraEnabled public String systemContext;
        @AuraEnabled public String tone;
        @AuraEnabled public String prompt;
        @AuraEnabled public String exclusions;
        @AuraEnabled public Integer maxResponseLength;
    }

    public class Condition {
        @AuraEnabled public String field;
        @AuraEnabled public String operator;
        @AuraEnabled public String value;
    }

    public class ActivationCriteria {
        public String logic;
        public List<Condition> conditions = new List<Condition>();
    }

    public class AssignedSource {
        @AuraEnabled public Id linkId;
        @AuraEnabled public Id dataSourceId;
        @AuraEnabled public String name;
        @AuraEnabled public String description;
        @AuraEnabled public String sourceType;
        @AuraEnabled public String bindingType;
        @AuraEnabled public String targetObject;
        @AuraEnabled public Boolean isActive = false;
        @AuraEnabled public Boolean isMismatch = false;
    }

    public class LibrarySource {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String description;
        @AuraEnabled public String sourceType;
        @AuraEnabled public String bindingType;
        @AuraEnabled public String targetObject;
        @AuraEnabled public Integer usedBy = 0;
        @AuraEnabled public Boolean runsOnObject = false;
    }

    public class AssignedAction {
        @AuraEnabled public Id linkId;
        @AuraEnabled public Id actionId;
        @AuraEnabled public String name;
        @AuraEnabled public String description;
        @AuraEnabled public String actionType;
        @AuraEnabled public String executionType;
        @AuraEnabled public String implementationName;
        @AuraEnabled public Boolean requiresConfirmation = false;
        @AuraEnabled public String confirmationMessage;
        @AuraEnabled public Boolean isActive = false;
    }

    public class LibraryAction {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String description;
        @AuraEnabled public String actionType;
        @AuraEnabled public String executionType;
        @AuraEnabled public String targetObject;
        @AuraEnabled public Boolean requiresConfirmation = false;
    }

    public class RuleView {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String developerName;
        @AuraEnabled public String detectionMethod;
        @AuraEnabled public String detectionLabel;
        @AuraEnabled public String violationType;
        @AuraEnabled public String violationTypeLabel;
        @AuraEnabled public Boolean blockRequest = false;
        @AuraEnabled public Boolean isActive = true;
        @AuraEnabled public String instruction;
        @AuraEnabled public String signalTag;
    }

    public class ConversationRules {
        @AuraEnabled public String loadTrigger;
        @AuraEnabled public String visibility;
        @AuraEnabled public Boolean singleActive = false;
        @AuraEnabled public Boolean allowResume = false;
        @AuraEnabled public Integer idleTimeout;
        @AuraEnabled public Integer maxMessages;
        @AuraEnabled public Decimal maxTokens;
        @AuraEnabled public String tokenTracking;
        @AuraEnabled public Integer retentionDays;
        @AuraEnabled public String retentionTrigger;
        @AuraEnabled public Decimal globalBudget;
    }

    public class SummaryItem {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public SummaryItem() {} // For JSON.deserialize.

        public SummaryItem(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    // state: ok | warn | pending. step is the wizard step the check becomes meaningful at.
    public class ReadinessCheck {
        @AuraEnabled public String text;
        @AuraEnabled public String state;
        @AuraEnabled public Integer step;

        public ReadinessCheck() {} // For JSON.deserialize.

        public ReadinessCheck(Integer step, String state, String text) {
            this.step = step;
            this.state = state;
            this.text = text;
        }
    }

    public class ReviewSection {
        @AuraEnabled public Integer step;
        @AuraEnabled public String title;
        @AuraEnabled public Boolean needsLook = false;
        @AuraEnabled public List<SummaryItem> values = new List<SummaryItem>();
    }

    public class TryItResult {
        @AuraEnabled public Id conversationId;
        @AuraEnabled public Id lastMessageId;
        @AuraEnabled public Boolean isProcessing = false;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public List<TranscriptMessage> messages = new List<TranscriptMessage>();
        @AuraEnabled public List<String> howItAnswered = new List<String>();
    }

    // =============================================================
    // Library
    // =============================================================

    public class ModelConfigView {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String developerName;
        @AuraEnabled public String provider;
        @AuraEnabled public String modelIdentifier;
        @AuraEnabled public String namedCredential;
        @AuraEnabled public String apiPath;
        @AuraEnabled public String headerName;
        @AuraEnabled public String headerValue;
        @AuraEnabled public Decimal temperature;
        @AuraEnabled public Integer maxOutputTokens;
        @AuraEnabled public Integer retryAttempts;
        @AuraEnabled public Boolean isActive = true;
    }

    public class ConnectionTestResult {
        @AuraEnabled public Boolean success = false;
        @AuraEnabled public Integer statusCode;
        @AuraEnabled public Long durationMs;
        @AuraEnabled public String message;
    }

    public class DataSourceView {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String developerName;
        @AuraEnabled public String description;
        @AuraEnabled public String sourceType;
        @AuraEnabled public String bindingType;
        @AuraEnabled public String targetObject;
        @AuraEnabled public String outputDescription;
        @AuraEnabled public String soqlTemplate;
        @AuraEnabled public String inputSchema;
        @AuraEnabled public String apexClassName;
        @AuraEnabled public Boolean isActive = true;
        @AuraEnabled public List<RelatedLine> usedBy = new List<RelatedLine>();
        @AuraEnabled public String usageLast14Days;
    }

    public class DataSourceTestResult {
        @AuraEnabled public Boolean success = false;
        @AuraEnabled public Integer rowCount = 0;
        @AuraEnabled public Long durationMs;
        @AuraEnabled public String piiNote;
        @AuraEnabled public String message;
        @AuraEnabled public List<String> columns = new List<String>();
        @AuraEnabled public List<List<String>> rows = new List<List<String>>();
    }

    public class WorkflowActionView {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String developerName;
        @AuraEnabled public String description;
        @AuraEnabled public String actionType;
        @AuraEnabled public String executionType;
        @AuraEnabled public String flowApiName;
        @AuraEnabled public String apexClassName;
        @AuraEnabled public String targetObject;
        @AuraEnabled public String inputSchema;
        @AuraEnabled public String outputDescription;
        @AuraEnabled public Boolean requiresConfirmation = false;
        @AuraEnabled public String confirmationMessage;
        @AuraEnabled public Boolean isActive = true;
        @AuraEnabled public List<SummaryItem> previewInputs = new List<SummaryItem>();
        @AuraEnabled public List<RelatedLine> usedBy = new List<RelatedLine>();
    }

    public class QueryObjectOption {
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public String relationshipField;
        @AuraEnabled public String relationshipLabel;
        @AuraEnabled public Boolean isBoundObject = false;
    }

    public class FieldOption {
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public String dataType;
        @AuraEnabled public Boolean isPii = false;
        @AuraEnabled public Boolean isDate = false;
        @AuraEnabled public Boolean isSortable = true;
        @AuraEnabled public Boolean isFilterable = true;
    }

    public class SoqlCheck {
        @AuraEnabled public Boolean isValid = false;
        @AuraEnabled public String message;
        @AuraEnabled public List<String> notes = new List<String>();
        @AuraEnabled public List<String> piiFields = new List<String>();
        @AuraEnabled public String inputSchema;
    }

    // =============================================================
    // Activity
    // =============================================================

    public class ConversationDetail {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String statusVariant;
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
        @AuraEnabled public Id agentId;
        @AuraEnabled public String agentName;
        @AuraEnabled public String recordId;
        @AuraEnabled public String recordLabel;
        @AuraEnabled public String templateName;
        @AuraEnabled public String channel;
        @AuraEnabled public String tokensLabel;
        @AuraEnabled public String retentionLabel;
        @AuraEnabled public Boolean canViewPii = false;
        @AuraEnabled public Boolean canClose = false;
        @AuraEnabled public Integer messageCount = 0;
        @AuraEnabled public List<TranscriptMessage> messages = new List<TranscriptMessage>();
        @AuraEnabled public Id stepsForMessageId;
        @AuraEnabled public String stepsForLabel;
        @AuraEnabled public List<StepView> steps = new List<StepView>();
        @AuraEnabled public String feedbackSummary;
        @AuraEnabled public String violationSummary;
    }

    public class TranscriptMessage {
        @AuraEnabled public Id id;
        @AuraEnabled public Boolean isUser = false;
        @AuraEnabled public Boolean isAgent = false;
        @AuraEnabled public String author;
        @AuraEnabled public String timeLabel;
        @AuraEnabled public String text;
        @AuraEnabled public Decimal tokens;
        @AuraEnabled public String rating;
        @AuraEnabled public String suggestedAction;
        @AuraEnabled public Boolean suggestedActionRun = false;
        @AuraEnabled public Boolean hasSteps = false;
    }

    public class StepView {
        @AuraEnabled public Integer stepOrder;
        @AuraEnabled public String label;
        @AuraEnabled public String detail;
        @AuraEnabled public Boolean isSuccess = true;
        @AuraEnabled public Boolean isMono = false;
    }

    public class PiiMapping {
        @AuraEnabled public String fakeValue;
        @AuraEnabled public String realValue;
    }

    public class ViolationDetail {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String severity;
        @AuraEnabled public Boolean requestBlocked = false;
        @AuraEnabled public String title;
        @AuraEnabled public String createdLabel;
        @AuraEnabled public String detail;
        @AuraEnabled public String violationType;
        @AuraEnabled public Id ruleId;
        @AuraEnabled public String ruleName;
        @AuraEnabled public Id agentId;
        @AuraEnabled public String agentName;
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
        @AuraEnabled public Id conversationId;
        @AuraEnabled public String conversationName;
        @AuraEnabled public String ruleFiredLabel;
        @AuraEnabled public String reviewStatus;
    }

    public class PlatformLogDetail {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String exceptionType;
        @AuraEnabled public String occurredLabel;
        @AuraEnabled public String message;
        @AuraEnabled public String className;
        @AuraEnabled public String methodName;
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
        @AuraEnabled public String relatedRecordId;
        @AuraEnabled public Boolean relatedIsConversation = false;
        @AuraEnabled public String stackTrace;
        @AuraEnabled public String hintText;
    }

    public class FeedbackSummary {
        @AuraEnabled public Integer helpfulPercent;
        @AuraEnabled public Integer helpful = 0;
        @AuraEnabled public Integer notHelpful = 0;
        @AuraEnabled public Integer ratings = 0;
        @AuraEnabled public Integer replies = 0;
        @AuraEnabled public Integer commentCount = 0;
        @AuraEnabled public List<AgentRate> byAgent = new List<AgentRate>();
        @AuraEnabled public List<FeedbackComment> comments = new List<FeedbackComment>();
        @AuraEnabled public List<Option> agentOptions = new List<Option>();
    }

    public class AgentRate {
        @AuraEnabled public String name;
        @AuraEnabled public Integer percent;
        @AuraEnabled public Integer ratings;
    }

    public class FeedbackComment {
        @AuraEnabled public Id id;
        @AuraEnabled public String comment;
        @AuraEnabled public String agentName;
        @AuraEnabled public String userName;
        @AuraEnabled public Id conversationId;
        @AuraEnabled public String conversationName;
        @AuraEnabled public String whenLabel;
    }

    // =============================================================
    // Settings
    // =============================================================

    public class AppSettingsView {
        @AuraEnabled public Boolean isApplicationActive = true;
        @AuraEnabled public String defaultModel;
        @AuraEnabled public List<Option> modelOptions = new List<Option>();
        @AuraEnabled public Decimal calloutTimeout;
        @AuraEnabled public Decimal processingLockMinutes;
        @AuraEnabled public List<String> successCodes = new List<String>();
        @AuraEnabled public List<String> retryCodes = new List<String>();
        @AuraEnabled public Decimal defaultMaxIterations;
        @AuraEnabled public Decimal iterationsCap;
        @AuraEnabled public Decimal callsPerIteration;
        @AuraEnabled public Decimal globalTokenBudget;
        @AuraEnabled public Decimal tokensToday = 0;
        @AuraEnabled public Boolean disableExceptionLogging = false;
        @AuraEnabled public Boolean disablePlatformLogs = false;
        @AuraEnabled public String auditLoggingRecordId;
        @AuraEnabled public List<Option> agentOptions = new List<Option>();
        @AuraEnabled public Decimal maxPiiRegistryObjects;
        @AuraEnabled public String toolingApiVersion;
        @AuraEnabled public String emailTemplateId;
        @AuraEnabled public List<Option> emailTemplateOptions = new List<Option>();
        @AuraEnabled public String lastChangedLabel;
    }

    public class UiSettingsView {
        @AuraEnabled public String level; // org | profile | user
        @AuraEnabled public String ownerId;
        @AuraEnabled public String ownerName;
        @AuraEnabled public List<Option> ownerOptions = new List<Option>();
        @AuraEnabled public Integer userCount;
        @AuraEnabled public Integer overriddenCount = 0;
        @AuraEnabled public List<UiSettingRow> rows = new List<UiSettingRow>();
    }

    // type: toggle | radio | number. inheritedLabel is what "Reset to ..." puts back.
    public class UiSettingRow {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public String help;
        @AuraEnabled public String type;
        @AuraEnabled public Object value;
        @AuraEnabled public String sourceLabel;
        @AuraEnabled public Boolean isOverridden = false;
        @AuraEnabled public String inheritedLabel;
        @AuraEnabled public Object inheritedValue;
        @AuraEnabled public List<Option> options = new List<Option>();
    }

    public class UserSettingsRow {
        @AuraEnabled public Id id;
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
        @AuraEnabled public String userType;
        @AuraEnabled public String channelsLabel;
        @AuraEnabled public Decimal maxTokens;
        @AuraEnabled public String limitBehavior;
        @AuraEnabled public String termsLabel;
        @AuraEnabled public Boolean termsOutOfDate = false;
        @AuraEnabled public Boolean isInactive = false;
    }

    public class UserSettingsView {
        @AuraEnabled public Id id;
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
        @AuraEnabled public String initials;
        @AuraEnabled public String userType;
        @AuraEnabled public Boolean isActive = true;
        @AuraEnabled public List<String> allowedChannels = new List<String>();
        @AuraEnabled public List<Option> channelOptions = new List<Option>();
        @AuraEnabled public String visibilityScope;
        @AuraEnabled public List<Option> visibilityOptions = new List<Option>();
        @AuraEnabled public Decimal maxTokens;
        @AuraEnabled public Decimal maxConversations;
        @AuraEnabled public Decimal maxConcurrent;
        @AuraEnabled public String limitBehavior;
        @AuraEnabled public List<Option> limitBehaviorOptions = new List<Option>();
        @AuraEnabled public String usedTodayLabel;
        @AuraEnabled public Boolean workflowActionsEnabled = true;
        @AuraEnabled public Boolean exportEnabled = false;
        @AuraEnabled public Boolean debugModeEnabled = false;
        @AuraEnabled public String termsLabel;
    }

    public class TermsView {
        @AuraEnabled public String currentVersion;
        @AuraEnabled public String nextVersion;
        @AuraEnabled public String policyUrl;
        @AuraEnabled public Integer signedCount = 0;
        @AuraEnabled public Integer totalUsers = 0;
        @AuraEnabled public Integer percent = 0;
        @AuraEnabled public Integer olderCount = 0;
        @AuraEnabled public String olderUsersLabel;
        @AuraEnabled public List<Acknowledgment> acknowledgments = new List<Acknowledgment>();
    }

    public class Acknowledgment {
        @AuraEnabled public Id id;
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
        @AuraEnabled public String version;
        @AuraEnabled public String signature;
        @AuraEnabled public String acknowledgedLabel;
        @AuraEnabled public String loginHistoryId;
    }

    public class PiiRegistryView {
        @AuraEnabled public Integer objectCount = 0;
        @AuraEnabled public Integer maxObjects;
        @AuraEnabled public List<PiiObjectRow> objects = new List<PiiObjectRow>();
        @AuraEnabled public List<PiiObjectRow> failed = new List<PiiObjectRow>();
    }

    public class PiiObjectRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String objectLabel;
        @AuraEnabled public String syncStatus;
        @AuraEnabled public String syncVariant;
        @AuraEnabled public Integer fieldCount;
        @AuraEnabled public Integer piiCount;
        @AuraEnabled public String lastSyncedLabel;
        @AuraEnabled public Boolean isActive = true;
        @AuraEnabled public Boolean isFailed = false;
        @AuraEnabled public String failureMessage;
    }

    public class PiiFieldRow {
        @AuraEnabled public String label;
        @AuraEnabled public String apiName;
        @AuraEnabled public String dataType;
        @AuraEnabled public String piiType;
        @AuraEnabled public String complianceGroup;
    }
}
