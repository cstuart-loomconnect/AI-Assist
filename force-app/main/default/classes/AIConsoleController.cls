/*
Class Name: AIConsoleController

=================================================================
=================================================================

Description: The Apex controller behind the AI Assist console - aiTabPage and every section component it
loads on the AI Home, AI Agents, AI Library, AI Activity and AI Settings App Pages. Every @AuraEnabled
method here is one round trip a console component makes; the logic is split across services so this
class stays a thin translator between what the console asks for and what it should be shown:

AIConsoleDataStructure      - the response shapes shared by every service, and AIConsoleException -
                              the one refusal type whose message the console shows verbatim.
AIConsoleUtility            - who may open the console and each section, date/number labels, namespace.
AIConsoleNavService         - AINavTab__mdt / AINavTabSection__mdt: the tab's sections and rail.
AIConsoleHomeService        - Home's summary tiles, trend chart and "Needs attention".
AIConsoleListService        - every list aiRecordList shows (one builder per Related Object API Name).
AIConsoleAgentService       - the Agents list, agent record, row actions and New Agent modal.
AIConsoleWizardService      - the seven-step Agent Wizard, its summary, readiness and "Try it".
AIConsoleLibraryService     - Model Configurations, Data Sources and Workflow Actions, and their tests.
AIConsoleSoqlBuilderService - describe calls and validation behind the SOQL Builder.
AIConsoleActivityService    - conversation detail, violations, feedback and error log detail.
AIConsoleSettingsService    - App, UI and User Settings, Usage Terms and the PII Registry.

Access: only AIAssistAdminUser / AIAssistSuperUser hold this class. Every method also checks the
section it serves (AIConsoleUtility.assertSectionAccess), so a section locked by
AINavTabSection__mdt.RequiresPermissionSet__c is locked here too, not only hidden in the page.

Completely separate from the chat window (AIChatController and its services) - the two share no Apex.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-29     Chandler Stuart          Initial development
*/

public with sharing class AIConsoleController {

    // =============================================================
    // Navigation
    // =============================================================

    @AuraEnabled
    public static AIConsoleDataStructure.TabConfig getTabConfig(String tabName) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleNavService.getTabConfig(tabName);
        } catch (Exception ex) {
            throw toAuraException(ex, 'getTabConfig');
        }
    }

    // =============================================================
    // Home
    // =============================================================

    @AuraEnabled
    public static AIConsoleDataStructure.HomeSummary getHomeSummary(Integer days) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleHomeService.getSummary(days);
        } catch (Exception ex) {
            throw toAuraException(ex, 'getHomeSummary');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.ConversationTrend getConversationTrend(Integer days) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleHomeService.getTrend(days);
        } catch (Exception ex) {
            throw toAuraException(ex, 'getConversationTrend');
        }
    }

    @AuraEnabled
    public static List<AIConsoleDataStructure.AttentionItem> getAttentionItems() {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleHomeService.getAttentionItems();
        } catch (Exception ex) {
            throw toAuraException(ex, 'getAttentionItems');
        }
    }

    // =============================================================
    // Generic lists
    // =============================================================

    // filtersJson: {"status":"Active","hasViolation":true} - the keys each list's filters declare.
    @AuraEnabled
    public static AIConsoleDataStructure.ListResult getRecordList(String sectionName, String filtersJson, Integer offset) {
        try {
            return AIConsoleListService.getList(sectionName, filtersJson, offset);
        } catch (Exception ex) {
            throw toAuraException(ex, 'getRecordList');
        }
    }

    // =============================================================
    // Agents
    // =============================================================

    @AuraEnabled
    public static AIConsoleDataStructure.AgentList getAgentList(String sectionName, String searchText) {
        try {
            return AIConsoleAgentService.getAgentList(sectionName, searchText);
        } catch (Exception ex) {
            throw toAuraException(ex, 'getAgentList');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.AgentRecord getAgentRecord(Id agentId) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleAgentService.getAgentRecord(agentId);
        } catch (Exception ex) {
            throw toAuraException(ex, 'getAgentRecord');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.AgentRecord updateAgentField(Id agentId, String fieldKey, String value) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleAgentService.updateAgentField(agentId, fieldKey, value);
        } catch (Exception ex) {
            throw toAuraException(ex, 'updateAgentField');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.ListResult getAgentRelated(Id agentId, String relatedKey) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleAgentService.getAgentRelated(agentId, relatedKey);
        } catch (Exception ex) {
            throw toAuraException(ex, 'getAgentRelated');
        }
    }

    // mode: activate | test | deactivate
    @AuraEnabled
    public static void setAgentStatus(Id agentId, String mode) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            AIConsoleAgentService.setAgentStatus(agentId, mode);
        } catch (Exception ex) {
            throw toAuraException(ex, 'setAgentStatus');
        }
    }

    @AuraEnabled
    public static void deleteAgent(Id agentId) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            AIConsoleAgentService.deleteAgent(agentId);
        } catch (Exception ex) {
            throw toAuraException(ex, 'deleteAgent');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.NewAgentOptions getNewAgentOptions() {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleAgentService.getNewAgentOptions();
        } catch (Exception ex) {
            throw toAuraException(ex, 'getNewAgentOptions');
        }
    }

    @AuraEnabled
    public static Id cloneAgent(String requestJson) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleAgentService.cloneAgent((AIConsoleDataStructure.CloneRequest) JSON.deserialize(requestJson, AIConsoleDataStructure.CloneRequest.class));
        } catch (Exception ex) {
            throw toAuraException(ex, 'cloneAgent');
        }
    }

    // =============================================================
    // Agent Wizard
    // =============================================================

    @AuraEnabled
    public static AIConsoleDataStructure.WizardState getWizard(Id agentId) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleWizardService.getWizard(agentId);
        } catch (Exception ex) {
            throw toAuraException(ex, 'getWizard');
        }
    }

    // nextStep: the step the wizard moves to after saving (null = stay).
    @AuraEnabled
    public static AIConsoleDataStructure.WizardState saveBasics(Id agentId, String basicsJson, Integer nextStep) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleWizardService.saveBasics(agentId, (AIConsoleDataStructure.WizardBasics) JSON.deserialize(basicsJson, AIConsoleDataStructure.WizardBasics.class), nextStep);
        } catch (Exception ex) {
            throw toAuraException(ex, 'saveBasics');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.WizardState saveTemplate(Id agentId, String templateJson) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleWizardService.saveTemplate(agentId, (AIConsoleDataStructure.TemplateView) JSON.deserialize(templateJson, AIConsoleDataStructure.TemplateView.class));
        } catch (Exception ex) {
            throw toAuraException(ex, 'saveTemplate');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.WizardState setTemplateActive(Id agentId, Id templateId, Boolean isActive) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleWizardService.setTemplateActive(agentId, templateId, isActive);
        } catch (Exception ex) {
            throw toAuraException(ex, 'setTemplateActive');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.WizardState cloneTemplate(Id agentId, Id templateId) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleWizardService.cloneTemplate(agentId, templateId);
        } catch (Exception ex) {
            throw toAuraException(ex, 'cloneTemplate');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.WizardState deleteTemplate(Id agentId, Id templateId) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleWizardService.deleteTemplate(agentId, templateId);
        } catch (Exception ex) {
            throw toAuraException(ex, 'deleteTemplate');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.WizardState saveNoMatchBehavior(Id agentId, String behavior) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleWizardService.saveNoMatchBehavior(agentId, behavior);
        } catch (Exception ex) {
            throw toAuraException(ex, 'saveNoMatchBehavior');
        }
    }

    @AuraEnabled
    public static List<AIConsoleDataStructure.LibrarySource> getLibrarySources(Id agentId, String searchText, Boolean onlyThisObject) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleWizardService.getLibrarySources(agentId, searchText, onlyThisObject);
        } catch (Exception ex) {
            throw toAuraException(ex, 'getLibrarySources');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.WizardState assignDataSources(Id agentId, List<Id> dataSourceIds) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleWizardService.assignDataSources(agentId, dataSourceIds);
        } catch (Exception ex) {
            throw toAuraException(ex, 'assignDataSources');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.WizardState setDataSourceAssignmentActive(Id agentId, Id linkId, Boolean isActive) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleWizardService.setDataSourceActive(agentId, linkId, isActive);
        } catch (Exception ex) {
            throw toAuraException(ex, 'setDataSourceAssignmentActive');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.WizardState removeDataSource(Id agentId, Id linkId) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleWizardService.removeDataSource(agentId, linkId);
        } catch (Exception ex) {
            throw toAuraException(ex, 'removeDataSource');
        }
    }

    @AuraEnabled
    public static List<AIConsoleDataStructure.LibraryAction> getLibraryActions(Id agentId) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleWizardService.getLibraryActions(agentId);
        } catch (Exception ex) {
            throw toAuraException(ex, 'getLibraryActions');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.WizardState assignWorkflowActions(Id agentId, List<Id> actionIds) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleWizardService.assignWorkflowActions(agentId, actionIds);
        } catch (Exception ex) {
            throw toAuraException(ex, 'assignWorkflowActions');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.WizardState setWorkflowActionAssignmentActive(Id agentId, Id linkId, Boolean isActive) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleWizardService.setWorkflowActionActive(agentId, linkId, isActive);
        } catch (Exception ex) {
            throw toAuraException(ex, 'setWorkflowActionAssignmentActive');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.WizardState removeWorkflowAction(Id agentId, Id linkId) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleWizardService.removeWorkflowAction(agentId, linkId);
        } catch (Exception ex) {
            throw toAuraException(ex, 'removeWorkflowAction');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.WizardState saveRule(Id agentId, String ruleJson) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleWizardService.saveRule(agentId, (AIConsoleDataStructure.RuleView) JSON.deserialize(ruleJson, AIConsoleDataStructure.RuleView.class));
        } catch (Exception ex) {
            throw toAuraException(ex, 'saveRule');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.WizardState setRuleActive(Id agentId, Id ruleId, Boolean isActive) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleWizardService.setRuleActive(agentId, ruleId, isActive);
        } catch (Exception ex) {
            throw toAuraException(ex, 'setRuleActive');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.WizardState deleteRule(Id agentId, Id ruleId) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleWizardService.deleteRule(agentId, ruleId);
        } catch (Exception ex) {
            throw toAuraException(ex, 'deleteRule');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.WizardState saveConversationRules(Id agentId, String rulesJson, Integer nextStep) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleWizardService.saveConversationRules(agentId, (AIConsoleDataStructure.ConversationRules) JSON.deserialize(rulesJson, AIConsoleDataStructure.ConversationRules.class), nextStep);
        } catch (Exception ex) {
            throw toAuraException(ex, 'saveConversationRules');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.WizardState goToWizardStep(Id agentId, Integer nextStep) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleWizardService.goToStep(agentId, nextStep);
        } catch (Exception ex) {
            throw toAuraException(ex, 'goToWizardStep');
        }
    }

    // mode: activate | test | inactive
    @AuraEnabled
    public static AIConsoleDataStructure.WizardState finishWizard(Id agentId, String mode) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleWizardService.finish(agentId, mode);
        } catch (Exception ex) {
            throw toAuraException(ex, 'finishWizard');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.TryItResult sendTryIt(Id agentId, Id recordId, String text, Id conversationId) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleWizardService.sendTryIt(agentId, recordId, text, conversationId);
        } catch (Exception ex) {
            throw toAuraException(ex, 'sendTryIt');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.TryItResult getTryItUpdate(Id conversationId) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleWizardService.getTryItUpdate(conversationId);
        } catch (Exception ex) {
            throw toAuraException(ex, 'getTryItUpdate');
        }
    }

    @AuraEnabled
    public static List<AIConsoleDataStructure.Option> getObjectOptions() {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleWizardService.getObjectOptions();
        } catch (Exception ex) {
            throw toAuraException(ex, 'getObjectOptions');
        }
    }

    // =============================================================
    // Library
    // =============================================================

    @AuraEnabled
    public static AIConsoleDataStructure.ModelConfigView getModelConfig(Id modelId) {
        try {
            AIConsoleUtility.assertSectionAccess(AIConsoleConstants.SECTION_LIBRARY_MODELS);
            return AIConsoleLibraryService.getModelConfig(modelId);
        } catch (Exception ex) {
            throw toAuraException(ex, 'getModelConfig');
        }
    }

    @AuraEnabled
    public static List<AIConsoleDataStructure.Option> getNamedCredentialOptions() {
        try {
            AIConsoleUtility.assertSectionAccess(AIConsoleConstants.SECTION_LIBRARY_MODELS);
            return AIConsoleLibraryService.getNamedCredentialOptions();
        } catch (Exception ex) {
            throw toAuraException(ex, 'getNamedCredentialOptions');
        }
    }

    @AuraEnabled
    public static Id saveModelConfig(String modelJson) {
        try {
            AIConsoleUtility.assertSectionAccess(AIConsoleConstants.SECTION_LIBRARY_MODELS);
            return AIConsoleLibraryService.saveModelConfig((AIConsoleDataStructure.ModelConfigView) JSON.deserialize(modelJson, AIConsoleDataStructure.ModelConfigView.class));
        } catch (Exception ex) {
            throw toAuraException(ex, 'saveModelConfig');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.ConnectionTestResult testModelConnection(String modelJson) {
        try {
            AIConsoleUtility.assertSectionAccess(AIConsoleConstants.SECTION_LIBRARY_MODELS);
            return AIConsoleLibraryService.testConnection((AIConsoleDataStructure.ModelConfigView) JSON.deserialize(modelJson, AIConsoleDataStructure.ModelConfigView.class));
        } catch (Exception ex) {
            throw toAuraException(ex, 'testModelConnection');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.DataSourceView getDataSource(Id dataSourceId) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleLibraryService.getDataSource(dataSourceId);
        } catch (Exception ex) {
            throw toAuraException(ex, 'getDataSource');
        }
    }

    // assignToAgentId: "Save & assign" from the wizard.
    @AuraEnabled
    public static Id saveDataSource(String dataSourceJson, Id assignToAgentId) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleLibraryService.saveDataSource((AIConsoleDataStructure.DataSourceView) JSON.deserialize(dataSourceJson, AIConsoleDataStructure.DataSourceView.class), assignToAgentId);
        } catch (Exception ex) {
            throw toAuraException(ex, 'saveDataSource');
        }
    }

    @AuraEnabled
    public static void setDataSourceActive(Id dataSourceId, Boolean isActive) {
        try {
            AIConsoleUtility.assertSectionAccess(AIConsoleConstants.SECTION_LIBRARY_DATA_SOURCES);
            AIConsoleLibraryService.setDataSourceActive(dataSourceId, isActive);
        } catch (Exception ex) {
            throw toAuraException(ex, 'setDataSourceActive');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.DataSourceTestResult testDataSource(String dataSourceJson, Id testRecordId) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleLibraryService.testDataSource((AIConsoleDataStructure.DataSourceView) JSON.deserialize(dataSourceJson, AIConsoleDataStructure.DataSourceView.class), testRecordId);
        } catch (Exception ex) {
            throw toAuraException(ex, 'testDataSource');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.WorkflowActionView getWorkflowAction(Id actionId) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleLibraryService.getWorkflowAction(actionId);
        } catch (Exception ex) {
            throw toAuraException(ex, 'getWorkflowAction');
        }
    }

    @AuraEnabled
    public static Id saveWorkflowAction(String actionJson) {
        try {
            AIConsoleUtility.assertSectionAccess(AIConsoleConstants.SECTION_LIBRARY_ACTIONS);
            return AIConsoleLibraryService.saveWorkflowAction((AIConsoleDataStructure.WorkflowActionView) JSON.deserialize(actionJson, AIConsoleDataStructure.WorkflowActionView.class));
        } catch (Exception ex) {
            throw toAuraException(ex, 'saveWorkflowAction');
        }
    }

    // =============================================================
    // SOQL Builder
    // =============================================================

    @AuraEnabled
    public static List<AIConsoleDataStructure.QueryObjectOption> getQueryObjects(String boundObject, String bindingType) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleSoqlBuilderService.getQueryObjects(boundObject, bindingType);
        } catch (Exception ex) {
            throw toAuraException(ex, 'getQueryObjects');
        }
    }

    @AuraEnabled
    public static List<AIConsoleDataStructure.FieldOption> getObjectFields(String objectApiName) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleSoqlBuilderService.getFields(objectApiName);
        } catch (Exception ex) {
            throw toAuraException(ex, 'getObjectFields');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.SoqlCheck checkSoql(String soql, String targetObject, String bindingType) {
        try {
            AIConsoleUtility.assertConsoleAccess();
            return AIConsoleSoqlBuilderService.checkSoql(soql, targetObject, bindingType);
        } catch (Exception ex) {
            throw toAuraException(ex, 'checkSoql');
        }
    }

    // =============================================================
    // Activity
    // =============================================================

    @AuraEnabled
    public static AIConsoleDataStructure.ConversationDetail getConversationDetail(Id conversationId, Id stepsForMessageId) {
        try {
            AIConsoleUtility.assertSectionAccess(AIConsoleConstants.SECTION_ACTIVITY_CONVERSATIONS);
            return AIConsoleActivityService.getConversationDetail(conversationId, stepsForMessageId);
        } catch (Exception ex) {
            throw toAuraException(ex, 'getConversationDetail');
        }
    }

    @AuraEnabled
    public static void closeConversation(Id conversationId) {
        try {
            AIConsoleUtility.assertSectionAccess(AIConsoleConstants.SECTION_ACTIVITY_CONVERSATIONS);
            AIConsoleActivityService.closeConversation(conversationId);
        } catch (Exception ex) {
            throw toAuraException(ex, 'closeConversation');
        }
    }

    @AuraEnabled
    public static List<AIConsoleDataStructure.PiiMapping> getPiiMappings(Id conversationId) {
        try {
            AIConsoleUtility.assertSectionAccess(AIConsoleConstants.SECTION_ACTIVITY_CONVERSATIONS);
            return AIConsoleActivityService.getPiiMappings(conversationId);
        } catch (Exception ex) {
            throw toAuraException(ex, 'getPiiMappings');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.ViolationDetail getViolationDetail(Id violationId) {
        try {
            AIConsoleUtility.assertSectionAccess(AIConsoleConstants.SECTION_ACTIVITY_VIOLATIONS);
            return AIConsoleActivityService.getViolationDetail(violationId);
        } catch (Exception ex) {
            throw toAuraException(ex, 'getViolationDetail');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.ViolationDetail markViolationReviewed(Id violationId) {
        try {
            AIConsoleUtility.assertSectionAccess(AIConsoleConstants.SECTION_ACTIVITY_VIOLATIONS);
            return AIConsoleActivityService.markViolationReviewed(violationId);
        } catch (Exception ex) {
            throw toAuraException(ex, 'markViolationReviewed');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.FeedbackSummary getFeedbackSummary(String agentId, Integer days) {
        try {
            AIConsoleUtility.assertSectionAccess(AIConsoleConstants.SECTION_ACTIVITY_FEEDBACK);
            return AIConsoleActivityService.getFeedbackSummary(agentId, days);
        } catch (Exception ex) {
            throw toAuraException(ex, 'getFeedbackSummary');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.PlatformLogDetail getPlatformLogDetail(Id logId) {
        try {
            AIConsoleUtility.assertSectionAccess(AIConsoleConstants.SECTION_ACTIVITY_ERROR_LOG);
            return AIConsoleActivityService.getPlatformLogDetail(logId);
        } catch (Exception ex) {
            throw toAuraException(ex, 'getPlatformLogDetail');
        }
    }

    // =============================================================
    // Settings
    // =============================================================

    @AuraEnabled
    public static AIConsoleDataStructure.AppSettingsView getAppSettings() {
        try {
            AIConsoleUtility.assertSectionAccess(AIConsoleConstants.SECTION_SETTINGS_APP);
            return AIConsoleSettingsService.getAppSettings();
        } catch (Exception ex) {
            throw toAuraException(ex, 'getAppSettings');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.AppSettingsView saveAppSettings(String settingsJson) {
        try {
            AIConsoleUtility.assertSectionAccess(AIConsoleConstants.SECTION_SETTINGS_APP);
            return AIConsoleSettingsService.saveAppSettings((AIConsoleDataStructure.AppSettingsView) JSON.deserialize(settingsJson, AIConsoleDataStructure.AppSettingsView.class));
        } catch (Exception ex) {
            throw toAuraException(ex, 'saveAppSettings');
        }
    }

    // level: org | profile | user
    @AuraEnabled
    public static AIConsoleDataStructure.UiSettingsView getUiSettings(String level, String ownerId) {
        try {
            AIConsoleUtility.assertSectionAccess(AIConsoleConstants.SECTION_SETTINGS_UI);
            return AIConsoleSettingsService.getUiSettings(level, ownerId);
        } catch (Exception ex) {
            throw toAuraException(ex, 'getUiSettings');
        }
    }

    // valuesJson: {"IsMaintenanceMode__c": false, "MaxVisibleMessageHistory__c": 20, ...}
    @AuraEnabled
    public static AIConsoleDataStructure.UiSettingsView saveUiSettings(String level, String ownerId, String valuesJson) {
        try {
            AIConsoleUtility.assertSectionAccess(AIConsoleConstants.SECTION_SETTINGS_UI);
            return AIConsoleSettingsService.saveUiSettings(level, ownerId, (Map<String, Object>) JSON.deserializeUntyped(valuesJson));
        } catch (Exception ex) {
            throw toAuraException(ex, 'saveUiSettings');
        }
    }

    @AuraEnabled
    public static List<AIConsoleDataStructure.UserSettingsRow> getUserSettingsList(String searchText) {
        try {
            AIConsoleUtility.assertSectionAccess(AIConsoleConstants.SECTION_SETTINGS_USERS);
            return AIConsoleSettingsService.getUserSettingsList(searchText);
        } catch (Exception ex) {
            throw toAuraException(ex, 'getUserSettingsList');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.UserSettingsView getUserSettings(Id settingsId) {
        try {
            AIConsoleUtility.assertSectionAccess(AIConsoleConstants.SECTION_SETTINGS_USERS);
            return AIConsoleSettingsService.getUserSettings(settingsId);
        } catch (Exception ex) {
            throw toAuraException(ex, 'getUserSettings');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.UserSettingsView saveUserSettings(String settingsJson) {
        try {
            AIConsoleUtility.assertSectionAccess(AIConsoleConstants.SECTION_SETTINGS_USERS);
            return AIConsoleSettingsService.saveUserSettings((AIConsoleDataStructure.UserSettingsView) JSON.deserialize(settingsJson, AIConsoleDataStructure.UserSettingsView.class));
        } catch (Exception ex) {
            throw toAuraException(ex, 'saveUserSettings');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.TermsView getTerms() {
        try {
            AIConsoleUtility.assertSectionAccess(AIConsoleConstants.SECTION_SETTINGS_TERMS);
            return AIConsoleSettingsService.getTerms();
        } catch (Exception ex) {
            throw toAuraException(ex, 'getTerms');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.TermsView savePolicyUrl(String policyUrl) {
        try {
            AIConsoleUtility.assertSectionAccess(AIConsoleConstants.SECTION_SETTINGS_TERMS);
            return AIConsoleSettingsService.savePolicyUrl(policyUrl);
        } catch (Exception ex) {
            throw toAuraException(ex, 'savePolicyUrl');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.TermsView publishTermsVersion() {
        try {
            AIConsoleUtility.assertSectionAccess(AIConsoleConstants.SECTION_SETTINGS_TERMS);
            return AIConsoleSettingsService.publishNewVersion();
        } catch (Exception ex) {
            throw toAuraException(ex, 'publishTermsVersion');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.PiiRegistryView getPiiRegistry() {
        try {
            AIConsoleUtility.assertSectionAccess(AIConsoleConstants.SECTION_SETTINGS_PII);
            return AIConsoleSettingsService.getPiiRegistry();
        } catch (Exception ex) {
            throw toAuraException(ex, 'getPiiRegistry');
        }
    }

    @AuraEnabled
    public static List<AIConsoleDataStructure.PiiFieldRow> getPiiFields(Id registryId) {
        try {
            AIConsoleUtility.assertSectionAccess(AIConsoleConstants.SECTION_SETTINGS_PII);
            return AIConsoleSettingsService.getPiiFields(registryId);
        } catch (Exception ex) {
            throw toAuraException(ex, 'getPiiFields');
        }
    }

    // registryId null = "Sync all now".
    @AuraEnabled
    public static AIConsoleDataStructure.PiiRegistryView syncPii(Id registryId) {
        try {
            AIConsoleUtility.assertSectionAccess(AIConsoleConstants.SECTION_SETTINGS_PII);
            return AIConsoleSettingsService.syncPii(registryId);
        } catch (Exception ex) {
            throw toAuraException(ex, 'syncPii');
        }
    }

    @AuraEnabled
    public static AIConsoleDataStructure.PiiRegistryView addPiiObject(String objectApiName) {
        try {
            AIConsoleUtility.assertSectionAccess(AIConsoleConstants.SECTION_SETTINGS_PII);
            return AIConsoleSettingsService.addPiiObject(objectApiName);
        } catch (Exception ex) {
            throw toAuraException(ex, 'addPiiObject');
        }
    }

    // =============================================================
    // Helpers
    // =============================================================

    // A refusal (AIConsoleException) or a validation error on save is shown as it is; anything else is logged once and replaced with a plain message.
    private static AuraHandledException toAuraException(Exception ex, String methodName) {

        if (ex instanceof AIConsoleDataStructure.AIConsoleException) return newAuraException(ex.getMessage());

        AIPlatformLogManager.logException(ex, 'AIConsoleController', methodName);

        if (ex instanceof DmlException && ((DmlException) ex).getNumDml() > 0) return newAuraException(((DmlException) ex).getDmlMessage(0));
        return newAuraException('Something went wrong in the AI Assist console. Please try again.');
    }

    private static AuraHandledException newAuraException(String message) {
        AuraHandledException auraException = new AuraHandledException(message);
        auraException.setMessage(message);
        return auraException;
    }
}