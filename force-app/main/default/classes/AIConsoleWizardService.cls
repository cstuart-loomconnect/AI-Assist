/*
Class Name: AIConsoleWizardService

=================================================================
=================================================================

Description: The Agent Wizard (aiAgentWizard) - the seven steps every agent is built in:

1 Basics              - AIAgent__c identity, model and what users see.
2 Prompt Templates    - AIPromptTemplate__c rows, their ActivationCriteria__c and No Match Behavior.
3 Data Sources        - AIAgentDataSource__c assignments from the Library.
4 Workflow Actions    - AIAgentWorkflowAction__c assignments from the Library.
5 Guardrails          - AIViolationRule__c rows (master-detail to the agent).
6 Conversation Rules  - loading, sessions, limits and retention on AIAgent__c.
7 Review & Activate   - the summary, go-live choice and the "Try it" test chat.

Every save returns the whole WizardState, so the summary rail, readiness checks and review always
reflect what's saved. SetupCurrentStep__c records the furthest step reached; SetupStatus__c goes
Draft -> In Progress (on reaching Review) -> Complete (on Finish). A brand-new agent has no record
until Basics is saved, so abandoning the wizard on step 1 leaves nothing behind.

"Try it" sends through AIConversationMessageService like the chat window does (without changing it)
and reads the reply back, so a test conversation uses real data, real Data Sources and real guardrails.
The agent must be Active (live or test mode) to reply.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-29     Chandler Stuart          Initial development
*/

public with sharing class AIConsoleWizardService {

    private static final Map<String, String> OPERATOR_LABELS = new Map<String, String>{
        'equals' => 'is', 'notEquals' => 'is not', 'contains' => 'contains', 'greaterThan' => 'is greater than', 'lessThan' => 'is less than'
    };

    // =============================================================
    // Load
    // =============================================================

    public static AIConsoleDataStructure.WizardState getWizard(Id agentId) {

        AIConsoleDataStructure.WizardState state = new AIConsoleDataStructure.WizardState();
        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();

        state.orgDefaultIterations = AIAssistSettingsService.getDefaultMaxToolCallingIterations();
        state.iterationsCap = AIAssistSettingsService.getMaxToolCallingIterationsCap();
        state.objectOptions = getObjectOptions();
        state.modelOptions = getModelOptions(settings.DefaultModelConfiguration__c);

        if (agentId == null) {
            state.basics = new AIConsoleDataStructure.WizardBasics();
            for (AIConsoleDataStructure.ModelOption model : state.modelOptions) {
                if (model.isOrgDefault) state.basics.modelId = model.id;
            }
            state.statusLabel = 'Draft';
            state.agentName = 'New Agent';
            state.noMatchBehavior = AIConsoleConstants.NO_MATCH_CLOSEST;
            state.conversationRules = new AIConsoleDataStructure.ConversationRules();
            buildSummary(state, null);
            return state;
        }

        AIAgent__c agent = AIConsoleAgentService.queryAgent(agentId);

        state.agentId = agent.Id;
        state.agentName = agent.Name;
        state.lastSaved = agent.SetupLastEdited__c != null ? agent.SetupLastEdited__c : agent.LastModifiedDate;
        state.setupStep = AIConsoleUtility.setupStep(agent);
        state.isSetupComplete = AIConsoleUtility.isSetupComplete(agent);
        state.isActive = agent.IsActive__c == true;
        state.isTestMode = agent.IsTestModeEnabled__c == true;
        state.statusLabel = state.isSetupComplete ? AIConsoleUtility.agentStatusLabel(agent) : (String.isBlank(agent.SetupStatus__c) ? AIConsoleConstants.SETUP_STATUS_DRAFT : agent.SetupStatus__c);
        state.noMatchBehavior = String.isBlank(agent.NoMatchBehavior__c) ? AIConsoleConstants.NO_MATCH_CLOSEST : agent.NoMatchBehavior__c;

        AIConsoleDataStructure.WizardBasics basics = new AIConsoleDataStructure.WizardBasics();
        basics.name = agent.Name;
        basics.developerName = agent.DeveloperName__c;
        basics.objectType = agent.ObjectType__c;
        basics.description = agent.Description__c;
        basics.persona = agent.AIAgentPersona__c;
        basics.modelId = agent.AIModelConfiguration__c;
        basics.maxIterations = AIConsoleUtility.toInteger(agent.MaxToolCallingIterations__c);
        basics.greeting = agent.GreetingMessage__c;
        basics.fallback = agent.AIFallbackMessage__c;
        state.basics = basics;

        state.templates = getTemplates(agent);
        state.dataSources = getAssignedSources(agent);
        state.workflowActions = getAssignedActions(agent.Id);
        state.violationRules = getRules(agent.Id);

        AIConsoleDataStructure.ConversationRules rules = new AIConsoleDataStructure.ConversationRules();
        rules.loadTrigger = agent.ConversationLoadTrigger__c;
        rules.visibility = agent.ConversationVisibility__c;
        rules.singleActive = agent.SingleActiveConversationPer_Record__c == true;
        rules.allowResume = agent.AllowConversationResume__c == true;
        rules.idleTimeout = AIConsoleUtility.toInteger(agent.IdleTimeoutMinutes__c);
        rules.maxMessages = AIConsoleUtility.toInteger(agent.MaxMessagesPerConversation__c);
        rules.maxTokens = agent.MaxTokensPerConversation__c;
        rules.tokenTracking = agent.TokenTrackingMethod__c;
        rules.retentionDays = AIConsoleUtility.toInteger(agent.ConversationRetentionDays__c);
        rules.retentionTrigger = agent.RetentionTrigger__c;
        rules.globalBudget = settings.GlobalTokenBudgetPerDay__c;
        state.conversationRules = rules;

        buildSummary(state, agent);
        return state;
    }

    // =============================================================
    // Step 1 - Basics
    // =============================================================

    public static AIConsoleDataStructure.WizardState saveBasics(Id agentId, AIConsoleDataStructure.WizardBasics basics, Integer nextStep) {

        if (basics == null || String.isBlank(basics.name)) throw new AIConsoleDataStructure.AIConsoleException('Agent Name is required.');
        if (String.isBlank(basics.objectType)) throw new AIConsoleDataStructure.AIConsoleException('Object is required.');
        if (String.isBlank(basics.modelId)) throw new AIConsoleDataStructure.AIConsoleException('Pick a Model Configuration.');
        if (Schema.getGlobalDescribe().get(basics.objectType) == null) throw new AIConsoleDataStructure.AIConsoleException(basics.objectType + ' isn\'t an object in this org.');

        Integer cap = AIAssistSettingsService.getMaxToolCallingIterationsCap();
        if (basics.maxIterations != null && (basics.maxIterations < 1 || basics.maxIterations > cap)) throw new AIConsoleDataStructure.AIConsoleException('Max Tool Calling Iterations must be between 1 and ' + cap + '.');

        AIAgent__c agent = agentId == null ? new AIAgent__c(SetupStatus__c = AIConsoleConstants.SETUP_STATUS_DRAFT, SetupCurrentStep__c = 1, IsActive__c = false, NoMatchBehavior__c = AIConsoleConstants.NO_MATCH_CLOSEST)
                                           : new AIAgent__c(Id = AIConsoleAgentService.queryAgent(agentId).Id);

        agent.Name = basics.name.trim().left(80);
        agent.DeveloperName__c = String.isBlank(basics.developerName) ? null : basics.developerName.trim().left(75);
        agent.ObjectType__c = basics.objectType;
        agent.Description__c = basics.description;
        agent.AIAgentPersona__c = basics.persona;
        agent.AIModelConfiguration__c = basics.modelId;
        agent.MaxToolCallingIterations__c = basics.maxIterations;
        agent.GreetingMessage__c = basics.greeting;
        agent.AIFallbackMessage__c = basics.fallback;
        agent.SetupLastEdited__c = System.now();

        upsert agent;

        advanceStep(agent.Id, nextStep);
        return getWizard(agent.Id);
    }

    // =============================================================
    // Step 2 - Prompt Templates
    // =============================================================

    public static AIConsoleDataStructure.WizardState saveTemplate(Id agentId, AIConsoleDataStructure.TemplateView template) {

        AIAgent__c agent = AIConsoleAgentService.queryAgent(agentId);

        if (template == null || String.isBlank(template.name)) throw new AIConsoleDataStructure.AIConsoleException('Template Name is required.');
        if (String.isBlank(template.prompt)) throw new AIConsoleDataStructure.AIConsoleException('AI Prompt is required.');

        AIPromptTemplate__c record = template.id == null ? new AIPromptTemplate__c(AIAgent__c = agent.Id) : new AIPromptTemplate__c(Id = assertTemplate(agentId, template.id).Id);
        record.Name = template.name.trim().left(80);
        record.DeveloperName__c = String.isBlank(template.developerName) ? null : template.developerName.trim().left(75);
        record.Description__c = template.description;
        record.IsActive__c = template.isActive == true;
        record.AISystemContext__c = template.systemContext;
        record.AITone__c = template.tone;
        record.AIPrompt__c = template.prompt;
        record.AIExclusionRules__c = template.exclusions;
        record.MaxResponseLength__c = template.maxResponseLength;
        record.TriggerKeywords__c = template.keywords == null || template.keywords.isEmpty() ? null : String.join(template.keywords, ', ');
        record.ActivationCriteria__c = serializeCriteria(template.criteriaLogic, template.conditions);

        upsert record;
        touch(agent.Id);
        return getWizard(agent.Id);
    }

    public static AIConsoleDataStructure.WizardState setTemplateActive(Id agentId, Id templateId, Boolean isActive) {
        AIPromptTemplate__c template = assertTemplate(agentId, templateId);
        template.IsActive__c = isActive == true;
        update template;
        touch(agentId);
        return getWizard(agentId);
    }

    public static AIConsoleDataStructure.WizardState cloneTemplate(Id agentId, Id templateId) {

        assertTemplate(agentId, templateId);

        AIPromptTemplate__c source = [ SELECT Name, AIAgent__c, AIExclusionRules__c, AIPrompt__c, AISystemContext__c, AITone__c, Description__c, MaxResponseLength__c, TriggerKeywords__c, ActivationCriteria__c
                                       FROM AIPromptTemplate__c WHERE Id = :templateId ];
        AIPromptTemplate__c copy = source.clone(false, true, false, false);
        copy.Name = (source.Name + ' (copy)').left(80);
        copy.IsActive__c = false;
        insert copy;

        touch(agentId);
        return getWizard(agentId);
    }

    public static AIConsoleDataStructure.WizardState deleteTemplate(Id agentId, Id templateId) {
        delete assertTemplate(agentId, templateId);
        touch(agentId);
        return getWizard(agentId);
    }

    public static AIConsoleDataStructure.WizardState saveNoMatchBehavior(Id agentId, String behavior) {

        if (behavior != AIConsoleConstants.NO_MATCH_CLOSEST && behavior != AIConsoleConstants.NO_MATCH_FALLBACK) throw new AIConsoleDataStructure.AIConsoleException('Pick what happens when no template matches.');

        update new AIAgent__c(Id = AIConsoleAgentService.queryAgent(agentId).Id, NoMatchBehavior__c = behavior, SetupLastEdited__c = System.now());
        return getWizard(agentId);
    }

    // =============================================================
    // Step 3 - Data Sources
    // =============================================================

    // The Library table under "Add from the Library" - everything not yet assigned. onlyThisObject keeps sources that can run on the agent's object (bound to it, or unbound).
    public static List<AIConsoleDataStructure.LibrarySource> getLibrarySources(Id agentId, String searchText, Boolean onlyThisObject) {

        AIAgent__c agent = AIConsoleAgentService.queryAgent(agentId);

        Set<Id> assigned = new Set<Id>();
        for (AIAgentDataSource__c link : [ SELECT AIDataSource__c FROM AIAgentDataSource__c WHERE AIAgent__c = :agentId ]) assigned.add(link.AIDataSource__c);

        Map<Id, Integer> usedBy = new Map<Id, Integer>();
        for (AggregateResult row : [ SELECT AIDataSource__c sourceId, COUNT(Id) total FROM AIAgentDataSource__c GROUP BY AIDataSource__c ]) usedBy.put((Id) row.get('sourceId'), (Integer) row.get('total'));

        String search = String.isBlank(searchText) ? '%' : '%' + searchText.trim() + '%';
        List<AIConsoleDataStructure.LibrarySource> sources = new List<AIConsoleDataStructure.LibrarySource>();

        for (AIDataSource__c source : [ SELECT Id, Name, SourceName__c, DeveloperName__c, Description__c, SourceType__c, BindingType__c, TargetObject__c FROM AIDataSource__c
                                        WHERE Id NOT IN :assigned AND IsActive__c = true AND (SourceName__c LIKE :search OR DeveloperName__c LIKE :search OR TargetObject__c LIKE :search)
                                        ORDER BY SourceName__c NULLS LAST, DeveloperName__c LIMIT 200 ]) {

            Boolean runsHere = source.BindingType__c != AIConsoleConstants.BINDING_BOUND || (source.TargetObject__c != null && source.TargetObject__c.equalsIgnoreCase(agent.ObjectType__c));
            if (onlyThisObject == true && !runsHere) continue;

            AIConsoleDataStructure.LibrarySource option = new AIConsoleDataStructure.LibrarySource();
            option.id = source.Id;
            option.name = AIConsoleUtility.dataSourceName(source);
            option.description = source.Description__c;
            option.sourceType = source.SourceType__c;
            option.bindingType = source.BindingType__c;
            option.targetObject = source.TargetObject__c;
            option.usedBy = usedBy.containsKey(source.Id) ? usedBy.get(source.Id) : 0;
            option.runsOnObject = runsHere;
            sources.add(option);
        }

        return sources;
    }

    public static AIConsoleDataStructure.WizardState assignDataSources(Id agentId, List<Id> dataSourceIds) {

        AIConsoleAgentService.queryAgent(agentId);
        if (dataSourceIds == null || dataSourceIds.isEmpty()) return getWizard(agentId);

        Set<Id> assigned = new Set<Id>();
        for (AIAgentDataSource__c link : [ SELECT AIDataSource__c FROM AIAgentDataSource__c WHERE AIAgent__c = :agentId ]) assigned.add(link.AIDataSource__c);

        List<AIAgentDataSource__c> links = new List<AIAgentDataSource__c>();
        for (AIDataSource__c source : [ SELECT Id FROM AIDataSource__c WHERE Id IN :dataSourceIds ]) {
            if (!assigned.contains(source.Id)) links.add(new AIAgentDataSource__c(AIAgent__c = agentId, AIDataSource__c = source.Id, IsActive__c = true));
        }
        insert links;

        touch(agentId);
        return getWizard(agentId);
    }

    public static AIConsoleDataStructure.WizardState setDataSourceActive(Id agentId, Id linkId, Boolean isActive) {
        AIAgentDataSource__c link = [ SELECT Id FROM AIAgentDataSource__c WHERE Id = :linkId AND AIAgent__c = :agentId LIMIT 1 ];
        link.IsActive__c = isActive == true;
        update link;
        touch(agentId);
        return getWizard(agentId);
    }

    public static AIConsoleDataStructure.WizardState removeDataSource(Id agentId, Id linkId) {
        delete [ SELECT Id FROM AIAgentDataSource__c WHERE Id = :linkId AND AIAgent__c = :agentId ];
        touch(agentId);
        return getWizard(agentId);
    }

    // =============================================================
    // Step 4 - Workflow Actions
    // =============================================================

    public static List<AIConsoleDataStructure.LibraryAction> getLibraryActions(Id agentId) {

        AIAgent__c agent = AIConsoleAgentService.queryAgent(agentId);

        Set<Id> assigned = new Set<Id>();
        for (AIAgentWorkflowAction__c link : [ SELECT AIWorkflowAction__c FROM AIAgentWorkflowAction__c WHERE AIAgent__c = :agentId ]) assigned.add(link.AIWorkflowAction__c);

        List<AIConsoleDataStructure.LibraryAction> actions = new List<AIConsoleDataStructure.LibraryAction>();
        for (AIWorkflowAction__c action : [ SELECT Id, Name, ActionName__c, DeveloperName__c, Description__c, ActionType__c, ExecutionType__c, TargetObject__c, RequiresConfirmation__c FROM AIWorkflowAction__c
                                            WHERE Id NOT IN :assigned AND IsActive__c = true ORDER BY ActionName__c NULLS LAST, DeveloperName__c LIMIT 200 ]) {
            AIConsoleDataStructure.LibraryAction option = new AIConsoleDataStructure.LibraryAction();
            option.id = action.Id;
            option.name = AIConsoleUtility.workflowActionName(action);
            option.description = action.Description__c;
            option.actionType = action.ActionType__c;
            option.executionType = action.ExecutionType__c;
            option.targetObject = action.TargetObject__c;
            option.requiresConfirmation = action.RequiresConfirmation__c == true;
            actions.add(option);
        }

        return actions;
    }

    public static AIConsoleDataStructure.WizardState assignWorkflowActions(Id agentId, List<Id> actionIds) {

        AIConsoleAgentService.queryAgent(agentId);
        if (actionIds == null || actionIds.isEmpty()) return getWizard(agentId);

        Set<Id> assigned = new Set<Id>();
        for (AIAgentWorkflowAction__c link : [ SELECT AIWorkflowAction__c FROM AIAgentWorkflowAction__c WHERE AIAgent__c = :agentId ]) assigned.add(link.AIWorkflowAction__c);

        List<AIAgentWorkflowAction__c> links = new List<AIAgentWorkflowAction__c>();
        for (AIWorkflowAction__c action : [ SELECT Id FROM AIWorkflowAction__c WHERE Id IN :actionIds ]) {
            if (!assigned.contains(action.Id)) links.add(new AIAgentWorkflowAction__c(AIAgent__c = agentId, AIWorkflowAction__c = action.Id, IsActive__c = true));
        }
        insert links;

        touch(agentId);
        return getWizard(agentId);
    }

    public static AIConsoleDataStructure.WizardState setWorkflowActionActive(Id agentId, Id linkId, Boolean isActive) {
        AIAgentWorkflowAction__c link = [ SELECT Id FROM AIAgentWorkflowAction__c WHERE Id = :linkId AND AIAgent__c = :agentId LIMIT 1 ];
        link.IsActive__c = isActive == true;
        update link;
        touch(agentId);
        return getWizard(agentId);
    }

    public static AIConsoleDataStructure.WizardState removeWorkflowAction(Id agentId, Id linkId) {
        delete [ SELECT Id FROM AIAgentWorkflowAction__c WHERE Id = :linkId AND AIAgent__c = :agentId ];
        touch(agentId);
        return getWizard(agentId);
    }

    // =============================================================
    // Step 5 - Guardrails
    // =============================================================

    public static AIConsoleDataStructure.WizardState saveRule(Id agentId, AIConsoleDataStructure.RuleView rule) {

        AIConsoleAgentService.queryAgent(agentId);

        if (rule == null || String.isBlank(rule.name)) throw new AIConsoleDataStructure.AIConsoleException('Rule Name is required.');
        if (String.isBlank(rule.detectionMethod)) throw new AIConsoleDataStructure.AIConsoleException('Pick a Detection Method.');
        if (String.isBlank(rule.violationType)) throw new AIConsoleDataStructure.AIConsoleException('Pick the Violation Type Produced.');
        if (rule.detectionMethod == AIConsoleConstants.DETECTION_AI_EVALUATED && String.isBlank(rule.instruction)) throw new AIConsoleDataStructure.AIConsoleException('AI-evaluated rules need an AI Detection Instruction.');
        if (String.isBlank(rule.signalTag)) throw new AIConsoleDataStructure.AIConsoleException('Signal Tag is required.');

        AIViolationRule__c record = rule.id == null ? new AIViolationRule__c(Agent__c = agentId) : assertRule(agentId, rule.id);
        record.RuleName__c = rule.name.trim().left(80);
        record.DeveloperName__c = String.isBlank(rule.developerName) ? rule.name.trim().replaceAll('[^a-zA-Z0-9]+', '_').replaceAll('^_+|_+$', '').left(75) : rule.developerName.trim().left(75);
        record.DetectionMethod__c = rule.detectionMethod;
        record.AIDetectionInstruction__c = rule.instruction;
        record.SignalTag__c = rule.signalTag.trim().toUpperCase().left(40);
        record.ViolationTypeProduced__c = rule.violationType;
        record.BlockRequest__c = rule.blockRequest == true;
        record.Active__c = rule.isActive != false;

        upsert record;
        touch(agentId);
        return getWizard(agentId);
    }

    public static AIConsoleDataStructure.WizardState setRuleActive(Id agentId, Id ruleId, Boolean isActive) {
        AIViolationRule__c rule = assertRule(agentId, ruleId);
        rule.Active__c = isActive == true;
        update rule;
        touch(agentId);
        return getWizard(agentId);
    }

    public static AIConsoleDataStructure.WizardState deleteRule(Id agentId, Id ruleId) {
        delete assertRule(agentId, ruleId);
        touch(agentId);
        return getWizard(agentId);
    }

    // =============================================================
    // Step 6 - Conversation Rules
    // =============================================================

    public static AIConsoleDataStructure.WizardState saveConversationRules(Id agentId, AIConsoleDataStructure.ConversationRules rules, Integer nextStep) {

        AIConsoleAgentService.queryAgent(agentId);
        if (rules == null) throw new AIConsoleDataStructure.AIConsoleException('Nothing to save.');

        for (Decimal value : new List<Decimal>{ rules.idleTimeout, rules.maxMessages, rules.maxTokens, rules.retentionDays }) {
            if (value != null && value < 0) throw new AIConsoleDataStructure.AIConsoleException('Limits can\'t be negative.');
        }

        update new AIAgent__c(
            Id = agentId,
            ConversationLoadTrigger__c = rules.loadTrigger,
            ConversationVisibility__c = rules.visibility,
            SingleActiveConversationPer_Record__c = rules.singleActive == true,
            AllowConversationResume__c = rules.allowResume == true,
            IdleTimeoutMinutes__c = rules.idleTimeout,
            MaxMessagesPerConversation__c = rules.maxMessages,
            MaxTokensPerConversation__c = rules.maxTokens,
            TokenTrackingMethod__c = rules.tokenTracking,
            ConversationRetentionDays__c = rules.retentionDays,
            RetentionTrigger__c = rules.retentionTrigger,
            SetupLastEdited__c = System.now()
        );

        advanceStep(agentId, nextStep);
        return getWizard(agentId);
    }

    // =============================================================
    // Moving between steps, and finishing
    // =============================================================

    // Records the furthest step reached. Reaching Review moves a Draft to In Progress.
    public static AIConsoleDataStructure.WizardState goToStep(Id agentId, Integer nextStep) {
        AIConsoleAgentService.queryAgent(agentId);
        advanceStep(agentId, nextStep);
        return getWizard(agentId);
    }

    // mode: activate | test | inactive (AIConsoleConstants.GO_LIVE_*)
    public static AIConsoleDataStructure.WizardState finish(Id agentId, String mode) {

        AIAgent__c agent = AIConsoleAgentService.queryAgent(agentId);
        if (agent.AIModelConfiguration__c == null) throw new AIConsoleDataStructure.AIConsoleException('Pick a Model Configuration in Basics before finishing.');

        AIAgent__c changes = new AIAgent__c(Id = agentId, SetupStatus__c = AIConsoleConstants.SETUP_STATUS_COMPLETE, SetupCurrentStep__c = AIConsoleConstants.WIZARD_STEP_COUNT, SetupLastEdited__c = System.now());

        if (mode == AIConsoleConstants.GO_LIVE_ACTIVATE) {
            changes.IsActive__c = true;
            changes.IsTestModeEnabled__c = false;
        } else if (mode == AIConsoleConstants.GO_LIVE_TEST_MODE) {
            changes.IsActive__c = true;
            changes.IsTestModeEnabled__c = true;
        } else if (mode == AIConsoleConstants.GO_LIVE_INACTIVE) {
            changes.IsActive__c = false;
            changes.IsTestModeEnabled__c = false;
        } else {
            throw new AIConsoleDataStructure.AIConsoleException('Pick how the agent goes live.');
        }

        update changes;
        return getWizard(agentId);
    }

    private static void advanceStep(Id agentId, Integer nextStep) {

        if (nextStep == null) {
            touch(agentId);
            return;
        }

        AIAgent__c agent = AIConsoleAgentService.queryAgent(agentId);
        Integer target = Math.max(1, Math.min(AIConsoleConstants.WIZARD_STEP_COUNT, nextStep));

        AIAgent__c changes = new AIAgent__c(Id = agentId, SetupLastEdited__c = System.now());
        if (target > AIConsoleUtility.setupStep(agent)) changes.SetupCurrentStep__c = target;

        Boolean reachedReview = target >= AIConsoleConstants.WIZARD_STEP_COUNT && !AIConsoleUtility.isSetupComplete(agent);
        if (reachedReview) changes.SetupStatus__c = AIConsoleConstants.SETUP_STATUS_IN_PROGRESS;
        if (String.isBlank(agent.SetupStatus__c)) changes.SetupStatus__c = AIConsoleConstants.SETUP_STATUS_DRAFT;

        update changes;
    }

    private static void touch(Id agentId) {
        update new AIAgent__c(Id = agentId, SetupLastEdited__c = System.now());
    }

    // =============================================================
    // Step 7 - Try it
    // =============================================================

    public static AIConsoleDataStructure.TryItResult sendTryIt(Id agentId, Id recordId, String text, Id conversationId) {

        AIAgent__c agent = AIConsoleAgentService.queryAgent(agentId);

        if (agent.IsActive__c != true) throw new AIConsoleDataStructure.AIConsoleException('Turn on test mode to try the agent. Test mode keeps it hidden from everyone except admins and testers.');
        if (recordId == null) throw new AIConsoleDataStructure.AIConsoleException('Pick a record to test against.');
        if (String.isBlank(text)) throw new AIConsoleDataStructure.AIConsoleException('Type a test question first.');

        String objectApiName = recordId.getSobjectType().getDescribe().getName();
        if (String.isNotBlank(agent.ObjectType__c) && !objectApiName.equalsIgnoreCase(agent.ObjectType__c)) throw new AIConsoleDataStructure.AIConsoleException('Pick a ' + agent.ObjectType__c + ' record - this agent runs on ' + agent.ObjectType__c + '.');

        try {
            AIConversationMessage__c message = AIConversationMessageService.sendMessage(conversationId, agentId, text.trim(), AIConsoleConstants.TRY_IT_CHANNEL, objectApiName, recordId);
            return getTryItUpdate(message.AIConversation__c);
        } catch (AIConversationMessageService.AIConversationMessageServiceException refusal) {
            throw new AIConsoleDataStructure.AIConsoleException(refusal.getMessage().startsWith('Failed to') ? 'The test message couldn\'t be sent. Please try again.' : refusal.getMessage());
        }
    }

    public static AIConsoleDataStructure.TryItResult getTryItUpdate(Id conversationId) {

        List<AIConversation__c> conversations = [ SELECT Id, OwnerId, ProcessingLockedUntil__c, AIPromptTemplate__r.Name FROM AIConversation__c WHERE Id = :conversationId LIMIT 1 ];
        if (conversations.isEmpty() || conversations[0].OwnerId != UserInfo.getUserId()) throw new AIConsoleDataStructure.AIConsoleException('That test conversation isn\'t yours.');

        AIConversation__c conversation = conversations[0];
        AIConsoleDataStructure.TryItResult result = new AIConsoleDataStructure.TryItResult();
        result.conversationId = conversation.Id;
        result.isProcessing = conversation.ProcessingLockedUntil__c != null && conversation.ProcessingLockedUntil__c > System.now();

        List<AIConversationMessage__c> messages = [ SELECT Id, Sender__c, MessageBody__c, TokenCount__c, CreatedDate FROM AIConversationMessage__c WHERE AIConversation__c = :conversationId ORDER BY CreatedDate ASC, Id ASC LIMIT 200 ];
        Map<String, String> realByFake = AIConsoleActivityService.getRealValueByFakeValue(conversationId);

        AIConversationMessage__c lastReply;
        Datetime lastUserMessageAt;
        for (AIConversationMessage__c message : messages) {
            AIConsoleDataStructure.TranscriptMessage view = AIConsoleActivityService.toTranscriptMessage(message, UserInfo.getName(), realByFake);
            result.messages.add(view);
            result.lastMessageId = message.Id;
            if (message.Sender__c == AIAssistApplicationConstants.SENDER_AI_AGENT) lastReply = message;
            if (message.Sender__c == AIAssistApplicationConstants.SENDER_USER) lastUserMessageAt = message.CreatedDate;
        }

        Boolean replyIsCurrent = lastReply != null && lastUserMessageAt != null && lastReply.CreatedDate >= lastUserMessageAt;
        if (replyIsCurrent && !result.isProcessing) {

            result.howItAnswered.add('Template: ' + (conversation.AIPromptTemplate__r?.Name == null ? 'none matched' : conversation.AIPromptTemplate__r.Name));

            List<String> sourceNames = new List<String>();
            for (AIExecutionStep__c step : [ SELECT AIDataSource__r.SourceName__c, AIDataSource__r.DeveloperName__c, AIDataSource__r.Name FROM AIExecutionStep__c WHERE AIConversationMessage__c = :lastReply.Id AND AIDataSource__c != null ORDER BY StepOrder__c ]) {
                String sourceName = AIConsoleUtility.dataSourceName(step.AIDataSource__r);
                if (!sourceNames.contains(sourceName)) sourceNames.add(sourceName);
            }
            result.howItAnswered.add('Data sources: ' + (sourceNames.isEmpty() ? 'none called' : String.join(sourceNames, ', ')));

            List<String> fired = new List<String>();
            for (AIViolation__c violation : [ SELECT AIViolationRule__r.RuleName__c, ViolationType__c FROM AIViolation__c WHERE AIConversation__c = :conversationId AND CreatedDate >= :lastUserMessageAt ]) {
                fired.add(violation.AIViolationRule__r?.RuleName__c != null ? violation.AIViolationRule__r.RuleName__c : violation.ViolationType__c);
            }
            result.howItAnswered.add('Guardrails: ' + (fired.isEmpty() ? 'none fired' : String.join(fired, ', ')) + ' · ' + AIConsoleUtility.formatNumber(lastReply.TokenCount__c) + ' tokens');
        }

        return result;
    }

    // =============================================================
    // Summary rail, readiness checks and review
    // =============================================================

    private static void buildSummary(AIConsoleDataStructure.WizardState state, AIAgent__c agent) {

        String objectLabel = state.basics.objectType == null ? null : AIConsoleUtility.objectLabel(state.basics.objectType);
        String modelName;
        Boolean modelActive = false;
        for (AIConsoleDataStructure.ModelOption model : state.modelOptions) {
            if (model.id == state.basics.modelId) {
                modelName = model.name;
                modelActive = true;
            }
        }
        if (modelName == null && agent != null && agent.AIModelConfiguration__c != null) modelName = agent.AIModelConfiguration__r.Name; // Set, but no longer active.

        Integer activeTemplates = 0;
        Integer maxLength;
        String maxLengthTemplate;
        List<String> templateNames = new List<String>();
        for (AIConsoleDataStructure.TemplateView template : state.templates) {
            templateNames.add(template.name);
            if (template.isActive) activeTemplates++;
            if (template.isActive && template.maxResponseLength != null && (maxLength == null || template.maxResponseLength > maxLength)) {
                maxLength = template.maxResponseLength;
                maxLengthTemplate = template.name;
            }
        }

        List<String> mismatched = new List<String>();
        Integer activeSources = 0;
        Map<String, Integer> sourcesByType = new Map<String, Integer>();
        for (AIConsoleDataStructure.AssignedSource source : state.dataSources) {
            if (source.isMismatch) mismatched.add(source.name);
            if (source.isActive) activeSources++;
            String type = String.isBlank(source.sourceType) ? 'Other' : source.sourceType;
            sourcesByType.put(type, (sourcesByType.containsKey(type) ? sourcesByType.get(type) : 0) + 1);
        }

        Integer writeActions = 0;
        Integer writeWithoutConfirm = 0;
        for (AIConsoleDataStructure.AssignedAction action : state.workflowActions) {
            if (action.executionType == AIConsoleConstants.EXECUTION_WRITE) {
                writeActions++;
                if (!action.requiresConfirmation) writeWithoutConfirm++;
            }
        }

        Integer activeRules = 0;
        Integer blockingRules = 0;
        Integer aiRules = 0;
        for (AIConsoleDataStructure.RuleView rule : state.violationRules) {
            if (!rule.isActive) continue;
            activeRules++;
            if (rule.blockRequest) blockingRules++;
            if (rule.detectionMethod == AIConsoleConstants.DETECTION_AI_EVALUATED) aiRules++;
        }

        AIConsoleDataStructure.ConversationRules rules = state.conversationRules;
        Boolean limitsSet = rules != null && rules.maxMessages != null && rules.maxTokens != null && rules.retentionDays != null;

        // Summary rail
        state.summary.add(new AIConsoleDataStructure.SummaryItem('Basics', joinDot(new List<String>{ objectLabel, modelName })));
        state.summary.add(new AIConsoleDataStructure.SummaryItem('Prompt Templates', templateSummary(state.templates.size(), activeTemplates)));
        state.summary.add(new AIConsoleDataStructure.SummaryItem('Data Sources', state.dataSources.size() + ' assigned' + (mismatched.isEmpty() ? '' : ' · ' + mismatched.size() + (mismatched.size() == 1 ? ' needs a look' : ' need a look'))));
        state.summary.add(new AIConsoleDataStructure.SummaryItem('Workflow Actions', state.workflowActions.size() + ' assigned' + (writeActions == 0 ? '' : ' · ' + writeActions + (writeActions == 1 ? ' writes data' : ' write data'))));
        state.summary.add(new AIConsoleDataStructure.SummaryItem('Guardrails', state.violationRules.size() + (state.violationRules.size() == 1 ? ' rule' : ' rules') + ' · ' + blockingRules + ' block'));
        state.summary.add(new AIConsoleDataStructure.SummaryItem('Conversation Rules', rules == null ? '' : joinDot(new List<String>{
            rules.maxMessages == null ? null : rules.maxMessages + ' messages',
            rules.maxTokens == null ? null : AIConsoleUtility.compactNumber(rules.maxTokens) + ' tokens',
            rules.retentionDays == null ? null : rules.retentionDays + ' days' })));
        state.summary.add(new AIConsoleDataStructure.SummaryItem('Review & Activate', state.isSetupComplete ? state.statusLabel : 'Test, then activate'));

        // Readiness checks
        state.checks.add(new AIConsoleDataStructure.ReadinessCheck(2, modelActive ? 'ok' : 'warn', modelActive ? 'Model configuration is active' : (modelName == null ? 'No model configuration picked' : modelName + ' is inactive')));
        state.checks.add(new AIConsoleDataStructure.ReadinessCheck(3, activeTemplates > 0 ? 'ok' : 'warn', activeTemplates > 0 ? 'At least one active prompt template' : 'No active prompt template'));

        if (mismatched.isEmpty()) {
            state.checks.add(new AIConsoleDataStructure.ReadinessCheck(4, 'ok', objectLabel == null ? 'Every data source can run here' : 'Every data source can run on ' + objectLabel + ' pages'));
        } else {
            for (AIConsoleDataStructure.AssignedSource source : state.dataSources) {
                if (!source.isMismatch) continue;
                String warning = source.name + ' is bound to ' + source.targetObject + ' and won’t run on ' + objectLabel + ' pages';
                state.checks.add(new AIConsoleDataStructure.ReadinessCheck(4, 'warn', warning));
                state.warnings.add(warning);
            }
        }

        if (writeActions == 0) state.checks.add(new AIConsoleDataStructure.ReadinessCheck(5, 'ok', 'No actions write data'));
        else if (writeWithoutConfirm == 0) state.checks.add(new AIConsoleDataStructure.ReadinessCheck(5, 'ok', writeActions == 1 ? 'The write action asks users to confirm' : 'Every write action asks users to confirm'));
        else state.checks.add(new AIConsoleDataStructure.ReadinessCheck(5, 'warn', writeWithoutConfirm + (writeWithoutConfirm == 1 ? ' write action runs' : ' write actions run') + ' without asking'));

        state.checks.add(new AIConsoleDataStructure.ReadinessCheck(6, blockingRules > 0 ? 'ok' : 'warn', blockingRules > 0 ? 'At least one guardrail blocks requests' : 'No guardrail blocks requests'));
        state.checks.add(new AIConsoleDataStructure.ReadinessCheck(7, limitsSet ? 'ok' : 'warn', limitsSet ? 'Message, token and retention limits are set' : 'Set message, token and retention limits'));

        // Review
        Integer orgDefault = state.orgDefaultIterations;
        state.review.add(reviewSection(1, 'Basics', false, new List<String>{
            'Object', objectLabel, 'Model', modelName,
            'Max Tool Calling Iterations', state.basics.maxIterations == null ? 'Org default (' + orgDefault + ')' : String.valueOf(state.basics.maxIterations) }));

        state.review.add(reviewSection(2, 'Prompt Templates', activeTemplates == 0, new List<String>{
            'Templates', templateNames.isEmpty() ? 'None yet' : String.join(templateNames, ', '),
            'No match', state.noMatchBehavior == AIConsoleConstants.NO_MATCH_FALLBACK ? 'Show the fallback message' : 'Use the closest match',
            'Max response', maxLength == null ? 'Not set' : maxLength + ' words (' + maxLengthTemplate.toLowerCase() + ')' }));

        List<String> typeParts = new List<String>();
        for (String type : sourcesByType.keySet()) typeParts.add(sourcesByType.get(type) + ' ' + type);
        state.review.add(reviewSection(3, 'Data Sources', !mismatched.isEmpty(), new List<String>{
            'Assigned', state.dataSources.isEmpty() ? 'None' : state.dataSources.size() + (activeSources == state.dataSources.size() ? ', all active' : ', ' + activeSources + ' active'),
            'Types', typeParts.isEmpty() ? '—' : String.join(typeParts, ', '),
            'Needs a look', mismatched.isEmpty() ? 'Nothing' : String.join(mismatched, ', ') }));

        state.review.add(reviewSection(4, 'Workflow Actions', writeWithoutConfirm > 0, new List<String>{
            'Assigned', String.valueOf(state.workflowActions.size()),
            'Write actions', writeActions == 0 ? 'None' : writeActions + (writeWithoutConfirm == 0 ? ', asks to confirm' : ', ' + writeWithoutConfirm + ' without asking'),
            'Read-only', String.valueOf(state.workflowActions.size() - writeActions) }));

        state.review.add(reviewSection(5, 'Guardrails', blockingRules == 0, new List<String>{
            'Rules', activeRules + ' active', 'Blocking', String.valueOf(blockingRules), 'AI evaluated', String.valueOf(aiRules) }));

        state.review.add(reviewSection(6, 'Conversation Rules', !limitsSet, new List<String>{
            'Limits', rules == null ? '—' : joinDot(new List<String>{ rules.maxMessages == null ? null : rules.maxMessages + ' messages', rules.maxTokens == null ? null : AIConsoleUtility.formatNumber(rules.maxTokens) + ' tokens' }),
            'Loads', rules == null ? '—' : joinDot(new List<String>{ rules.loadTrigger, rules.visibility }),
            'Retention', rules == null || rules.retentionDays == null ? 'Not set' : rules.retentionDays + ' days after ' + retentionShort(rules.retentionTrigger) }));
    }

    private static AIConsoleDataStructure.ReviewSection reviewSection(Integer step, String title, Boolean needsLook, List<String> labelValues) {
        AIConsoleDataStructure.ReviewSection section = new AIConsoleDataStructure.ReviewSection();
        section.step = step;
        section.title = title;
        section.needsLook = needsLook;
        for (Integer index = 0; index < labelValues.size(); index += 2) {
            section.values.add(new AIConsoleDataStructure.SummaryItem(labelValues[index], String.isBlank(labelValues[index + 1]) ? '—' : labelValues[index + 1]));
        }
        return section;
    }

    private static String templateSummary(Integer total, Integer active) {
        if (total == 0) return 'No templates yet';
        if (total == active) return total + (total == 1 ? ' template, active' : (total == 2 ? ' templates, both active' : ' templates, all active'));
        return total + (total == 1 ? ' template, ' : ' templates, ') + active + ' active';
    }

    private static String retentionShort(String retentionTrigger) {
        if (retentionTrigger == AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE) return 'creation';
        if (retentionTrigger == AIAssistApplicationConstants.RETENTION_TRIGGER_LAST_MESSAGE_DATE) return 'the last message';
        return 'close';
    }

    private static String joinDot(List<String> parts) {
        List<String> present = new List<String>();
        for (String part : parts) if (String.isNotBlank(part)) present.add(part);
        return String.join(present, ' · ');
    }

    // =============================================================
    // Readers
    // =============================================================

    private static List<AIConsoleDataStructure.TemplateView> getTemplates(AIAgent__c agent) {

        List<AIConsoleDataStructure.TemplateView> templates = new List<AIConsoleDataStructure.TemplateView>();

        for (AIPromptTemplate__c record : [ SELECT Id, Name, DeveloperName__c, Description__c, IsActive__c, ActivationCriteria__c, TriggerKeywords__c, AISystemContext__c, AITone__c, AIPrompt__c, AIExclusionRules__c, MaxResponseLength__c
                                            FROM AIPromptTemplate__c WHERE AIAgent__c = :agent.Id ORDER BY CreatedDate ASC ]) {

            AIConsoleDataStructure.TemplateView view = new AIConsoleDataStructure.TemplateView();
            view.id = record.Id;
            view.name = record.Name;
            view.developerName = record.DeveloperName__c;
            view.description = record.Description__c;
            view.isActive = record.IsActive__c == true;
            view.systemContext = record.AISystemContext__c;
            view.tone = record.AITone__c;
            view.prompt = record.AIPrompt__c;
            view.exclusions = record.AIExclusionRules__c;
            view.maxResponseLength = AIConsoleUtility.toInteger(record.MaxResponseLength__c);

            AIConsoleDataStructure.ActivationCriteria criteria = parseCriteria(record.ActivationCriteria__c);
            view.criteriaLogic = criteria.logic;
            view.conditions = criteria.conditions;
            view.criteriaSummary = criteria.conditions.isEmpty() ? 'No criteria · the everyday template' : criteriaSummary(criteria, agent.ObjectType__c);

            if (String.isNotBlank(record.TriggerKeywords__c)) {
                for (String keyword : record.TriggerKeywords__c.split(',')) {
                    if (String.isNotBlank(keyword)) view.keywords.add(keyword.trim());
                }
            }

            templates.add(view);
        }

        return templates;
    }

    private static List<AIConsoleDataStructure.AssignedSource> getAssignedSources(AIAgent__c agent) {

        List<AIConsoleDataStructure.AssignedSource> sources = new List<AIConsoleDataStructure.AssignedSource>();
        for (AIAgentDataSource__c link : [ SELECT Id, IsActive__c, AIDataSource__c, AIDataSource__r.SourceName__c, AIDataSource__r.DeveloperName__c, AIDataSource__r.Name, AIDataSource__r.Description__c, AIDataSource__r.SourceType__c, AIDataSource__r.BindingType__c, AIDataSource__r.TargetObject__c
                                           FROM AIAgentDataSource__c WHERE AIAgent__c = :agent.Id ORDER BY CreatedDate ASC ]) {
            AIConsoleDataStructure.AssignedSource source = new AIConsoleDataStructure.AssignedSource();
            source.linkId = link.Id;
            source.dataSourceId = link.AIDataSource__c;
            source.name = AIConsoleUtility.dataSourceName(link.AIDataSource__r);
            source.description = link.AIDataSource__r.Description__c;
            source.sourceType = link.AIDataSource__r.SourceType__c;
            source.bindingType = link.AIDataSource__r.BindingType__c;
            source.targetObject = link.AIDataSource__r.TargetObject__c;
            source.isActive = link.IsActive__c == true;
            source.isMismatch = AIConsoleAgentService.isBoundElsewhere(source.bindingType, source.targetObject, agent.ObjectType__c);
            sources.add(source);
        }
        return sources;
    }

    private static List<AIConsoleDataStructure.AssignedAction> getAssignedActions(Id agentId) {

        List<AIConsoleDataStructure.AssignedAction> actions = new List<AIConsoleDataStructure.AssignedAction>();
        for (AIAgentWorkflowAction__c link : [ SELECT Id, IsActive__c, AIWorkflowAction__c, AIWorkflowAction__r.ActionName__c, AIWorkflowAction__r.DeveloperName__c, AIWorkflowAction__r.Name, AIWorkflowAction__r.Description__c, AIWorkflowAction__r.ActionType__c,
                                                      AIWorkflowAction__r.ExecutionType__c, AIWorkflowAction__r.FlowAPIName__c, AIWorkflowAction__r.ApexClassName__c,
                                                      AIWorkflowAction__r.RequiresConfirmation__c, AIWorkflowAction__r.ConfirmationMessage__c
                                               FROM AIAgentWorkflowAction__c WHERE AIAgent__c = :agentId ORDER BY CreatedDate ASC ]) {
            AIConsoleDataStructure.AssignedAction action = new AIConsoleDataStructure.AssignedAction();
            action.linkId = link.Id;
            action.actionId = link.AIWorkflowAction__c;
            action.name = AIConsoleUtility.workflowActionName(link.AIWorkflowAction__r);
            action.description = link.AIWorkflowAction__r.Description__c;
            action.actionType = link.AIWorkflowAction__r.ActionType__c;
            action.executionType = link.AIWorkflowAction__r.ExecutionType__c;
            action.implementationName = action.actionType == AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW ? link.AIWorkflowAction__r.FlowAPIName__c : link.AIWorkflowAction__r.ApexClassName__c;
            action.requiresConfirmation = link.AIWorkflowAction__r.RequiresConfirmation__c == true;
            action.confirmationMessage = link.AIWorkflowAction__r.ConfirmationMessage__c;
            action.isActive = link.IsActive__c == true;
            actions.add(action);
        }
        return actions;
    }

    private static List<AIConsoleDataStructure.RuleView> getRules(Id agentId) {

        List<AIConsoleDataStructure.RuleView> rules = new List<AIConsoleDataStructure.RuleView>();
        for (AIViolationRule__c record : [ SELECT Id, RuleName__c, DeveloperName__c, DetectionMethod__c, ViolationTypeProduced__c, BlockRequest__c, Active__c, AIDetectionInstruction__c, SignalTag__c
                                           FROM AIViolationRule__c WHERE Agent__c = :agentId ORDER BY CreatedDate ASC ]) {
            AIConsoleDataStructure.RuleView rule = new AIConsoleDataStructure.RuleView();
            rule.id = record.Id;
            rule.name = record.RuleName__c;
            rule.developerName = record.DeveloperName__c;
            rule.detectionMethod = record.DetectionMethod__c;
            rule.detectionLabel = AIConsoleAgentService.picklistLabel(AIViolationRule__c.DetectionMethod__c, record.DetectionMethod__c);
            rule.violationType = record.ViolationTypeProduced__c;
            rule.violationTypeLabel = AIConsoleAgentService.picklistLabel(AIViolationRule__c.ViolationTypeProduced__c, record.ViolationTypeProduced__c);
            rule.blockRequest = record.BlockRequest__c == true;
            rule.isActive = record.Active__c == true;
            rule.instruction = record.AIDetectionInstruction__c;
            rule.signalTag = record.SignalTag__c;
            rules.add(rule);
        }
        return rules;
    }

    public static List<AIConsoleDataStructure.ModelOption> getModelOptions(String defaultDeveloperName) {

        List<AIConsoleDataStructure.ModelOption> options = new List<AIConsoleDataStructure.ModelOption>();
        for (AIModelConfiguration__c model : [ SELECT Id, Name, DeveloperName__c, AIProvider__c, ModelIdentifier__c, Temperature__c, MaximumOutputTokens__c, RetryAttempts__c
                                               FROM AIModelConfiguration__c WHERE IsActive__c = true ORDER BY Name ]) {
            AIConsoleDataStructure.ModelOption option = new AIConsoleDataStructure.ModelOption();
            option.id = model.Id;
            option.name = model.Name;
            option.developerName = model.DeveloperName__c;
            option.provider = model.AIProvider__c;
            option.modelIdentifier = model.ModelIdentifier__c;
            option.isOrgDefault = String.isNotBlank(defaultDeveloperName) && model.DeveloperName__c == defaultDeveloperName;
            option.detail = joinDot(new List<String>{
                model.AIProvider__c,
                model.ModelIdentifier__c,
                model.Temperature__c == null ? null : 'temperature ' + model.Temperature__c.stripTrailingZeros().toPlainString(),
                model.MaximumOutputTokens__c == null ? null : 'up to ' + AIConsoleUtility.formatNumber(model.MaximumOutputTokens__c) + ' output tokens',
                model.RetryAttempts__c == null ? null : AIConsoleUtility.formatNumber(model.RetryAttempts__c) + (model.RetryAttempts__c == 1 ? ' retry' : ' retries') });
            options.add(option);
        }

        // Org default first.
        List<AIConsoleDataStructure.ModelOption> ordered = new List<AIConsoleDataStructure.ModelOption>();
        for (AIConsoleDataStructure.ModelOption option : options) if (option.isOrgDefault) ordered.add(option);
        for (AIConsoleDataStructure.ModelOption option : options) if (!option.isOrgDefault) ordered.add(option);
        return ordered;
    }

    // Objects an agent can run on - record-page objects the user can see. Custom Settings, Metadata and system objects are left out.
    public static List<AIConsoleDataStructure.Option> getObjectOptions() {

        List<AIConsoleDataStructure.Option> options = new List<AIConsoleDataStructure.Option>();

        try {
            for (EntityDefinition entity : [ SELECT QualifiedApiName, Label FROM EntityDefinition
                                             WHERE IsLayoutable = true AND IsQueryable = true AND IsCustomSetting = false AND IsApexTriggerable = true AND IsEverCreatable = true
                                             ORDER BY Label LIMIT 2000 ]) {
                if (entity.QualifiedApiName.endsWith('__mdt') || entity.QualifiedApiName.endsWith('__e')) continue;
                options.add(new AIConsoleDataStructure.Option(entity.Label, entity.QualifiedApiName));
            }
        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIConsoleWizardService', 'getObjectOptions');
        }

        if (options.isEmpty()) {
            for (String objectName : new List<String>{ 'Account', 'Case', 'Contact', 'Lead', 'Opportunity' }) {
                options.add(new AIConsoleDataStructure.Option(AIConsoleUtility.objectLabel(objectName), objectName));
            }
        }

        return options;
    }

    // =============================================================
    // Activation criteria (AIPromptTemplate__c.ActivationCriteria__c)
    // =============================================================

    public static AIConsoleDataStructure.ActivationCriteria parseCriteria(String criteriaJson) {

        AIConsoleDataStructure.ActivationCriteria criteria = new AIConsoleDataStructure.ActivationCriteria();
        criteria.logic = 'any';
        if (String.isBlank(criteriaJson)) return criteria;

        try {
            AIConsoleDataStructure.ActivationCriteria parsed = (AIConsoleDataStructure.ActivationCriteria) JSON.deserialize(criteriaJson, AIConsoleDataStructure.ActivationCriteria.class);
            if (parsed.logic == 'all') criteria.logic = 'all';
            if (parsed.conditions != null) {
                for (AIConsoleDataStructure.Condition condition : parsed.conditions) {
                    if (condition != null && String.isNotBlank(condition.field)) criteria.conditions.add(condition);
                }
            }
        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIConsoleWizardService', 'parseCriteria');
        }

        return criteria;
    }

    private static String serializeCriteria(String logic, List<AIConsoleDataStructure.Condition> conditions) {

        AIConsoleDataStructure.ActivationCriteria criteria = new AIConsoleDataStructure.ActivationCriteria();
        criteria.logic = logic == 'all' ? 'all' : 'any';

        if (conditions != null) {
            for (AIConsoleDataStructure.Condition condition : conditions) {
                if (condition == null || String.isBlank(condition.field)) continue;
                if (!OPERATOR_LABELS.containsKey(condition.operator)) condition.operator = 'equals';
                criteria.conditions.add(condition);
            }
        }

        return criteria.conditions.isEmpty() ? null : JSON.serialize(criteria);
    }

    public static String criteriaSummary(AIConsoleDataStructure.ActivationCriteria criteria) {
        return criteriaSummary(criteria, null);
    }

    // "Stage is Proposal or Negotiation" when every condition checks the same field for equality; otherwise each condition joined by or / and.
    public static String criteriaSummary(AIConsoleDataStructure.ActivationCriteria criteria, String objectApiName) {

        if (criteria == null || criteria.conditions.isEmpty()) return 'No criteria';

        Map<String, Schema.SObjectField> fields;
        Schema.SObjectType objectType = String.isBlank(objectApiName) ? null : Schema.getGlobalDescribe().get(objectApiName);
        if (objectType != null) fields = objectType.getDescribe().fields.getMap();

        String joiner = criteria.logic == 'all' ? ' and ' : ' or ';
        Boolean sameFieldEquals = true;
        for (AIConsoleDataStructure.Condition condition : criteria.conditions) {
            if (condition.field != criteria.conditions[0].field || condition.operator != 'equals') sameFieldEquals = false;
        }

        if (sameFieldEquals) {
            List<String> values = new List<String>();
            for (AIConsoleDataStructure.Condition condition : criteria.conditions) values.add(condition.value);
            return fieldLabel(fields, criteria.conditions[0].field) + ' is ' + String.join(values, joiner);
        }

        List<String> parts = new List<String>();
        for (AIConsoleDataStructure.Condition condition : criteria.conditions) {
            parts.add(fieldLabel(fields, condition.field) + ' ' + OPERATOR_LABELS.get(condition.operator) + ' ' + condition.value);
        }
        return String.join(parts, joiner);
    }

    private static String fieldLabel(Map<String, Schema.SObjectField> fields, String fieldName) {
        if (fields == null || !fields.containsKey(fieldName.toLowerCase())) return fieldName;
        String label = fields.get(fieldName.toLowerCase()).getDescribe().getLabel();
        return label.endsWith(' ID') ? label.removeEnd(' ID') : label;
    }

    // =============================================================
    // Ownership guards - every child Id must belong to the agent being edited
    // =============================================================

    private static AIPromptTemplate__c assertTemplate(Id agentId, Id templateId) {
        List<AIPromptTemplate__c> templates = [ SELECT Id FROM AIPromptTemplate__c WHERE Id = :templateId AND AIAgent__c = :agentId LIMIT 1 ];
        if (templates.isEmpty()) throw new AIConsoleDataStructure.AIConsoleException('That template doesn\'t belong to this agent.');
        return templates[0];
    }

    private static AIViolationRule__c assertRule(Id agentId, Id ruleId) {
        List<AIViolationRule__c> rules = [ SELECT Id FROM AIViolationRule__c WHERE Id = :ruleId AND Agent__c = :agentId LIMIT 1 ];
        if (rules.isEmpty()) throw new AIConsoleDataStructure.AIConsoleException('That rule doesn\'t belong to this agent.');
        return rules[0];
    }
}
