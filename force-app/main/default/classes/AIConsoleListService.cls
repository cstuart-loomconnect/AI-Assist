/*
Class Name: AIConsoleListService

=================================================================
=================================================================

Description: Every list aiRecordList shows. aiRecordList is one generic component - it takes the
section's AINavTabSection__mdt row (Related Object API Name, Filter Criteria, Max Records Shown) and
renders whatever this service hands back: header, filters, columns, rows and which detail panel opens
beside a row. A new list is a metadata record plus a builder here, not a new component.

Builders, by Related Object API Name:
AIAgent__c             - Home › Agent health (Related List)
AIViolation__c         - Home › Recent violations (Related List) / Activity › Violations
AIModelConfiguration__c - Library › Model Configurations
AIDataSource__c        - Library › Data Sources
AIWorkflowAction__c    - Library › Workflow Actions
AIConversation__c      - Activity › Conversations
AIPlatformLog__c       - Activity › Error Log
anything else          - a plain Name / Created / Last Modified list

The section's Filter Criteria is ANDed onto every query; user-picked filters are bound variables, never
concatenated. Criteria are protected, developer-controlled metadata, so they're trusted as written.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-29     Chandler Stuart          Initial development
*/

public with sharing class AIConsoleListService {

    private static final Integer AGENT_HEALTH_DAYS = 14;

    public static AIConsoleDataStructure.ListResult getList(String sectionDeveloperName, String filtersJson, Integer offset) {

        AINavTabSection__mdt section = AIConsoleNavService.getSection(sectionDeveloperName);
        if (String.isBlank(section.RelatedObjectAPIName__c)) throw new AIConsoleDataStructure.AIConsoleException('This section has no Related Object API Name set.');

        Map<String, Object> filters = String.isBlank(filtersJson) ? new Map<String, Object>() : (Map<String, Object>) JSON.deserializeUntyped(filtersJson);
        ListContext context = new ListContext(section, filters, offset);

        String objectName = section.RelatedObjectAPIName__c.trim();
        String bareName = objectName.contains('__') && objectName.countMatches('__') > 1 ? objectName.substringAfter('__') : objectName;
        Boolean isRelatedList = section.SectionType__c == AIConsoleConstants.SECTION_TYPE_RELATED_LIST;

        AIConsoleDataStructure.ListResult result;
        switch on bareName {
            when 'AIAgent__c' { result = buildAgentHealth(context); }
            when 'AIViolation__c' { result = isRelatedList ? buildRecentViolations(context) : buildViolations(context); }
            when 'AIModelConfiguration__c' { result = buildModels(context); }
            when 'AIDataSource__c' { result = buildDataSources(context); }
            when 'AIWorkflowAction__c' { result = buildWorkflowActions(context); }
            when 'AIConversation__c' { result = buildConversations(context); }
            when 'AIPlatformLog__c' { result = buildErrorLog(context); }
            when else { result = buildGeneric(context, objectName); }
        }

        result.objectApiName = objectName;
        if (String.isBlank(result.icon)) result.icon = section.SectionIcon__c;
        return result;
    }

    // =============================================================
    // Home › Agent health
    // =============================================================

    private static AIConsoleDataStructure.ListResult buildAgentHealth(ListContext context) {

        AIConsoleDataStructure.ListResult result = newResult('Agent health', null, null);
        result.viewAll = new AIConsoleDataStructure.NavTarget(AIConsoleConstants.TAB_AGENTS, AIConsoleConstants.SECTION_AGENTS_ALL, null, null);
        result.columns = new List<AIConsoleDataStructure.ListColumn>{
            new AIConsoleDataStructure.ListColumn('name', 'Agent'),
            new AIConsoleDataStructure.ListColumn('object', 'Object'),
            new AIConsoleDataStructure.ListColumn('conversations', 'Conversations', true),
            new AIConsoleDataStructure.ListColumn('helpful', 'Helpful', true),
            new AIConsoleDataStructure.ListColumn('errors', 'Errors', true),
            new AIConsoleDataStructure.ListColumn('tokens', 'Avg tokens', true),
            new AIConsoleDataStructure.ListColumn('status', 'Status')
        };

        String query = 'SELECT Id, Name, ObjectType__c, IsActive__c, IsTestModeEnabled__c FROM AIAgent__c' + context.whereClause(null) + ' ORDER BY Name ASC LIMIT ' + context.rowLimit(5);
        List<AIAgent__c> agents = Database.queryWithBinds(query, context.binds, AccessLevel.USER_MODE);
        result.totalCount = agents.size();

        Set<Id> agentIds = new Map<Id, AIAgent__c>(agents).keySet();
        Datetime rangeStart = System.now().addDays(-AGENT_HEALTH_DAYS);

        Map<Id, Integer> conversationsByAgent = new Map<Id, Integer>();
        Map<Id, Decimal> avgTokensByAgent = new Map<Id, Decimal>();
        for (AggregateResult row : [ SELECT AIAgent__c agentId, COUNT(Id) total, AVG(ConversationTokenUsage__c) avgTokens FROM AIConversation__c WHERE AIAgent__c IN :agentIds AND CreatedDate >= :rangeStart GROUP BY AIAgent__c ]) {
            conversationsByAgent.put((Id) row.get('agentId'), (Integer) row.get('total'));
            avgTokensByAgent.put((Id) row.get('agentId'), (Decimal) row.get('avgTokens'));
        }

        Map<Id, Integer> helpfulByAgent = new Map<Id, Integer>();
        Map<Id, Integer> ratingsByAgent = new Map<Id, Integer>();
        for (AggregateResult row : [ SELECT AIConversation__r.AIAgent__c agentId, Rating__c rating, COUNT(Id) total FROM AIFeedback__c WHERE AIConversation__r.AIAgent__c IN :agentIds AND CreatedDate >= :rangeStart GROUP BY AIConversation__r.AIAgent__c, Rating__c ]) {
            Id agentId = (Id) row.get('agentId');
            Integer total = (Integer) row.get('total');
            ratingsByAgent.put(agentId, (ratingsByAgent.containsKey(agentId) ? ratingsByAgent.get(agentId) : 0) + total);
            if ((String) row.get('rating') == AIConsoleConstants.RATING_HELPFUL) helpfulByAgent.put(agentId, total);
        }

        Map<Id, Integer> errorsByAgent = new Map<Id, Integer>();
        for (AggregateResult row : [ SELECT AIConversationMessage__r.AIConversation__r.AIAgent__c agentId, COUNT(Id) total FROM AIExecutionStep__c
                                     WHERE Status__c = :AIAssistApplicationConstants.EXECUTION_STEP_STATUS_FAILED AND AIConversationMessage__r.AIConversation__r.AIAgent__c IN :agentIds AND CreatedDate >= :rangeStart
                                     GROUP BY AIConversationMessage__r.AIConversation__r.AIAgent__c ]) {
            errorsByAgent.put((Id) row.get('agentId'), (Integer) row.get('total'));
        }

        for (AIAgent__c agent : agents) {

            Integer conversations = conversationsByAgent.containsKey(agent.Id) ? conversationsByAgent.get(agent.Id) : 0;
            Integer errors = errorsByAgent.containsKey(agent.Id) ? errorsByAgent.get(agent.Id) : 0;
            Integer ratings = ratingsByAgent.get(agent.Id);
            Integer helpful = helpfulByAgent.containsKey(agent.Id) ? helpfulByAgent.get(agent.Id) : 0;

            AIConsoleDataStructure.ListRow row = newRow(agent.Id);
            row.cells.add(linkCell('name', agent.Name, false, new AIConsoleDataStructure.NavTarget(AIConsoleConstants.TAB_AGENTS, AIConsoleConstants.SECTION_AGENTS_ALL, AIConsoleConstants.VIEW_RECORD, agent.Id)));
            row.cells.add(textCell('object', agent.ObjectType__c));
            row.cells.add(rightCell('conversations', AIConsoleUtility.formatNumber(conversations)));
            row.cells.add(rightCell('helpful', ratings == null ? '—' : AIConsoleUtility.percent(helpful, ratings) + '%'));

            // Flagged when more than 2% of the agent's conversations hit a failed step.
            AIConsoleDataStructure.ListCell errorCell = rightCell('errors', String.valueOf(errors));
            if (errors > 0 && conversations > 0 && errors * 100 > conversations * 2) errorCell.variant = 'error';
            row.cells.add(errorCell);

            row.cells.add(rightCell('tokens', AIConsoleUtility.formatNumber(avgTokensByAgent.get(agent.Id))));
            row.cells.add(badgeCell('status', AIConsoleUtility.agentStatusLabel(agent), AIConsoleUtility.agentStatusVariant(agent)));
            result.rows.add(row);
        }

        return result;
    }

    // =============================================================
    // Home › Recent violations
    // =============================================================

    private static AIConsoleDataStructure.ListResult buildRecentViolations(ListContext context) {

        AIConsoleDataStructure.ListResult result = newResult('Recent violations', null, null);
        result.viewAll = new AIConsoleDataStructure.NavTarget(AIConsoleConstants.TAB_ACTIVITY, AIConsoleConstants.SECTION_ACTIVITY_VIOLATIONS, null, null);
        result.columns = new List<AIConsoleDataStructure.ListColumn>{ hiddenColumn('severity', 'Severity'), hiddenColumn('what', 'Violation') };

        String query = 'SELECT Id, Severity__c, ViolationType__c, RequestBlocked__c, CreatedDate, AIViolationRule__r.RuleName__c FROM AIViolation__c' + context.whereClause(null) + ' ORDER BY CreatedDate DESC LIMIT ' + context.rowLimit(5);

        for (AIViolation__c violation : (List<AIViolation__c>) Database.queryWithBinds(query, context.binds, AccessLevel.USER_MODE)) {

            AIConsoleDataStructure.ListRow row = newRow(violation.Id);
            row.cells.add(badgeCell('severity', violation.Severity__c, severityVariant(violation.Severity__c)));

            AIConsoleDataStructure.ListCell what = new AIConsoleDataStructure.ListCell();
            what.key = 'what';
            what.type = 'twoLine';
            what.value = String.isNotBlank(violation.AIViolationRule__r?.RuleName__c) ? violation.AIViolationRule__r.RuleName__c : violation.ViolationType__c;
            what.secondary = (violation.RequestBlocked__c ? 'Blocked' : 'Logged') + ' · ' + AIConsoleUtility.relativeLabel(violation.CreatedDate);
            what.bold = true;
            what.target = new AIConsoleDataStructure.NavTarget(AIConsoleConstants.TAB_ACTIVITY, AIConsoleConstants.SECTION_ACTIVITY_VIOLATIONS, AIConsoleConstants.VIEW_RECORD, violation.Id);
            row.cells.add(what);

            result.rows.add(row);
        }

        result.totalCount = result.rows.size();
        return result;
    }

    // =============================================================
    // Activity › Violations
    // =============================================================

    private static AIConsoleDataStructure.ListResult buildViolations(ListContext context) {

        AIConsoleDataStructure.ListResult result = newResult('Violations', 'Activity', 'violation');
        result.detailComponent = 'aiViolationDetail';
        result.countLabel = rangeLabel(context.section.FilterCriteria__c);

        String chip = context.stringFilter('severity', 'all');
        String baseWhere = context.whereClause(null);

        AIConsoleDataStructure.ListFilter chips = newFilter('severity', 'Filter by severity', 'chips', chip);
        chips.options.add(countedOption('All', 'all', countWhere('AIViolation__c', baseWhere, context.binds)));
        for (String severity : new List<String>{ AIConsoleConstants.SEVERITY_HIGH, AIConsoleConstants.SEVERITY_MEDIUM, AIConsoleConstants.SEVERITY_LOW }) {
            context.binds.put('chipSeverity' + severity, severity);
            chips.options.add(countedOption(severity, severity, countWhere('AIViolation__c', context.whereClause('Severity__c = :chipSeverity' + severity), context.binds)));
        }
        chips.options.add(countedOption('Blocked', 'blocked', countWhere('AIViolation__c', context.whereClause('RequestBlocked__c = true'), context.binds)));
        result.filters.add(chips);

        String extra = null;
        if (chip == 'blocked') {
            extra = 'RequestBlocked__c = true';
        } else if (chip != 'all') {
            context.binds.put('severityFilter', chip);
            extra = 'Severity__c = :severityFilter';
        }

        String whereSql = context.whereClause(extra);
        result.totalCount = countWhere('AIViolation__c', whereSql, context.binds);

        result.columns = new List<AIConsoleDataStructure.ListColumn>{
            new AIConsoleDataStructure.ListColumn('severity', 'Severity'),
            new AIConsoleDataStructure.ListColumn('type', 'Violation Type'),
            new AIConsoleDataStructure.ListColumn('rule', 'Rule'),
            new AIConsoleDataStructure.ListColumn('user', 'User'),
            new AIConsoleDataStructure.ListColumn('conversation', 'Conversation'),
            new AIConsoleDataStructure.ListColumn('request', 'Request'),
            new AIConsoleDataStructure.ListColumn('when', 'When')
        };

        String query = 'SELECT Id, Severity__c, ViolationType__c, RequestBlocked__c, CreatedDate, AIViolationRule__c, AIViolationRule__r.RuleName__c, AIViolationRule__r.Agent__c, User__r.Name, AIConversation__c, AIConversation__r.Name, ReviewStatus__c FROM AIViolation__c'
                     + whereSql + ' ORDER BY CreatedDate DESC LIMIT ' + context.pageLimit() + ' OFFSET ' + context.offset;

        for (AIViolation__c violation : (List<AIViolation__c>) Database.queryWithBinds(query, context.binds, AccessLevel.USER_MODE)) {

            AIConsoleDataStructure.ListRow row = newRow(violation.Id);
            row.isMuted = violation.ReviewStatus__c == AIConsoleConstants.REVIEW_STATUS_REVIEWED;
            row.cells.add(badgeCell('severity', violation.Severity__c, severityVariant(violation.Severity__c)));
            row.cells.add(textCell('type', violation.ViolationType__c));
            row.cells.add(violation.AIViolationRule__c == null ? textCell('rule', '—') : linkCell('rule', violation.AIViolationRule__r.RuleName__c, false, guardrailsTarget(violation.AIViolationRule__r.Agent__c)));
            row.cells.add(textCell('user', violation.User__r?.Name));
            row.cells.add(conversationCell('conversation', violation.AIConversation__c, violation.AIConversation__r?.Name));
            row.cells.add(textCell('request', violation.RequestBlocked__c ? 'Blocked' : 'Logged'));
            row.cells.add(textCell('when', AIConsoleUtility.relativeLabel(violation.CreatedDate)));
            result.rows.add(row);
        }

        setHasMore(result, context);
        return result;
    }

    // =============================================================
    // Library › Model Configurations
    // =============================================================

    private static AIConsoleDataStructure.ListResult buildModels(ListContext context) {

        AIConsoleDataStructure.ListResult result = newResult('Model Configurations', 'Library', 'model');
        result.primaryActionLabel = 'New';
        result.primaryAction = 'newModel';
        result.rowView = 'editModel';
        result.footerNote = 'Callout timeout (' + AIConsoleUtility.formatNumber(AIAssistSettingsService.getCalloutTimeoutMilliseconds()) + ' ms) and the retryable status codes apply to every configuration and live in App Settings.';

        String defaultModel = AIAssistSettings__c.getOrgDefaults().DefaultModelConfiguration__c;

        String query = 'SELECT Id, Name, DeveloperName__c, AIProvider__c, ModelIdentifier__c, Temperature__c, MaximumOutputTokens__c, RetryAttempts__c, NamedCredential__c, IsActive__c FROM AIModelConfiguration__c'
                     + context.whereClause(null) + ' ORDER BY IsActive__c DESC, Name ASC LIMIT ' + context.pageLimit() + ' OFFSET ' + context.offset;
        List<AIModelConfiguration__c> models = Database.queryWithBinds(query, context.binds, AccessLevel.USER_MODE);

        String defaultModelName;
        for (AIModelConfiguration__c model : models) {
            if (String.isNotBlank(defaultModel) && model.DeveloperName__c == defaultModel) defaultModelName = model.Name;
        }
        if (defaultModelName == null && String.isNotBlank(defaultModel)) {
            List<AIModelConfiguration__c> matches = [ SELECT Name FROM AIModelConfiguration__c WHERE DeveloperName__c = :defaultModel LIMIT 1 ];
            if (!matches.isEmpty()) defaultModelName = matches[0].Name;
        }

        result.bannerHtml = defaultModelName == null
            ? 'No default model is set. Agents with no active model can’t reply until one is picked in App Settings › Default Model Configuration.'
            : 'Agents with no active model fall back to <b>' + defaultModelName.escapeHtml4() + '</b>, set in App Settings › Default Model Configuration.';
        result.bannerLinkLabel = 'Change';
        result.bannerTarget = new AIConsoleDataStructure.NavTarget(AIConsoleConstants.TAB_SETTINGS, AIConsoleConstants.SECTION_SETTINGS_APP, null, null);

        Map<Id, Integer> agentsByModel = new Map<Id, Integer>();
        for (AggregateResult row : [ SELECT AIModelConfiguration__c modelId, COUNT(Id) total FROM AIAgent__c WHERE AIModelConfiguration__c != null GROUP BY AIModelConfiguration__c ]) {
            agentsByModel.put((Id) row.get('modelId'), (Integer) row.get('total'));
        }

        result.columns = new List<AIConsoleDataStructure.ListColumn>{
            new AIConsoleDataStructure.ListColumn('name', 'Configuration Name'),
            new AIConsoleDataStructure.ListColumn('provider', 'Provider'),
            new AIConsoleDataStructure.ListColumn('model', 'Model Identifier'),
            new AIConsoleDataStructure.ListColumn('temperature', 'Temperature', true),
            new AIConsoleDataStructure.ListColumn('maxTokens', 'Max Output Tokens', true),
            new AIConsoleDataStructure.ListColumn('retries', 'Retries', true),
            new AIConsoleDataStructure.ListColumn('credential', 'Named Credential'),
            new AIConsoleDataStructure.ListColumn('usedBy', 'Used by', true),
            new AIConsoleDataStructure.ListColumn('status', 'Status')
        };

        for (AIModelConfiguration__c model : models) {

            AIConsoleDataStructure.ListRow row = newRow(model.Id);
            AIConsoleDataStructure.ListCell name = linkCell('name', model.Name, true, null);
            if (String.isNotBlank(defaultModel) && model.DeveloperName__c == defaultModel) name.extraBadge = 'Org default';
            row.cells.add(name);
            row.cells.add(textCell('provider', model.AIProvider__c));
            row.cells.add(monoCell('model', model.ModelIdentifier__c));
            row.cells.add(rightCell('temperature', model.Temperature__c == null ? '—' : String.valueOf(model.Temperature__c.stripTrailingZeros())));
            row.cells.add(rightCell('maxTokens', AIConsoleUtility.formatNumber(model.MaximumOutputTokens__c)));
            row.cells.add(rightCell('retries', AIConsoleUtility.formatNumber(model.RetryAttempts__c)));
            row.cells.add(monoCell('credential', model.NamedCredential__c));
            Integer usedBy = agentsByModel.containsKey(model.Id) ? agentsByModel.get(model.Id) : 0;
            row.cells.add(rightCell('usedBy', usedBy + (usedBy == 1 ? ' agent' : ' agents')));
            row.cells.add(badgeCell('status', model.IsActive__c ? 'Active' : 'Inactive', model.IsActive__c ? 'ok' : ''));
            result.rows.add(row);
        }

        result.totalCount = countWhere('AIModelConfiguration__c', context.whereClause(null), context.binds);
        setHasMore(result, context);
        return result;
    }

    // =============================================================
    // Library › Data Sources
    // =============================================================

    private static AIConsoleDataStructure.ListResult buildDataSources(ListContext context) {

        AIConsoleDataStructure.ListResult result = newResult('Data Sources', 'Library', 'datasource');
        result.primaryActionLabel = 'New';
        result.primaryAction = 'newDataSource';
        result.detailComponent = 'aiDataSourceDetail';

        String whereSql = context.whereClause(null);
        result.totalCount = countWhere('AIDataSource__c', whereSql, context.binds);
        result.subtitle = result.totalCount + (result.totalCount == 1 ? ' item' : ' items') + ' · Read-only. The AI calls these during a conversation.';

        Map<Id, Integer> agentsBySource = new Map<Id, Integer>();
        for (AggregateResult row : [ SELECT AIDataSource__c sourceId, COUNT(Id) total FROM AIAgentDataSource__c GROUP BY AIDataSource__c ]) {
            agentsBySource.put((Id) row.get('sourceId'), (Integer) row.get('total'));
        }

        result.columns = new List<AIConsoleDataStructure.ListColumn>{
            new AIConsoleDataStructure.ListColumn('name', 'Source Name'),
            new AIConsoleDataStructure.ListColumn('type', 'Type'),
            new AIConsoleDataStructure.ListColumn('binding', 'Binding'),
            new AIConsoleDataStructure.ListColumn('target', 'Target Object'),
            new AIConsoleDataStructure.ListColumn('agents', 'Agents', true),
            new AIConsoleDataStructure.ListColumn('status', 'Status')
        };

        String query = 'SELECT Id, Name, SourceName__c, DeveloperName__c, SourceType__c, BindingType__c, TargetObject__c, IsActive__c FROM AIDataSource__c' + whereSql + ' ORDER BY SourceName__c ASC NULLS LAST, DeveloperName__c ASC LIMIT ' + context.pageLimit() + ' OFFSET ' + context.offset;

        for (AIDataSource__c source : (List<AIDataSource__c>) Database.queryWithBinds(query, context.binds, AccessLevel.USER_MODE)) {
            AIConsoleDataStructure.ListRow row = newRow(source.Id);
            row.cells.add(linkCell('name', AIConsoleUtility.dataSourceName(source), true, null));
            row.cells.add(badgeCell('type', source.SourceType__c, ''));
            row.cells.add(textCell('binding', source.BindingType__c));
            row.cells.add(textCell('target', source.TargetObject__c));
            row.cells.add(rightCell('agents', String.valueOf(agentsBySource.containsKey(source.Id) ? agentsBySource.get(source.Id) : 0)));
            row.cells.add(badgeCell('status', source.IsActive__c ? 'Active' : 'Inactive', source.IsActive__c ? 'ok' : ''));
            result.rows.add(row);
        }

        setHasMore(result, context);
        return result;
    }

    // =============================================================
    // Library › Workflow Actions
    // =============================================================

    private static AIConsoleDataStructure.ListResult buildWorkflowActions(ListContext context) {

        AIConsoleDataStructure.ListResult result = newResult('Workflow Actions', 'Library', 'action');
        result.primaryActionLabel = 'New';
        result.primaryAction = 'newWorkflowAction';
        result.detailComponent = 'aiWorkflowActionDetail';

        String chip = context.stringFilter('execution', 'all');
        context.binds.put('writeType', AIConsoleConstants.EXECUTION_WRITE);
        context.binds.put('readOnlyType', AIConsoleConstants.EXECUTION_READ_ONLY);

        Map<String, String> chipWhere = new Map<String, String>{
            'all' => null,
            'write' => 'ExecutionType__c = :writeType',
            'readonly' => 'ExecutionType__c = :readOnlyType',
            'noconfirm' => 'ExecutionType__c = :writeType AND RequiresConfirmation__c = false'
        };

        AIConsoleDataStructure.ListFilter chips = newFilter('execution', 'Filter by execution', 'chips', chip);
        chips.options.add(countedOption('All', 'all', countWhere('AIWorkflowAction__c', context.whereClause(null), context.binds)));
        chips.options.add(countedOption('Write', 'write', countWhere('AIWorkflowAction__c', context.whereClause(chipWhere.get('write')), context.binds)));
        chips.options.add(countedOption('Read Only', 'readonly', countWhere('AIWorkflowAction__c', context.whereClause(chipWhere.get('readonly')), context.binds)));
        chips.options.add(countedOption('No confirmation', 'noconfirm', countWhere('AIWorkflowAction__c', context.whereClause(chipWhere.get('noconfirm')), context.binds)));
        result.filters.add(chips);

        String whereSql = context.whereClause(chipWhere.containsKey(chip) ? chipWhere.get(chip) : null);
        result.totalCount = countWhere('AIWorkflowAction__c', whereSql, context.binds);

        Map<Id, Integer> agentsByAction = new Map<Id, Integer>();
        for (AggregateResult row : [ SELECT AIWorkflowAction__c actionId, COUNT(Id) total FROM AIAgentWorkflowAction__c GROUP BY AIWorkflowAction__c ]) {
            agentsByAction.put((Id) row.get('actionId'), (Integer) row.get('total'));
        }

        result.columns = new List<AIConsoleDataStructure.ListColumn>{
            new AIConsoleDataStructure.ListColumn('name', 'Action Name'),
            new AIConsoleDataStructure.ListColumn('type', 'Type'),
            new AIConsoleDataStructure.ListColumn('execution', 'Execution'),
            new AIConsoleDataStructure.ListColumn('target', 'Target Object'),
            new AIConsoleDataStructure.ListColumn('confirmation', 'Confirmation'),
            new AIConsoleDataStructure.ListColumn('agents', 'Agents', true),
            new AIConsoleDataStructure.ListColumn('status', 'Status')
        };

        String query = 'SELECT Id, Name, ActionName__c, DeveloperName__c, ActionType__c, ExecutionType__c, TargetObject__c, RequiresConfirmation__c, IsActive__c FROM AIWorkflowAction__c' + whereSql + ' ORDER BY ActionName__c ASC NULLS LAST, DeveloperName__c ASC LIMIT ' + context.pageLimit() + ' OFFSET ' + context.offset;

        for (AIWorkflowAction__c action : (List<AIWorkflowAction__c>) Database.queryWithBinds(query, context.binds, AccessLevel.USER_MODE)) {
            AIConsoleDataStructure.ListRow row = newRow(action.Id);
            row.cells.add(linkCell('name', AIConsoleUtility.workflowActionName(action), true, null));
            row.cells.add(badgeCell('type', action.ActionType__c, ''));
            row.cells.add(badgeCell('execution', action.ExecutionType__c, executionVariant(action.ExecutionType__c)));
            row.cells.add(textCell('target', action.TargetObject__c));
            row.cells.add(confirmationCell('confirmation', action.ExecutionType__c, action.RequiresConfirmation__c));
            row.cells.add(rightCell('agents', String.valueOf(agentsByAction.containsKey(action.Id) ? agentsByAction.get(action.Id) : 0)));
            row.cells.add(badgeCell('status', action.IsActive__c ? 'Active' : 'Inactive', action.IsActive__c ? 'ok' : ''));
            result.rows.add(row);
        }

        setHasMore(result, context);
        return result;
    }

    // =============================================================
    // Activity › Conversations
    // =============================================================

    private static AIConsoleDataStructure.ListResult buildConversations(ListContext context) {

        AIConsoleDataStructure.ListResult result = newResult('Conversations', 'Activity', 'conversation');
        result.secondaryActionLabel = 'Export';
        result.secondaryAction = 'export';
        result.rowView = AIConsoleConstants.VIEW_RECORD;
        result.detailComponent = 'aiConversationDetail';

        String status = context.stringFilter('status', 'All');
        String agentId = context.stringFilter('agent', 'All');
        String channel = context.stringFilter('channel', 'All');
        String started = context.stringFilter('started', '7');
        Boolean hasViolation = context.booleanFilter('hasViolation');

        AIConsoleDataStructure.ListFilter statusFilter = newFilter('status', 'Status', 'select', status);
        statusFilter.width = 140;
        statusFilter.options.add(new AIConsoleDataStructure.Option('All', 'All'));
        for (String value : new List<String>{ AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE, AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED, AIAssistApplicationConstants.CONVERSATION_STATUS_ARCHIVED }) {
            statusFilter.options.add(new AIConsoleDataStructure.Option(value, value));
        }

        AIConsoleDataStructure.ListFilter agentFilter = newFilter('agent', 'Agent', 'select', agentId);
        agentFilter.width = 220;
        agentFilter.options.add(new AIConsoleDataStructure.Option('All agents', 'All'));
        for (AIAgent__c agent : [ SELECT Id, Name FROM AIAgent__c ORDER BY Name LIMIT 200 ]) {
            agentFilter.options.add(new AIConsoleDataStructure.Option(agent.Name, agent.Id));
        }

        AIConsoleDataStructure.ListFilter channelFilter = newFilter('channel', 'Channel', 'select', channel);
        channelFilter.width = 160;
        channelFilter.options.add(new AIConsoleDataStructure.Option('All', 'All'));
        channelFilter.options.add(new AIConsoleDataStructure.Option(AIAssistApplicationConstants.CHANNEL_RECORD_PAGE_CHAT, AIAssistApplicationConstants.CHANNEL_RECORD_PAGE_CHAT));
        channelFilter.options.add(new AIConsoleDataStructure.Option(AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, AIAssistApplicationConstants.CHANNEL_UTILITY_BAR));

        AIConsoleDataStructure.ListFilter startedFilter = newFilter('started', 'Started', 'select', started);
        startedFilter.width = 160;
        startedFilter.options.add(new AIConsoleDataStructure.Option('Today', '1'));
        startedFilter.options.add(new AIConsoleDataStructure.Option('Last 7 days', '7'));
        startedFilter.options.add(new AIConsoleDataStructure.Option('Last 30 days', '30'));
        startedFilter.options.add(new AIConsoleDataStructure.Option('Last 90 days', '90'));
        startedFilter.options.add(new AIConsoleDataStructure.Option('Any time', 'all'));

        AIConsoleDataStructure.ListFilter violationFilter = newFilter('hasViolation', 'Has a violation', 'checkbox', String.valueOf(hasViolation));

        result.filters.addAll(new List<AIConsoleDataStructure.ListFilter>{ statusFilter, agentFilter, channelFilter, startedFilter, violationFilter });

        List<String> conditions = new List<String>();
        if (status != 'All') { context.binds.put('statusFilter', status); conditions.add('Status__c = :statusFilter'); }
        if (agentId != 'All') { context.binds.put('agentFilter', agentId); conditions.add('AIAgent__c = :agentFilter'); }
        if (channel != 'All') { context.binds.put('channelFilter', channel); conditions.add('Channel__c = :channelFilter'); }
        if (started != 'all') {
            Integer days = Integer.valueOf(started);
            context.binds.put('startedAfter', Datetime.newInstance(System.today().addDays(1 - days), Time.newInstance(0, 0, 0, 0)));
            conditions.add('CreatedDate >= :startedAfter');
        }
        if (hasViolation) conditions.add('Id IN (SELECT AIConversation__c FROM AIViolation__c)');

        String whereSql = context.whereClause(conditions.isEmpty() ? null : String.join(conditions, ' AND '));
        result.totalCount = countWhere('AIConversation__c', whereSql, context.binds);
        result.countLabel = AIConsoleUtility.formatNumber(result.totalCount) + (result.totalCount == 1 ? ' conversation' : ' conversations');

        result.columns = new List<AIConsoleDataStructure.ListColumn>{
            new AIConsoleDataStructure.ListColumn('name', 'Conversation'),
            new AIConsoleDataStructure.ListColumn('user', 'User'),
            new AIConsoleDataStructure.ListColumn('agent', 'Agent'),
            new AIConsoleDataStructure.ListColumn('record', 'Record'),
            new AIConsoleDataStructure.ListColumn('channel', 'Channel'),
            new AIConsoleDataStructure.ListColumn('status', 'Status'),
            new AIConsoleDataStructure.ListColumn('messages', 'Messages', true),
            new AIConsoleDataStructure.ListColumn('tokens', 'Tokens', true),
            new AIConsoleDataStructure.ListColumn('started', 'Started'),
            new AIConsoleDataStructure.ListColumn('closeReason', 'Close Reason')
        };

        String query = 'SELECT Id, Name, Owner.Name, AIAgent__r.Name, RelatedRecordId__c, Channel__c, Status__c, MessageCount__c, ConversationTokenUsage__c, CreatedDate, ConversationCloseReason__c FROM AIConversation__c'
                     + whereSql + ' ORDER BY CreatedDate DESC LIMIT ' + context.pageLimit() + ' OFFSET ' + context.offset;
        List<AIConversation__c> conversations = Database.queryWithBinds(query, context.binds, AccessLevel.USER_MODE);

        Set<Id> conversationIds = new Map<Id, AIConversation__c>(conversations).keySet();
        Map<Id, Integer> violationsByConversation = new Map<Id, Integer>();
        for (AggregateResult row : [ SELECT AIConversation__c conversationId, COUNT(Id) total FROM AIViolation__c WHERE AIConversation__c IN :conversationIds GROUP BY AIConversation__c ]) {
            violationsByConversation.put((Id) row.get('conversationId'), (Integer) row.get('total'));
        }

        Set<String> recordIds = new Set<String>();
        for (AIConversation__c conversation : conversations) {
            if (String.isNotBlank(conversation.RelatedRecordId__c)) recordIds.add(conversation.RelatedRecordId__c);
        }
        Map<String, String> recordLabels = getRecordLabels(recordIds);

        for (AIConversation__c conversation : conversations) {

            AIConsoleDataStructure.ListRow row = newRow(conversation.Id);
            AIConsoleDataStructure.ListCell name = linkCell('name', conversation.Name, true, null);
            name.violationCount = violationsByConversation.get(conversation.Id);
            row.cells.add(name);
            row.cells.add(textCell('user', conversation.Owner.Name));
            row.cells.add(textCell('agent', conversation.AIAgent__r?.Name));
            row.cells.add(recordCell('record', conversation.RelatedRecordId__c, recordLabels.get(conversation.RelatedRecordId__c)));
            row.cells.add(textCell('channel', conversation.Channel__c));
            row.cells.add(badgeCell('status', conversation.Status__c, conversation.Status__c == AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE ? 'ok' : ''));
            row.cells.add(rightCell('messages', AIConsoleUtility.formatNumber(conversation.MessageCount__c)));
            row.cells.add(rightCell('tokens', AIConsoleUtility.formatNumber(conversation.ConversationTokenUsage__c)));
            row.cells.add(textCell('started', AIConsoleUtility.shortDateTimeLabel(conversation.CreatedDate)));
            row.cells.add(textCell('closeReason', String.isBlank(conversation.ConversationCloseReason__c) ? '—' : conversation.ConversationCloseReason__c));
            result.rows.add(row);
        }

        setHasMore(result, context);
        return result;
    }

    // =============================================================
    // Activity › Error Log
    // =============================================================

    private static AIConsoleDataStructure.ListResult buildErrorLog(ListContext context) {

        AIConsoleDataStructure.ListResult result = newResult('Error Log', 'Activity · AI Platform Log', 'log');
        result.secondaryActionLabel = 'Export';
        result.secondaryAction = 'export';
        result.detailComponent = 'aiPlatformLogDetail';

        String exceptionType = context.stringFilter('exceptionType', 'All');
        String className = context.stringFilter('className', 'All');
        String range = context.stringFilter('range', '1');

        context.binds.put('logsAfter', Datetime.newInstance(System.today().addDays(1 - Integer.valueOf(range)), Time.newInstance(0, 0, 0, 0)));
        String rangeCondition = 'CreatedDate >= :logsAfter';

        AIConsoleDataStructure.ListFilter typeFilter = newFilter('exceptionType', 'Exception type', 'select', exceptionType);
        typeFilter.width = 240;
        typeFilter.options.add(new AIConsoleDataStructure.Option('All exception types', 'All'));

        AIConsoleDataStructure.ListFilter classFilter = newFilter('className', 'Class', 'select', className);
        classFilter.width = 220;
        classFilter.options.add(new AIConsoleDataStructure.Option('All classes', 'All'));

        Datetime logsAfter = (Datetime) context.binds.get('logsAfter');
        for (AggregateResult row : [ SELECT ExceptionType__c value FROM AIPlatformLog__c WHERE CreatedDate >= :logsAfter AND ExceptionType__c != null GROUP BY ExceptionType__c ORDER BY ExceptionType__c LIMIT 100 ]) {
            typeFilter.options.add(new AIConsoleDataStructure.Option((String) row.get('value'), (String) row.get('value')));
        }
        for (AggregateResult row : [ SELECT ClassName__c value FROM AIPlatformLog__c WHERE CreatedDate >= :logsAfter AND ClassName__c != null GROUP BY ClassName__c ORDER BY ClassName__c LIMIT 100 ]) {
            classFilter.options.add(new AIConsoleDataStructure.Option((String) row.get('value'), (String) row.get('value')));
        }

        AIConsoleDataStructure.ListFilter rangeFilter = newFilter('range', 'Date range', 'select', range);
        rangeFilter.width = 150;
        rangeFilter.options.add(new AIConsoleDataStructure.Option('Today', '1'));
        rangeFilter.options.add(new AIConsoleDataStructure.Option('Last 7 days', '7'));
        rangeFilter.options.add(new AIConsoleDataStructure.Option('Last 30 days', '30'));

        typeFilter.labelHidden = true;
        classFilter.labelHidden = true;
        rangeFilter.labelHidden = true;
        result.filters.addAll(new List<AIConsoleDataStructure.ListFilter>{ typeFilter, classFilter, rangeFilter });

        List<String> conditions = new List<String>{ rangeCondition };
        if (exceptionType != 'All') { context.binds.put('typeFilter', exceptionType); conditions.add('ExceptionType__c = :typeFilter'); }
        if (className != 'All') { context.binds.put('classFilter', className); conditions.add('ClassName__c = :classFilter'); }

        String whereSql = context.whereClause(String.join(conditions, ' AND '));
        result.totalCount = countWhere('AIPlatformLog__c', whereSql, context.binds);
        result.countLabel = result.totalCount + (result.totalCount == 1 ? ' entry' : ' entries');

        result.columns = new List<AIConsoleDataStructure.ListColumn>{
            new AIConsoleDataStructure.ListColumn('occurred', 'Occurred At'),
            new AIConsoleDataStructure.ListColumn('type', 'Exception Type'),
            new AIConsoleDataStructure.ListColumn('source', 'Class · Method'),
            new AIConsoleDataStructure.ListColumn('message', 'Message'),
            new AIConsoleDataStructure.ListColumn('user', 'User')
        };

        String query = 'SELECT Id, OccurredAt__c, CreatedDate, ExceptionType__c, ClassName__c, MethodName__c, ExceptionMessage__c, User__r.Name, CreatedBy.Name FROM AIPlatformLog__c'
                     + whereSql + ' ORDER BY CreatedDate DESC LIMIT ' + context.pageLimit() + ' OFFSET ' + context.offset;

        for (AIPlatformLog__c log : (List<AIPlatformLog__c>) Database.queryWithBinds(query, context.binds, AccessLevel.USER_MODE)) {
            AIConsoleDataStructure.ListRow row = newRow(log.Id);
            row.cells.add(textCell('occurred', AIConsoleUtility.shortDateTimeLabel(log.OccurredAt__c == null ? log.CreatedDate : log.OccurredAt__c)));
            row.cells.add(monoCell('type', log.ExceptionType__c));
            row.cells.add(monoCell('source', joinSource(log.ClassName__c, log.MethodName__c)));
            row.cells.add(textCell('message', log.ExceptionMessage__c));
            row.cells.add(textCell('user', log.User__r?.Name != null ? log.User__r.Name : log.CreatedBy.Name));
            result.rows.add(row);
        }

        setHasMore(result, context);
        return result;
    }

    // =============================================================
    // Any other object
    // =============================================================

    private static AIConsoleDataStructure.ListResult buildGeneric(ListContext context, String objectApiName) {

        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        if (objectType == null) throw new AIConsoleDataStructure.AIConsoleException('The object ' + objectApiName + ' doesn\'t exist in this org.');

        AIConsoleDataStructure.ListResult result = newResult(context.section.SectionLabel__c, null, null);
        result.columns = new List<AIConsoleDataStructure.ListColumn>{
            new AIConsoleDataStructure.ListColumn('name', 'Name'),
            new AIConsoleDataStructure.ListColumn('created', 'Created'),
            new AIConsoleDataStructure.ListColumn('modified', 'Last Modified')
        };

        String whereSql = context.whereClause(null);
        String query = 'SELECT Id, Name, CreatedDate, LastModifiedDate FROM ' + objectType.getDescribe().getName() + whereSql + ' ORDER BY LastModifiedDate DESC LIMIT ' + context.pageLimit() + ' OFFSET ' + context.offset;

        for (SObject record : Database.queryWithBinds(query, context.binds, AccessLevel.USER_MODE)) {
            AIConsoleDataStructure.ListRow row = newRow(record.Id);
            AIConsoleDataStructure.ListCell name = recordCell('name', record.Id, (String) record.get('Name'));
            row.cells.add(name);
            row.cells.add(textCell('created', AIConsoleUtility.dateTimeLabel((Datetime) record.get('CreatedDate'))));
            row.cells.add(textCell('modified', AIConsoleUtility.dateTimeLabel((Datetime) record.get('LastModifiedDate'))));
            result.rows.add(row);
        }

        result.totalCount = countWhere(objectType.getDescribe().getName(), whereSql, context.binds);
        setHasMore(result, context);
        return result;
    }

    // =============================================================
    // Record labels - "00012944 — Card declined" for a Case, the Name field for anything else
    // =============================================================

    public static Map<String, String> getRecordLabels(Set<String> recordIds) {

        Map<String, String> labels = new Map<String, String>();
        Map<Schema.SObjectType, Set<Id>> idsByType = new Map<Schema.SObjectType, Set<Id>>();

        for (String recordId : recordIds) {
            try {
                Id typedId = Id.valueOf(recordId);
                Schema.SObjectType objectType = typedId.getSobjectType();
                if (!idsByType.containsKey(objectType)) idsByType.put(objectType, new Set<Id>());
                idsByType.get(objectType).add(typedId);
            } catch (Exception ex) {
                continue; // Not a valid Id - shown as is.
            }
        }

        Integer typesQueried = 0;
        for (Schema.SObjectType objectType : idsByType.keySet()) {

            if (typesQueried++ >= 10) break; // One query per object type - bounded so a noisy list can't run away with SOQL.

            Set<Id> ids = idsByType.get(objectType);
            Schema.DescribeSObjectResult describe = objectType.getDescribe();
            if (!describe.isAccessible()) continue;

            try {
                if (describe.getName() == 'Case') {
                    for (Case record : [ SELECT Id, CaseNumber, Subject FROM Case WHERE Id IN :ids WITH USER_MODE ]) {
                        labels.put(String.valueOf(record.Id), record.CaseNumber + (String.isBlank(record.Subject) ? '' : ' — ' + record.Subject));
                        labels.put(String.valueOf(record.Id).left(15), labels.get(String.valueOf(record.Id)));
                    }
                    continue;
                }

                String nameField = getNameField(describe);
                if (nameField == null) continue;

                for (SObject record : Database.queryWithBinds('SELECT Id, ' + nameField + ' FROM ' + describe.getName() + ' WHERE Id IN :ids', new Map<String, Object>{ 'ids' => ids }, AccessLevel.USER_MODE)) {
                    String label = String.valueOf(record.get(nameField));
                    labels.put(String.valueOf(record.Id), label);
                    labels.put(String.valueOf(record.Id).left(15), label);
                }
            } catch (Exception ex) {
                continue; // No access to the object or field - the Id is shown instead.
            }
        }

        return labels;
    }

    private static String getNameField(Schema.DescribeSObjectResult describe) {
        for (Schema.SObjectField field : describe.fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            if (fieldDescribe.isNameField()) return fieldDescribe.getName();
        }
        return null;
    }

    // =============================================================
    // Cell and result builders
    // =============================================================

    private static AIConsoleDataStructure.ListResult newResult(String title, String eyebrow, String icon) {
        AIConsoleDataStructure.ListResult result = new AIConsoleDataStructure.ListResult();
        result.title = title;
        result.eyebrow = eyebrow;
        result.icon = icon;
        return result;
    }

    private static AIConsoleDataStructure.ListRow newRow(Id recordId) {
        AIConsoleDataStructure.ListRow row = new AIConsoleDataStructure.ListRow();
        row.id = recordId;
        return row;
    }

    private static AIConsoleDataStructure.ListFilter newFilter(String key, String label, String type, String value) {
        AIConsoleDataStructure.ListFilter filter = new AIConsoleDataStructure.ListFilter();
        filter.key = key;
        filter.label = label;
        filter.type = type;
        filter.value = value;
        return filter;
    }

    private static AIConsoleDataStructure.Option countedOption(String label, String value, Integer count) {
        AIConsoleDataStructure.Option option = new AIConsoleDataStructure.Option(label + ' (' + count + ')', value);
        option.count = count;
        return option;
    }

    private static AIConsoleDataStructure.ListColumn hiddenColumn(String key, String label) {
        AIConsoleDataStructure.ListColumn column = new AIConsoleDataStructure.ListColumn(key, label);
        column.hideLabel = true;
        return column;
    }

    public static AIConsoleDataStructure.ListCell textCell(String key, String value) {
        AIConsoleDataStructure.ListCell cell = new AIConsoleDataStructure.ListCell();
        cell.key = key;
        cell.value = String.isBlank(value) ? '—' : value;
        return cell;
    }

    private static AIConsoleDataStructure.ListCell rightCell(String key, String value) {
        AIConsoleDataStructure.ListCell cell = textCell(key, value);
        cell.alignRight = true;
        return cell;
    }

    private static AIConsoleDataStructure.ListCell monoCell(String key, String value) {
        AIConsoleDataStructure.ListCell cell = textCell(key, value);
        cell.type = 'mono';
        return cell;
    }

    public static AIConsoleDataStructure.ListCell badgeCell(String key, String value, String variant) {
        AIConsoleDataStructure.ListCell cell = textCell(key, value);
        cell.type = 'badge';
        cell.variant = variant;
        return cell;
    }

    // No target: the link opens the row itself (its detail panel, record view or edit modal).
    public static AIConsoleDataStructure.ListCell linkCell(String key, String value, Boolean bold, AIConsoleDataStructure.NavTarget target) {
        AIConsoleDataStructure.ListCell cell = textCell(key, value);
        cell.type = 'link';
        cell.bold = bold;
        cell.target = target;
        return cell;
    }

    private static AIConsoleDataStructure.ListCell conversationCell(String key, Id conversationId, String name) {
        if (conversationId == null) return textCell(key, '—');
        return linkCell(key, name, false, new AIConsoleDataStructure.NavTarget(AIConsoleConstants.TAB_ACTIVITY, AIConsoleConstants.SECTION_ACTIVITY_CONVERSATIONS, AIConsoleConstants.VIEW_RECORD, conversationId));
    }

    // Opens the Salesforce record itself (tab "record" is handled by aiTabPage as a standard record page).
    private static AIConsoleDataStructure.ListCell recordCell(String key, String recordId, String label) {
        if (String.isBlank(recordId)) return textCell(key, '—');
        return linkCell(key, String.isBlank(label) ? recordId : label, false, new AIConsoleDataStructure.NavTarget('record', null, null, recordId));
    }

    private static AIConsoleDataStructure.ListCell confirmationCell(String key, String executionType, Boolean requiresConfirmation) {
        if (executionType == AIConsoleConstants.EXECUTION_READ_ONLY) return textCell(key, '—');
        if (requiresConfirmation) return textCell(key, 'Asks first');

        AIConsoleDataStructure.ListCell cell = textCell(key, 'Runs without asking');
        cell.type = 'warning';
        return cell;
    }

    // The Guardrails step of the rule's agent in the Agent Wizard.
    public static AIConsoleDataStructure.NavTarget guardrailsTarget(Id agentId) {
        AIConsoleDataStructure.NavTarget target = new AIConsoleDataStructure.NavTarget(AIConsoleConstants.TAB_AGENT_WIZARD, null, null, agentId);
        target.step = 5;
        return target;
    }

    public static String severityVariant(String severity) {
        if (severity == AIConsoleConstants.SEVERITY_HIGH) return 'err';
        if (severity == AIConsoleConstants.SEVERITY_MEDIUM) return 'warn';
        return '';
    }

    public static String executionVariant(String executionType) {
        return executionType == AIConsoleConstants.EXECUTION_WRITE ? 'write' : (executionType == AIConsoleConstants.EXECUTION_READ_ONLY ? 'ro' : '');
    }

    private static String joinSource(String className, String methodName) {
        if (String.isBlank(className)) return methodName;
        return String.isBlank(methodName) ? className : className + '.' + methodName;
    }

    // "Last 7 days" from a section filter like CreatedDate = LAST_N_DAYS:7.
    private static String rangeLabel(String criteria) {
        if (String.isBlank(criteria)) return null;
        Matcher matcher = Pattern.compile('LAST_N_DAYS:(\\d+)').matcher(criteria);
        if (matcher.find()) return 'Last ' + matcher.group(1) + ' days';
        if (criteria.contains('= TODAY')) return 'Today';
        return null;
    }

    private static Integer countWhere(String objectApiName, String whereSql, Map<String, Object> binds) {
        return Database.countQueryWithBinds('SELECT COUNT() FROM ' + objectApiName + whereSql, binds, AccessLevel.USER_MODE);
    }

    private static void setHasMore(AIConsoleDataStructure.ListResult result, ListContext context) {
        result.hasMore = context.offset + result.rows.size() < result.totalCount && context.section.MaxRecordsShown__c == null;
    }

    // The section row plus the user's filters and paging - builds the WHERE clause every query in a builder shares.
    private class ListContext {

        AINavTabSection__mdt section;
        Map<String, Object> filters;
        Map<String, Object> binds = new Map<String, Object>();
        Integer offset;

        ListContext(AINavTabSection__mdt section, Map<String, Object> filters, Integer offset) {
            this.section = section;
            this.filters = filters;
            this.offset = offset == null || offset < 0 ? 0 : Math.min(offset, 2000);
        }

        String whereClause(String extraCondition) {
            List<String> parts = new List<String>();
            if (String.isNotBlank(section.FilterCriteria__c)) parts.add('(' + section.FilterCriteria__c + ')');
            if (String.isNotBlank(extraCondition)) parts.add('(' + extraCondition + ')');
            return parts.isEmpty() ? '' : ' WHERE ' + String.join(parts, ' AND ');
        }

        Integer rowLimit(Integer fallback) {
            return section.MaxRecordsShown__c == null ? fallback : section.MaxRecordsShown__c.intValue();
        }

        Integer pageLimit() {
            return rowLimit(AIConsoleConstants.LIST_PAGE_SIZE);
        }

        String stringFilter(String key, String fallback) {
            Object value = filters.get(key);
            return value == null || String.isBlank(String.valueOf(value)) ? fallback : String.valueOf(value);
        }

        Boolean booleanFilter(String key) {
            Object value = filters.get(key);
            return value != null && (value == true || String.valueOf(value) == 'true');
        }
    }
}