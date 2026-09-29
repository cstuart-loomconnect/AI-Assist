/*
Class Name: AIConsoleAgentService

=================================================================
=================================================================

Description: The AI Agents tab outside the wizard - the agent list (aiAgentList, one per Agents Sub
Navigation section: All Agents, Drafts, In test mode), the agent record (aiAgentRecord) with its
inline-editable Details card and related tabs, the row menu actions (clone, activate, deactivate,
delete) and the New Agent modal's choices (aiAgentNewModal).

Status wording is shared with Home: Active + Test Mode = "Test mode", Active = "Active", else "Inactive".
Setup wording: Complete, "Draft · step 2 of 7" while SetupStatus__c is Draft, "Step 7 of 7" while
In Progress.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-29     Chandler Stuart          Initial development
*/

public with sharing class AIConsoleAgentService {

    // =============================================================
    // Agent list
    // =============================================================

    public static AIConsoleDataStructure.AgentList getAgentList(String sectionDeveloperName, String searchText) {

        AINavTabSection__mdt section = AIConsoleNavService.getSection(sectionDeveloperName);

        List<String> conditions = new List<String>();
        Map<String, Object> binds = new Map<String, Object>();
        if (String.isNotBlank(section.FilterCriteria__c)) conditions.add('(' + section.FilterCriteria__c + ')');
        if (String.isNotBlank(searchText)) {
            binds.put('searchText', '%' + searchText.trim() + '%');
            conditions.add('(Name LIKE :searchText OR ObjectType__c LIKE :searchText OR AIModelConfiguration__r.Name LIKE :searchText)');
        }

        String query = 'SELECT Id, Name, ObjectType__c, AIModelConfiguration__r.Name, IsActive__c, IsTestModeEnabled__c, SetupStatus__c, SetupCurrentStep__c, SetupLastEdited__c, LastModifiedDate'
                     + ' FROM AIAgent__c' + (conditions.isEmpty() ? '' : ' WHERE ' + String.join(conditions, ' AND '))
                     + ' ORDER BY SetupLastEdited__c DESC NULLS LAST, LastModifiedDate DESC LIMIT 500';
        List<AIAgent__c> agents = Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);

        Set<Id> agentIds = new Map<Id, AIAgent__c>(agents).keySet();
        Map<Id, Integer> templatesByAgent = countByParent([ SELECT AIAgent__c parentId, COUNT(Id) total FROM AIPromptTemplate__c WHERE AIAgent__c IN :agentIds GROUP BY AIAgent__c ]);

        Datetime thirtyDaysAgo = System.now().addDays(-30);
        Map<Id, Integer> conversationsByAgent = countByParent([ SELECT AIAgent__c parentId, COUNT(Id) total FROM AIConversation__c WHERE AIAgent__c IN :agentIds AND CreatedDate >= :thirtyDaysAgo GROUP BY AIAgent__c ]);

        AIConsoleDataStructure.AgentList result = new AIConsoleDataStructure.AgentList();
        result.title = section.SectionLabel__c;
        result.totalCount = agents.size();

        for (AINavTabSection__mdt view : AIConsoleNavService.getSections(AIConsoleConstants.TAB_AGENTS)) {
            if (view.SectionType__c == AIConsoleConstants.SECTION_TYPE_SUB_NAVIGATION && view.ComponentAPIName__c == 'aiAgentList' && AIConsoleUtility.hasPermissionSet(view.RequiresPermissionSet__c)) {
                result.views.add(new AIConsoleDataStructure.Option(view.SectionLabel__c, view.DeveloperName));
            }
        }

        for (AIAgent__c agent : agents) {
            AIConsoleDataStructure.AgentRow row = new AIConsoleDataStructure.AgentRow();
            row.id = agent.Id;
            row.name = agent.Name;
            row.objectType = agent.ObjectType__c;
            row.modelName = agent.AIModelConfiguration__r?.Name;
            row.statusLabel = AIConsoleUtility.agentStatusLabel(agent);
            row.statusVariant = AIConsoleUtility.agentStatusVariant(agent);
            row.isActive = agent.IsActive__c == true;
            row.isTestMode = agent.IsTestModeEnabled__c == true;
            row.isSetupComplete = AIConsoleUtility.isSetupComplete(agent);
            row.resumeStep = AIConsoleUtility.setupStep(agent);
            row.setupLabel = setupLabel(agent);
            row.templateCount = templatesByAgent.containsKey(agent.Id) ? templatesByAgent.get(agent.Id) : 0;
            row.conversations30Days = conversationsByAgent.containsKey(agent.Id) ? conversationsByAgent.get(agent.Id) : 0;
            row.lastEdited = agent.SetupLastEdited__c != null ? agent.SetupLastEdited__c : agent.LastModifiedDate;
            result.rows.add(row);
        }

        return result;
    }

    public static String setupLabel(AIAgent__c agent) {
        if (AIConsoleUtility.isSetupComplete(agent)) return 'Complete';
        String stepText = 'step ' + AIConsoleUtility.setupStep(agent) + ' of ' + AIConsoleConstants.WIZARD_STEP_COUNT;
        return agent.SetupStatus__c == AIConsoleConstants.SETUP_STATUS_DRAFT || String.isBlank(agent.SetupStatus__c) ? 'Draft · ' + stepText : stepText.capitalize();
    }

    // =============================================================
    // Agent record
    // =============================================================

    public static AIConsoleDataStructure.AgentRecord getAgentRecord(Id agentId) {

        AIAgent__c agent = queryAgent(agentId);

        AIConsoleDataStructure.AgentRecord record = new AIConsoleDataStructure.AgentRecord();
        record.id = agent.Id;
        record.name = agent.Name;
        record.developerName = agent.DeveloperName__c;
        record.objectType = agent.ObjectType__c;
        record.modelId = agent.AIModelConfiguration__c;
        record.modelName = agent.AIModelConfiguration__r?.Name;
        record.ownerId = agent.OwnerId;
        record.ownerName = agent.Owner.Name;
        record.setupLastEdited = agent.SetupLastEdited__c != null ? agent.SetupLastEdited__c : agent.LastModifiedDate;
        record.statusLabel = AIConsoleUtility.agentStatusLabel(agent);
        record.statusVariant = AIConsoleUtility.agentStatusVariant(agent);
        record.isSetupComplete = AIConsoleUtility.isSetupComplete(agent);
        record.isActive = agent.IsActive__c == true;
        record.isTestMode = agent.IsTestModeEnabled__c == true;
        record.setupStep = AIConsoleUtility.setupStep(agent);
        record.details = buildDetailFields(agent);

        record.counts.put('templates', [ SELECT COUNT() FROM AIPromptTemplate__c WHERE AIAgent__c = :agentId ]);
        record.counts.put('dataSources', [ SELECT COUNT() FROM AIAgentDataSource__c WHERE AIAgent__c = :agentId ]);
        record.counts.put('workflowActions', [ SELECT COUNT() FROM AIAgentWorkflowAction__c WHERE AIAgent__c = :agentId ]);
        record.counts.put('guardrails', [ SELECT COUNT() FROM AIViolationRule__c WHERE Agent__c = :agentId ]);
        record.counts.put('conversations', [ SELECT COUNT() FROM AIConversation__c WHERE AIAgent__c = :agentId ]);
        record.counts.put('violations', [ SELECT COUNT() FROM AIViolation__c WHERE AIConversation__r.AIAgent__c = :agentId ]);

        record.stats = buildStats(agent);

        for (AIAgentDataSource__c link : [ SELECT AIDataSource__c, AIDataSource__r.SourceName__c, AIDataSource__r.DeveloperName__c, AIDataSource__r.Name, AIDataSource__r.SourceType__c, AIDataSource__r.BindingType__c, AIDataSource__r.TargetObject__c
                                           FROM AIAgentDataSource__c WHERE AIAgent__c = :agentId ORDER BY CreatedDate ASC LIMIT 10 ]) {
            AIConsoleDataStructure.RelatedLine line = new AIConsoleDataStructure.RelatedLine();
            line.id = link.AIDataSource__c;
            line.name = AIConsoleUtility.dataSourceName(link.AIDataSource__r);
            line.badge = link.AIDataSource__r.SourceType__c;
            if (isBoundElsewhere(link.AIDataSource__r.BindingType__c, link.AIDataSource__r.TargetObject__c, agent.ObjectType__c)) line.warning = 'Bound to ' + link.AIDataSource__r.TargetObject__c;
            record.dataSources.add(line);
        }

        for (AIViolationRule__c rule : [ SELECT Id, RuleName__c, BlockRequest__c FROM AIViolationRule__c WHERE Agent__c = :agentId ORDER BY BlockRequest__c DESC, RuleName__c ASC LIMIT 10 ]) {
            AIConsoleDataStructure.RelatedLine line = new AIConsoleDataStructure.RelatedLine();
            line.id = rule.Id;
            line.name = rule.RuleName__c;
            line.badge = rule.BlockRequest__c ? 'Blocks' : 'Logs only';
            line.badgeVariant = rule.BlockRequest__c ? 'err' : '';
            record.guardrails.add(line);
        }

        return record;
    }

    // A bound source only runs on its Target Object's record pages, so one bound to another object never runs for this agent.
    public static Boolean isBoundElsewhere(String bindingType, String targetObject, String agentObject) {
        return bindingType == AIConsoleConstants.BINDING_BOUND && String.isNotBlank(targetObject) && String.isNotBlank(agentObject) && !targetObject.equalsIgnoreCase(agentObject);
    }

    private static List<AIConsoleDataStructure.DetailField> buildDetailFields(AIAgent__c agent) {

        List<AIConsoleDataStructure.DetailField> fields = new List<AIConsoleDataStructure.DetailField>();

        fields.add(detailField('persona', 'Persona', agent.AIAgentPersona__c, agent.AIAgentPersona__c, 'textarea', true, null));
        fields.add(detailField('greeting', 'Greeting Message', agent.GreetingMessage__c, agent.GreetingMessage__c, 'textarea', true, null));
        fields.add(detailField('noMatch', 'No Match Behavior', noMatchLabel(agent.NoMatchBehavior__c), agent.NoMatchBehavior__c, 'select', false, noMatchOptions()));
        fields.add(detailField('loadTrigger', 'Conversation Load Trigger', agent.ConversationLoadTrigger__c, agent.ConversationLoadTrigger__c, 'select', false, picklistOptions(AIAgent__c.ConversationLoadTrigger__c)));
        fields.add(detailField('visibility', 'Conversation Visibility', agent.ConversationVisibility__c, agent.ConversationVisibility__c, 'select', false, picklistOptions(AIAgent__c.ConversationVisibility__c)));
        fields.add(detailField('idleTimeout', 'Idle Timeout Minutes', AIConsoleUtility.formatNumber(agent.IdleTimeoutMinutes__c), numberValue(agent.IdleTimeoutMinutes__c), 'number', false, null));
        fields.add(detailField('maxMessages', 'Max Messages Per Conversation', AIConsoleUtility.formatNumber(agent.MaxMessagesPerConversation__c), numberValue(agent.MaxMessagesPerConversation__c), 'number', false, null));

        String tokensDisplay = AIConsoleUtility.formatNumber(agent.MaxTokensPerConversation__c) + (String.isBlank(agent.TokenTrackingMethod__c) ? '' : ' · ' + agent.TokenTrackingMethod__c);
        fields.add(detailField('maxTokens', 'Max Tokens Per Conversation', tokensDisplay, numberValue(agent.MaxTokensPerConversation__c), 'number', false, null));

        String retentionDisplay = agent.ConversationRetentionDays__c == null ? '—' : AIConsoleUtility.formatNumber(agent.ConversationRetentionDays__c) + ' days' + (String.isBlank(agent.RetentionTrigger__c) ? '' : ' after ' + agent.RetentionTrigger__c);
        fields.add(detailField('retentionDays', 'Retention', retentionDisplay, numberValue(agent.ConversationRetentionDays__c), 'number', false, null));

        String resumeValue = (agent.AllowConversationResume__c ? 'allowed' : 'notAllowed') + '|' + (agent.SingleActiveConversationPer_Record__c ? 'on' : 'off');
        fields.add(detailField('resume', 'Resume · Single active per record', resumeLabel(resumeValue), resumeValue, 'select', false, resumeOptions()));

        return fields;
    }

    private static List<AIConsoleDataStructure.AgentStat> buildStats(AIAgent__c agent) {

        Datetime rangeStart = System.now().addDays(-14);
        List<AIConsoleDataStructure.AgentStat> stats = new List<AIConsoleDataStructure.AgentStat>();

        Integer conversations = [ SELECT COUNT() FROM AIConversation__c WHERE AIAgent__c = :agent.Id AND CreatedDate >= :rangeStart ];
        Integer people = [ SELECT OwnerId FROM AIConversation__c WHERE AIAgent__c = :agent.Id AND CreatedDate >= :rangeStart GROUP BY OwnerId ].size();
        String who = agent.IsTestModeEnabled__c == true ? (people == 1 ? 'tester' : 'testers') : (people == 1 ? 'user' : 'users');
        stats.add(new AIConsoleDataStructure.AgentStat(AIConsoleUtility.formatNumber(conversations), (conversations == 1 ? 'conversation, ' : 'conversations, ') + people + ' ' + who));

        Decimal tokens = AITokenUsageService.getAgentUsage(agent.Id, System.today().addDays(-14), System.today());
        stats.add(new AIConsoleDataStructure.AgentStat(AIConsoleUtility.compactNumber(tokens), 'tokens used'));

        Integer helpful = 0;
        Integer ratings = 0;
        for (AggregateResult row : [ SELECT Rating__c rating, COUNT(Id) total FROM AIFeedback__c WHERE AIConversation__r.AIAgent__c = :agent.Id AND CreatedDate >= :rangeStart GROUP BY Rating__c ]) {
            ratings += (Integer) row.get('total');
            if ((String) row.get('rating') == AIConsoleConstants.RATING_HELPFUL) helpful = (Integer) row.get('total');
        }
        stats.add(ratings == 0 ? new AIConsoleDataStructure.AgentStat('—', 'no ratings yet') : new AIConsoleDataStructure.AgentStat(AIConsoleUtility.percent(helpful, ratings) + '%', 'rated helpful, of ' + ratings));

        Integer violations = [ SELECT COUNT() FROM AIViolation__c WHERE AIConversation__r.AIAgent__c = :agent.Id AND CreatedDate >= :rangeStart ];
        Integer blocked = [ SELECT COUNT() FROM AIViolation__c WHERE AIConversation__r.AIAgent__c = :agent.Id AND CreatedDate >= :rangeStart AND RequestBlocked__c = true ];
        String violationLabel;
        if (violations == 0) violationLabel = 'violations';
        else if (blocked == violations) violationLabel = (violations == 1 ? 'violation' : 'violations') + ', blocked';
        else if (blocked > 0) violationLabel = 'violations, ' + blocked + ' blocked';
        else violationLabel = (violations == 1 ? 'violation' : 'violations') + ', logged';
        stats.add(new AIConsoleDataStructure.AgentStat(String.valueOf(violations), violationLabel));

        return stats;
    }

    // Saves one field from the Details card's pencil. key is a DetailField.key.
    public static AIConsoleDataStructure.AgentRecord updateAgentField(Id agentId, String key, String value) {

        AIAgent__c agent = new AIAgent__c(Id = queryAgent(agentId).Id, SetupLastEdited__c = System.now());
        String trimmed = value == null ? null : value.trim();

        switch on key {
            when 'persona' { agent.AIAgentPersona__c = trimmed; }
            when 'greeting' { agent.GreetingMessage__c = trimmed; }
            when 'noMatch' { agent.NoMatchBehavior__c = trimmed; }
            when 'loadTrigger' { agent.ConversationLoadTrigger__c = trimmed; }
            when 'visibility' { agent.ConversationVisibility__c = trimmed; }
            when 'idleTimeout' { agent.IdleTimeoutMinutes__c = toNumber(trimmed, 'Idle Timeout Minutes'); }
            when 'maxMessages' { agent.MaxMessagesPerConversation__c = toNumber(trimmed, 'Max Messages Per Conversation'); }
            when 'maxTokens' { agent.MaxTokensPerConversation__c = toNumber(trimmed, 'Max Tokens Per Conversation'); }
            when 'retentionDays' { agent.ConversationRetentionDays__c = toNumber(trimmed, 'Retention'); }
            when 'resume' {
                List<String> parts = (trimmed == null ? 'notAllowed|off' : trimmed).split('\\|');
                agent.AllowConversationResume__c = parts[0] == 'allowed';
                agent.SingleActiveConversationPer_Record__c = parts.size() > 1 && parts[1] == 'on';
            }
            when else { throw new AIConsoleDataStructure.AIConsoleException('That field can\'t be edited here.'); }
        }

        update agent;
        return getAgentRecord(agentId);
    }

    // One of the record's related tabs, as a table.
    public static AIConsoleDataStructure.ListResult getAgentRelated(Id agentId, String relatedKey) {

        AIAgent__c agent = queryAgent(agentId);
        AIConsoleDataStructure.ListResult result = new AIConsoleDataStructure.ListResult();
        result.showHeader = false;

        switch on relatedKey {
            when 'templates' {
                result.columns = columns(new List<String>{ 'name:Template Name', 'criteria:When to use', 'length:Max Response Length', 'status:Status' });
                for (AIPromptTemplate__c template : [ SELECT Id, Name, ActivationCriteria__c, MaxResponseLength__c, IsActive__c FROM AIPromptTemplate__c WHERE AIAgent__c = :agentId ORDER BY Name ]) {
                    AIConsoleDataStructure.ListRow row = newRow(template.Id);
                    row.cells.add(AIConsoleListService.linkCell('name', template.Name, true, wizardTarget(agentId, 2)));
                    row.cells.add(AIConsoleListService.textCell('criteria', AIConsoleWizardService.criteriaSummary(AIConsoleWizardService.parseCriteria(template.ActivationCriteria__c), agent.ObjectType__c)));
                    row.cells.add(AIConsoleListService.textCell('length', template.MaxResponseLength__c == null ? '—' : AIConsoleUtility.formatNumber(template.MaxResponseLength__c) + ' words'));
                    row.cells.add(AIConsoleListService.badgeCell('status', template.IsActive__c ? 'Active' : 'Inactive', template.IsActive__c ? 'ok' : ''));
                    result.rows.add(row);
                }
            }
            when 'dataSources' {
                result.columns = columns(new List<String>{ 'name:Data Source', 'type:Type', 'binding:Binding', 'target:Target Object', 'status:Active' });
                for (AIAgentDataSource__c link : [ SELECT Id, IsActive__c, AIDataSource__r.SourceName__c, AIDataSource__r.DeveloperName__c, AIDataSource__r.Name, AIDataSource__r.SourceType__c, AIDataSource__r.BindingType__c, AIDataSource__r.TargetObject__c FROM AIAgentDataSource__c WHERE AIAgent__c = :agentId ORDER BY CreatedDate ]) {
                    AIConsoleDataStructure.ListRow row = newRow(link.Id);
                    row.isWarning = isBoundElsewhere(link.AIDataSource__r.BindingType__c, link.AIDataSource__r.TargetObject__c, agent.ObjectType__c);
                    row.cells.add(AIConsoleListService.linkCell('name', AIConsoleUtility.dataSourceName(link.AIDataSource__r), true, wizardTarget(agentId, 3)));
                    row.cells.add(AIConsoleListService.badgeCell('type', link.AIDataSource__r.SourceType__c, ''));
                    row.cells.add(AIConsoleListService.textCell('binding', link.AIDataSource__r.BindingType__c));
                    row.cells.add(AIConsoleListService.textCell('target', link.AIDataSource__r.TargetObject__c));
                    row.cells.add(AIConsoleListService.badgeCell('status', link.IsActive__c ? 'Active' : 'Paused', link.IsActive__c ? 'ok' : ''));
                    result.rows.add(row);
                }
            }
            when 'workflowActions' {
                result.columns = columns(new List<String>{ 'name:Workflow Action', 'type:Type', 'execution:Execution', 'confirmation:Requires Confirmation', 'status:Active' });
                for (AIAgentWorkflowAction__c link : [ SELECT Id, IsActive__c, AIWorkflowAction__r.ActionName__c, AIWorkflowAction__r.DeveloperName__c, AIWorkflowAction__r.Name, AIWorkflowAction__r.ActionType__c, AIWorkflowAction__r.ExecutionType__c, AIWorkflowAction__r.RequiresConfirmation__c FROM AIAgentWorkflowAction__c WHERE AIAgent__c = :agentId ORDER BY CreatedDate ]) {
                    AIConsoleDataStructure.ListRow row = newRow(link.Id);
                    row.cells.add(AIConsoleListService.linkCell('name', AIConsoleUtility.workflowActionName(link.AIWorkflowAction__r), true, wizardTarget(agentId, 4)));
                    row.cells.add(AIConsoleListService.badgeCell('type', link.AIWorkflowAction__r.ActionType__c, ''));
                    row.cells.add(AIConsoleListService.badgeCell('execution', link.AIWorkflowAction__r.ExecutionType__c, AIConsoleListService.executionVariant(link.AIWorkflowAction__r.ExecutionType__c)));
                    row.cells.add(AIConsoleListService.textCell('confirmation', link.AIWorkflowAction__r.RequiresConfirmation__c ? 'Yes' : 'No'));
                    row.cells.add(AIConsoleListService.badgeCell('status', link.IsActive__c ? 'Active' : 'Paused', link.IsActive__c ? 'ok' : ''));
                    result.rows.add(row);
                }
            }
            when 'guardrails' {
                result.columns = columns(new List<String>{ 'name:Rule Name', 'detection:Detection', 'type:Violation Type Produced', 'fires:When it fires', 'count:Times fired' });
                for (AIViolationRule__c rule : [ SELECT Id, RuleName__c, DetectionMethod__c, ViolationTypeProduced__c, BlockRequest__c, TriggerCount__c, Active__c FROM AIViolationRule__c WHERE Agent__c = :agentId ORDER BY RuleName__c ]) {
                    AIConsoleDataStructure.ListRow row = newRow(rule.Id);
                    row.isMuted = rule.Active__c != true;
                    row.cells.add(AIConsoleListService.linkCell('name', rule.RuleName__c, true, wizardTarget(agentId, 5)));
                    row.cells.add(AIConsoleListService.textCell('detection', picklistLabel(AIViolationRule__c.DetectionMethod__c, rule.DetectionMethod__c)));
                    row.cells.add(AIConsoleListService.textCell('type', picklistLabel(AIViolationRule__c.ViolationTypeProduced__c, rule.ViolationTypeProduced__c)));
                    row.cells.add(AIConsoleListService.badgeCell('fires', rule.BlockRequest__c ? 'Blocks' : 'Logs only', rule.BlockRequest__c ? 'err' : ''));
                    row.cells.add(AIConsoleListService.textCell('count', AIConsoleUtility.formatNumber(rule.TriggerCount__c)));
                    result.rows.add(row);
                }
            }
            when 'conversations' {
                result.columns = columns(new List<String>{ 'name:Conversation', 'user:User', 'status:Status', 'messages:Messages', 'started:Started' });
                for (AIConversation__c conversation : [ SELECT Id, Name, Owner.Name, Status__c, MessageCount__c, CreatedDate FROM AIConversation__c WHERE AIAgent__c = :agentId ORDER BY CreatedDate DESC LIMIT 50 ]) {
                    AIConsoleDataStructure.ListRow row = newRow(conversation.Id);
                    row.cells.add(AIConsoleListService.linkCell('name', conversation.Name, true, new AIConsoleDataStructure.NavTarget(AIConsoleConstants.TAB_ACTIVITY, AIConsoleConstants.SECTION_ACTIVITY_CONVERSATIONS, AIConsoleConstants.VIEW_RECORD, conversation.Id)));
                    row.cells.add(AIConsoleListService.textCell('user', conversation.Owner.Name));
                    row.cells.add(AIConsoleListService.badgeCell('status', conversation.Status__c, conversation.Status__c == AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE ? 'ok' : ''));
                    row.cells.add(AIConsoleListService.textCell('messages', AIConsoleUtility.formatNumber(conversation.MessageCount__c)));
                    row.cells.add(AIConsoleListService.textCell('started', AIConsoleUtility.shortDateTimeLabel(conversation.CreatedDate)));
                    result.rows.add(row);
                }
            }
            when 'violations' {
                result.columns = columns(new List<String>{ 'severity:Severity', 'type:Violation Type', 'user:User', 'request:Request', 'when:When' });
                for (AIViolation__c violation : [ SELECT Id, Severity__c, ViolationType__c, User__r.Name, RequestBlocked__c, CreatedDate FROM AIViolation__c WHERE AIConversation__r.AIAgent__c = :agentId ORDER BY CreatedDate DESC LIMIT 50 ]) {
                    AIConsoleDataStructure.ListRow row = newRow(violation.Id);
                    row.cells.add(AIConsoleListService.badgeCell('severity', violation.Severity__c, AIConsoleListService.severityVariant(violation.Severity__c)));
                    row.cells.add(AIConsoleListService.linkCell('type', violation.ViolationType__c, false, new AIConsoleDataStructure.NavTarget(AIConsoleConstants.TAB_ACTIVITY, AIConsoleConstants.SECTION_ACTIVITY_VIOLATIONS, AIConsoleConstants.VIEW_RECORD, violation.Id)));
                    row.cells.add(AIConsoleListService.textCell('user', violation.User__r?.Name));
                    row.cells.add(AIConsoleListService.textCell('request', violation.RequestBlocked__c ? 'Blocked' : 'Logged'));
                    row.cells.add(AIConsoleListService.textCell('when', AIConsoleUtility.relativeLabel(violation.CreatedDate)));
                    result.rows.add(row);
                }
            }
            when else { throw new AIConsoleDataStructure.AIConsoleException('Unknown related list.'); }
        }

        result.totalCount = result.rows.size();
        return result;
    }

    // =============================================================
    // Row menu / header actions
    // =============================================================

    // mode: activate (Active, Test Mode off) | test (Active, Test Mode on) | deactivate
    public static void setAgentStatus(Id agentId, String mode) {

        AIAgent__c agent = new AIAgent__c(Id = queryAgent(agentId).Id, SetupLastEdited__c = System.now());

        switch on mode {
            when 'activate' { agent.IsActive__c = true; agent.IsTestModeEnabled__c = false; }
            when 'test' { agent.IsActive__c = true; agent.IsTestModeEnabled__c = true; }
            when 'deactivate' { agent.IsActive__c = false; agent.IsTestModeEnabled__c = false; }
            when else { throw new AIConsoleDataStructure.AIConsoleException('Unknown status.'); }
        }

        update agent;
    }

    public static void deleteAgent(Id agentId) {

        AIAgent__c agent = queryAgent(agentId);
        if (agent.IsActive__c == true) throw new AIConsoleDataStructure.AIConsoleException('Deactivate ' + agent.Name + ' before deleting it.');

        Integer conversations = [ SELECT COUNT() FROM AIConversation__c WHERE AIAgent__c = :agentId ];
        if (conversations > 0) throw new AIConsoleDataStructure.AIConsoleException(agent.Name + ' has ' + conversations + ' conversations, so it can\'t be deleted. Deactivate it instead.');

        delete [ SELECT Id FROM AIPromptTemplate__c WHERE AIAgent__c = :agentId ];
        delete new AIAgent__c(Id = agentId); // Junctions and violation rules are master-detail.
    }

    // =============================================================
    // New Agent modal
    // =============================================================

    public static AIConsoleDataStructure.NewAgentOptions getNewAgentOptions() {

        AIConsoleDataStructure.NewAgentOptions options = new AIConsoleDataStructure.NewAgentOptions();

        List<AIAgent__c> sources = [ SELECT Id, Name FROM AIAgent__c WHERE SetupStatus__c = :AIConsoleConstants.SETUP_STATUS_COMPLETE ORDER BY Name LIMIT 200 ];
        Set<Id> sourceIds = new Map<Id, AIAgent__c>(sources).keySet();

        Map<Id, Integer> templates = countByParent([ SELECT AIAgent__c parentId, COUNT(Id) total FROM AIPromptTemplate__c WHERE AIAgent__c IN :sourceIds GROUP BY AIAgent__c ]);
        Map<Id, Integer> dataSources = countByParent([ SELECT AIAgent__c parentId, COUNT(Id) total FROM AIAgentDataSource__c WHERE AIAgent__c IN :sourceIds GROUP BY AIAgent__c ]);
        Map<Id, Integer> actions = countByParent([ SELECT AIAgent__c parentId, COUNT(Id) total FROM AIAgentWorkflowAction__c WHERE AIAgent__c IN :sourceIds GROUP BY AIAgent__c ]);
        Map<Id, Integer> rules = countByParent([ SELECT Agent__c parentId, COUNT(Id) total FROM AIViolationRule__c WHERE Agent__c IN :sourceIds GROUP BY Agent__c ]);

        for (AIAgent__c source : sources) {
            AIConsoleDataStructure.CloneSource option = new AIConsoleDataStructure.CloneSource();
            option.id = source.Id;
            option.name = source.Name;
            option.templates = templates.containsKey(source.Id) ? templates.get(source.Id) : 0;
            option.dataSources = dataSources.containsKey(source.Id) ? dataSources.get(source.Id) : 0;
            option.workflowActions = actions.containsKey(source.Id) ? actions.get(source.Id) : 0;
            option.violationRules = rules.containsKey(source.Id) ? rules.get(source.Id) : 0;
            options.cloneSources.add(option);
        }

        for (AIAgent__c draft : [ SELECT Id, Name, SetupCurrentStep__c, SetupLastEdited__c, LastModifiedDate FROM AIAgent__c WHERE SetupStatus__c != :AIConsoleConstants.SETUP_STATUS_COMPLETE ORDER BY SetupLastEdited__c DESC NULLS LAST LIMIT 20 ]) {
            AIConsoleDataStructure.DraftAgent option = new AIConsoleDataStructure.DraftAgent();
            option.id = draft.Id;
            option.name = draft.Name;
            option.step = AIConsoleUtility.setupStep(draft);
            option.lastEdited = draft.SetupLastEdited__c != null ? draft.SetupLastEdited__c : draft.LastModifiedDate;
            options.drafts.add(option);
        }

        return options;
    }

    // Copies the agent's settings - the copy starts inactive, in Draft, on step 1. Library records (Data Sources, Workflow Actions) are shared, so only the assignments are copied.
    public static Id cloneAgent(AIConsoleDataStructure.CloneRequest request) {

        if (request == null || request.sourceId == null) throw new AIConsoleDataStructure.AIConsoleException('Pick an agent to clone.');
        if (String.isBlank(request.name)) throw new AIConsoleDataStructure.AIConsoleException('Give the new agent a name.');

        AIAgent__c source = queryAgent(request.sourceId);

        AIAgent__c copy = source.clone(false, true, false, false);
        copy.Name = request.name.trim().left(80);
        copy.DeveloperName__c = null;
        copy.PublicId__c = null;
        copy.IsActive__c = false;
        copy.IsTestModeEnabled__c = false;
        copy.SetupStatus__c = AIConsoleConstants.SETUP_STATUS_DRAFT;
        copy.SetupCurrentStep__c = 1;
        copy.SetupLastEdited__c = System.now();
        copy.OwnerId = UserInfo.getUserId();
        insert copy;

        if (request.copyTemplates == true) {
            List<AIPromptTemplate__c> templates = new List<AIPromptTemplate__c>();
            for (AIPromptTemplate__c template : [ SELECT Name, AIExclusionRules__c, AIPrompt__c, AISystemContext__c, AITone__c, Description__c, IsActive__c, MaxResponseLength__c, TriggerKeywords__c, ActivationCriteria__c
                                                  FROM AIPromptTemplate__c WHERE AIAgent__c = :source.Id ]) {
                AIPromptTemplate__c templateCopy = template.clone(false, true, false, false);
                templateCopy.AIAgent__c = copy.Id;
                templates.add(templateCopy);
            }
            insert templates;
        }

        if (request.copyDataSources == true) {
            List<AIAgentDataSource__c> links = new List<AIAgentDataSource__c>();
            for (AIAgentDataSource__c link : [ SELECT AIDataSource__c, IsActive__c FROM AIAgentDataSource__c WHERE AIAgent__c = :source.Id ]) {
                links.add(new AIAgentDataSource__c(AIAgent__c = copy.Id, AIDataSource__c = link.AIDataSource__c, IsActive__c = link.IsActive__c));
            }
            insert links;
        }

        if (request.copyWorkflowActions == true) {
            List<AIAgentWorkflowAction__c> links = new List<AIAgentWorkflowAction__c>();
            for (AIAgentWorkflowAction__c link : [ SELECT AIWorkflowAction__c, IsActive__c FROM AIAgentWorkflowAction__c WHERE AIAgent__c = :source.Id ]) {
                links.add(new AIAgentWorkflowAction__c(AIAgent__c = copy.Id, AIWorkflowAction__c = link.AIWorkflowAction__c, IsActive__c = link.IsActive__c));
            }
            insert links;
        }

        if (request.copyViolationRules == true) {
            List<AIViolationRule__c> rules = new List<AIViolationRule__c>();
            for (AIViolationRule__c rule : [ SELECT RuleName__c, AIDetectionInstruction__c, Active__c, BlockRequest__c, DetectionMethod__c, SignalTag__c, ViolationTypeProduced__c
                                             FROM AIViolationRule__c WHERE Agent__c = :source.Id ]) {
                AIViolationRule__c ruleCopy = rule.clone(false, true, false, false);
                ruleCopy.Agent__c = copy.Id;
                rules.add(ruleCopy);
            }
            insert rules;
        }

        return copy.Id;
    }

    // =============================================================
    // Helpers
    // =============================================================

    public static AIAgent__c queryAgent(Id agentId) {

        if (agentId == null) throw new AIConsoleDataStructure.AIConsoleException('No agent was given.');

        List<AIAgent__c> agents = [ SELECT Id, Name, DeveloperName__c, PublicId__c, ObjectType__c, Description__c, AIAgentPersona__c, GreetingMessage__c, AIFallbackMessage__c,
                                           AIModelConfiguration__c, AIModelConfiguration__r.Name, MaxToolCallingIterations__c, NoMatchBehavior__c, ConversationLoadTrigger__c,
                                           ConversationVisibility__c, SingleActiveConversationPer_Record__c, AllowConversationResume__c, IdleTimeoutMinutes__c,
                                           MaxMessagesPerConversation__c, MaxTokensPerConversation__c, TokenTrackingMethod__c, ConversationRetentionDays__c, RetentionTrigger__c,
                                           IsActive__c, IsTestModeEnabled__c, SetupStatus__c, SetupCurrentStep__c, SetupLastEdited__c, OwnerId, Owner.Name, LastModifiedDate
                                    FROM AIAgent__c WHERE Id = :agentId LIMIT 1 ];

        if (agents.isEmpty()) throw new AIConsoleDataStructure.AIConsoleException('That agent no longer exists.');
        return agents[0];
    }

    public static List<AIConsoleDataStructure.Option> picklistOptions(Schema.SObjectField field) {
        List<AIConsoleDataStructure.Option> options = new List<AIConsoleDataStructure.Option>();
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.isActive()) options.add(new AIConsoleDataStructure.Option(entry.getLabel(), entry.getValue()));
        }
        return options;
    }

    public static String picklistLabel(Schema.SObjectField field, String value) {
        if (String.isBlank(value)) return '—';
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.getValue() == value) return entry.getLabel();
        }
        return value;
    }

    public static String noMatchLabel(String value) {
        if (value == AIConsoleConstants.NO_MATCH_CLOSEST) return 'Closest match';
        if (value == AIConsoleConstants.NO_MATCH_FALLBACK) return 'Fallback message';
        return '—';
    }

    private static List<AIConsoleDataStructure.Option> noMatchOptions() {
        return new List<AIConsoleDataStructure.Option>{
            new AIConsoleDataStructure.Option('Closest match', AIConsoleConstants.NO_MATCH_CLOSEST),
            new AIConsoleDataStructure.Option('Fallback message', AIConsoleConstants.NO_MATCH_FALLBACK)
        };
    }

    private static List<AIConsoleDataStructure.Option> resumeOptions() {
        List<AIConsoleDataStructure.Option> options = new List<AIConsoleDataStructure.Option>();
        for (String value : new List<String>{ 'allowed|on', 'allowed|off', 'notAllowed|on', 'notAllowed|off' }) {
            options.add(new AIConsoleDataStructure.Option(resumeLabel(value), value));
        }
        return options;
    }

    private static String resumeLabel(String value) {
        List<String> parts = value.split('\\|');
        return (parts[0] == 'allowed' ? 'Allowed' : 'Not allowed') + ' · ' + (parts[1] == 'on' ? 'On' : 'Off');
    }

    private static AIConsoleDataStructure.DetailField detailField(String key, String label, String displayValue, String value, String editor, Boolean fullWidth, List<AIConsoleDataStructure.Option> options) {
        AIConsoleDataStructure.DetailField field = new AIConsoleDataStructure.DetailField();
        field.key = key;
        field.label = label;
        field.displayValue = String.isBlank(displayValue) ? '—' : displayValue;
        field.value = value;
        field.editor = editor;
        field.fullWidth = fullWidth;
        if (options != null) field.options = options;
        return field;
    }

    private static String numberValue(Decimal value) {
        return value == null ? null : String.valueOf(value.stripTrailingZeros().toPlainString());
    }

    public static Decimal toNumber(String value, String label) {
        if (String.isBlank(value)) return null;
        try {
            Decimal parsed = Decimal.valueOf(value.replace(',', '').trim());
            if (parsed < 0) throw new AIConsoleDataStructure.AIConsoleException(label + ' can\'t be negative.');
            return parsed;
        } catch (TypeException ex) {
            throw new AIConsoleDataStructure.AIConsoleException(label + ' must be a number.');
        }
    }

    private static Map<Id, Integer> countByParent(List<AggregateResult> results) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        for (AggregateResult row : results) counts.put((Id) row.get('parentId'), (Integer) row.get('total'));
        return counts;
    }

    private static AIConsoleDataStructure.ListRow newRow(Id recordId) {
        AIConsoleDataStructure.ListRow row = new AIConsoleDataStructure.ListRow();
        row.id = recordId;
        return row;
    }

    private static List<AIConsoleDataStructure.ListColumn> columns(List<String> keyLabels) {
        List<AIConsoleDataStructure.ListColumn> result = new List<AIConsoleDataStructure.ListColumn>();
        for (String keyLabel : keyLabels) result.add(new AIConsoleDataStructure.ListColumn(keyLabel.substringBefore(':'), keyLabel.substringAfter(':')));
        return result;
    }

    private static AIConsoleDataStructure.NavTarget wizardTarget(Id agentId, Integer step) {
        AIConsoleDataStructure.NavTarget target = new AIConsoleDataStructure.NavTarget(AIConsoleConstants.TAB_AGENT_WIZARD, null, null, agentId);
        target.step = step;
        return target;
    }
}