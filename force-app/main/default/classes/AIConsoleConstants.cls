/*
Class Name: AIConsoleConstants

=================================================================
=================================================================

Description: Constants used only by the AI Assist console (AIConsoleController and its services). The
tab and section Developer Names match the AINavTab__mdt / AINavTabSection__mdt records seeded per org -
the console links across tabs with them (e.g. a Home tile opening Activity › Conversations), so a
renamed record must be renamed here too. Everything shared with the rest of the package stays in
AIAssistApplicationConstants.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-29     Chandler Stuart          Initial development
*/

public class AIConsoleConstants {

    // AINavTab__mdt Developer Names (also the App Page and CustomTab API names)
    public static final String TAB_HOME = 'AI_Home';
    public static final String TAB_AGENTS = 'AI_Agents';
    public static final String TAB_AGENT_WIZARD = 'AI_Agent_Wizard';
    public static final String TAB_LIBRARY = 'AI_Library';
    public static final String TAB_ACTIVITY = 'AI_Activity';
    public static final String TAB_SETTINGS = 'AI_Settings';

    // AINavTabSection__mdt Developer Names
    public static final String SECTION_AGENTS_ALL = 'Agents_All';
    public static final String SECTION_AGENTS_DRAFTS = 'Agents_Drafts';
    public static final String SECTION_LIBRARY_MODELS = 'Library_Model_Configurations';
    public static final String SECTION_LIBRARY_DATA_SOURCES = 'Library_Data_Sources';
    public static final String SECTION_LIBRARY_ACTIONS = 'Library_Workflow_Actions';
    public static final String SECTION_ACTIVITY_CONVERSATIONS = 'Activity_Conversations';
    public static final String SECTION_ACTIVITY_VIOLATIONS = 'Activity_Violations';
    public static final String SECTION_ACTIVITY_FEEDBACK = 'Activity_Feedback';
    public static final String SECTION_ACTIVITY_ERROR_LOG = 'Activity_Error_Log';
    public static final String SECTION_SETTINGS_APP = 'Settings_App';
    public static final String SECTION_SETTINGS_UI = 'Settings_UI';
    public static final String SECTION_SETTINGS_USERS = 'Settings_Users';
    public static final String SECTION_SETTINGS_TERMS = 'Settings_Terms';
    public static final String SECTION_SETTINGS_PII = 'Settings_PII';

    // AINavTabSection__mdt.SectionType__c
    public static final String SECTION_TYPE_SUB_NAVIGATION = 'Sub Navigation';
    public static final String SECTION_TYPE_COMPONENT = 'Component';
    public static final String SECTION_TYPE_RELATED_LIST = 'Related List';

    // Views inside a section (the c__view page state)
    public static final String VIEW_RECORD = 'record';
    public static final String VIEW_WIZARD = 'wizard';
    public static final String VIEW_NEW = 'new';

    // AIAgent__c.SetupStatus__c
    public static final String SETUP_STATUS_DRAFT = 'Draft';
    public static final String SETUP_STATUS_IN_PROGRESS = 'In Progress';
    public static final String SETUP_STATUS_COMPLETE = 'Complete';

    public static final Integer WIZARD_STEP_COUNT = 7;
    public static final List<String> WIZARD_STEP_LABELS = new List<String>{ 'Basics', 'Prompt Templates', 'Data Sources', 'Workflow Actions', 'Guardrails', 'Conversation Rules', 'Review & Activate' };

    // Step 7 "Go live" choices
    public static final String GO_LIVE_ACTIVATE = 'activate';
    public static final String GO_LIVE_TEST_MODE = 'test';
    public static final String GO_LIVE_INACTIVE = 'inactive';

    // AIAgent__c.NoMatchBehavior__c - the picklist value is spelled "Closet Match" in the org.
    public static final String NO_MATCH_CLOSEST = 'Closet Match';
    public static final String NO_MATCH_FALLBACK = 'Fallback Message';

    // AIViolationRule__c.DetectionMethod__c
    public static final String DETECTION_DETERMINISTIC_APEX = 'Deterministic_Apex';
    public static final String DETECTION_AI_EVALUATED = 'AI_Evaluated';

    // AIDataSource__c.BindingType__c / AIWorkflowAction__c.ExecutionType__c
    public static final String BINDING_BOUND = 'Bound';
    public static final String BINDING_UNBOUND = 'Unbound';
    public static final String EXECUTION_WRITE = 'Write';
    public static final String EXECUTION_READ_ONLY = 'Read Only';

    // AIViolation__c.ReviewStatus__c / Severity__c
    public static final String REVIEW_STATUS_NEW = 'New';
    public static final String REVIEW_STATUS_REVIEWED = 'Reviewed';
    public static final String SEVERITY_HIGH = 'High';
    public static final String SEVERITY_MEDIUM = 'Medium';
    public static final String SEVERITY_LOW = 'Low';

    // AIFeedback__c.Rating__c
    public static final String RATING_HELPFUL = 'Helpful';
    public static final String RATING_NOT_HELPFUL = 'Not Helpful';

    // UI Settings levels
    public static final String LEVEL_ORG = 'org';
    public static final String LEVEL_PROFILE = 'profile';
    public static final String LEVEL_USER = 'user';

    // Test runs ("Run test" on a Data Source) never return more than this many rows.
    public static final Integer TEST_ROW_LIMIT = 20;
    public static final Integer LIST_PAGE_SIZE = 50;
    public static final Integer HOME_TREND_DEFAULT_DAYS = 14;
    public static final String TRY_IT_CHANNEL = 'Record Page Chat';
}