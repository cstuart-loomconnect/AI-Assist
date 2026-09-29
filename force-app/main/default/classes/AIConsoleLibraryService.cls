/*
Class Name: AIConsoleLibraryService

=================================================================
=================================================================

Description: The AI Library tab's building blocks, shared across agents through the junction objects:

AIModelConfiguration__c - read/save for the New Model Configuration modal (aiModelConfigModal), and
                          "Test connection", which sends a one-line prompt through the Named Credential.
AIDataSource__c         - read/save for the New Data Source modal (aiDataSourceModal), the detail panel
                          (aiDataSourceDetail) and "Run test", which runs the SOQL template read-only as
                          the running user (USER_MODE), capped at 20 rows.
AIWorkflowAction__c     - read/save for aiWorkflowActionModal and the detail panel (aiWorkflowActionDetail).

A test run never writes anything - test connection is a callout only, and a SOQL test is a query only -
so both can run in the same transaction as nothing else.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-29     Chandler Stuart          Initial development
*/

public with sharing class AIConsoleLibraryService {

    private static final Pattern BIND_PATTERN = Pattern.compile(':([A-Za-z_][A-Za-z0-9_]*)');
    private static final Pattern LIMIT_PATTERN = Pattern.compile('(?i)\\bLIMIT\\s+\\d+');

    // =============================================================
    // Model Configurations
    // =============================================================

    public static AIConsoleDataStructure.ModelConfigView getModelConfig(Id modelId) {

        List<AIModelConfiguration__c> models = [ SELECT Id, Name, DeveloperName__c, AIProvider__c, ModelIdentifier__c, NamedCredential__c, ApiPath__c, ApiVersionHeaderName__c, ApiVersionHeaderValue__c,
                                                        Temperature__c, MaximumOutputTokens__c, RetryAttempts__c, IsActive__c
                                                 FROM AIModelConfiguration__c WHERE Id = :modelId LIMIT 1 ];
        if (models.isEmpty()) throw new AIConsoleDataStructure.AIConsoleException('That model configuration no longer exists.');

        AIModelConfiguration__c model = models[0];
        AIConsoleDataStructure.ModelConfigView view = new AIConsoleDataStructure.ModelConfigView();
        view.id = model.Id;
        view.name = model.Name;
        view.developerName = model.DeveloperName__c;
        view.provider = model.AIProvider__c;
        view.modelIdentifier = model.ModelIdentifier__c;
        view.namedCredential = model.NamedCredential__c;
        view.apiPath = model.ApiPath__c;
        view.headerName = model.ApiVersionHeaderName__c;
        view.headerValue = model.ApiVersionHeaderValue__c;
        view.temperature = model.Temperature__c;
        view.maxOutputTokens = AIConsoleUtility.toInteger(model.MaximumOutputTokens__c);
        view.retryAttempts = AIConsoleUtility.toInteger(model.RetryAttempts__c);
        view.isActive = model.IsActive__c == true;
        return view;
    }

    public static List<AIConsoleDataStructure.Option> getNamedCredentialOptions() {
        List<AIConsoleDataStructure.Option> options = new List<AIConsoleDataStructure.Option>();
        for (NamedCredential credential : [ SELECT DeveloperName, MasterLabel FROM NamedCredential ORDER BY DeveloperName LIMIT 200 ]) {
            options.add(new AIConsoleDataStructure.Option(credential.DeveloperName, credential.DeveloperName));
        }
        return options;
    }

    public static Id saveModelConfig(AIConsoleDataStructure.ModelConfigView view) {

        validateModel(view);

        AIModelConfiguration__c model = view.id == null ? new AIModelConfiguration__c() : new AIModelConfiguration__c(Id = view.id);
        model.Name = view.name.trim().left(80);
        model.DeveloperName__c = String.isBlank(view.developerName) ? null : view.developerName.trim().left(75);
        model.AIProvider__c = view.provider;
        model.ModelIdentifier__c = view.modelIdentifier.trim();
        model.NamedCredential__c = view.namedCredential.trim();
        model.ApiPath__c = view.apiPath;
        model.ApiVersionHeaderName__c = view.headerName;
        model.ApiVersionHeaderValue__c = view.headerValue;
        model.Temperature__c = view.temperature;
        model.MaximumOutputTokens__c = view.maxOutputTokens;
        model.RetryAttempts__c = view.retryAttempts;
        model.IsActive__c = view.isActive == true;

        upsert model;
        return model.Id;
    }

    // Sends "Reply with OK." with the form's current values - nothing is saved. Counts towards today's tokens at the provider.
    public static AIConsoleDataStructure.ConnectionTestResult testConnection(AIConsoleDataStructure.ModelConfigView view) {

        validateModel(view);
        AIConsoleDataStructure.ConnectionTestResult result = new AIConsoleDataStructure.ConnectionTestResult();

        if (!AIProvider.isSupported(view.provider)) {
            result.message = view.provider + ' isn\'t a supported provider.';
            return result;
        }

        AIProvider.Request request = new AIProvider.Request();
        request.modelIdentifier = view.modelIdentifier.trim();
        request.maxOutputTokens = 16;
        request.temperature = view.temperature == null ? 0 : view.temperature;
        request.systemPromptText = 'You are checking a connection.';
        request.messages = new List<Map<String, Object>>{ new Map<String, Object>{
            AIAssistApplicationConstants.CANONICAL_ROLE_KEY => AIAssistApplicationConstants.CANONICAL_ROLE_USER,
            AIAssistApplicationConstants.CANONICAL_CONTENT_KEY => 'Reply with OK.'
        } };
        request.tools = new List<AIProvider.ToolDefinition>();
        request.allowToolCalls = false;

        HttpRequest httpRequest = new HttpRequest();
        httpRequest.setEndpoint('callout:' + view.namedCredential.trim() + (String.isBlank(view.apiPath) ? '' : view.apiPath.trim()));
        httpRequest.setMethod('POST');
        httpRequest.setHeader('Content-Type', 'application/json');
        if (String.isNotBlank(view.headerName)) httpRequest.setHeader(view.headerName.trim(), view.headerValue == null ? '' : view.headerValue.trim());
        httpRequest.setTimeout(Math.min(AIAssistSettingsService.getCalloutTimeoutMilliseconds(), 120000));
        httpRequest.setBody(JSON.serialize(AIProvider.getRequestBuilder(view.provider).buildRequestBody(request)));

        Long startedAt = System.currentTimeMillis();
        try {
            HttpResponse response = new Http().send(httpRequest);
            result.durationMs = System.currentTimeMillis() - startedAt;
            result.statusCode = response.getStatusCode();
            result.success = AIAssistSettingsService.getSuccessStatusCodes().contains(result.statusCode);
            result.message = result.success ? 'Connected' : describeFailure(response);
        } catch (Exception ex) {
            result.durationMs = System.currentTimeMillis() - startedAt;
            result.message = ex.getMessage();
        }

        return result;
    }

    private static String describeFailure(HttpResponse response) {
        String body = response.getBody();
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
            Object error = parsed.get('error');
            if (error instanceof Map<String, Object>) return String.valueOf(((Map<String, Object>) error).get('message')).left(200);
        } catch (Exception ex) {
            // Not JSON - fall through to the status.
        }
        return response.getStatus();
    }

    private static void validateModel(AIConsoleDataStructure.ModelConfigView view) {
        if (view == null || String.isBlank(view.name)) throw new AIConsoleDataStructure.AIConsoleException('Configuration Name is required.');
        if (String.isBlank(view.provider)) throw new AIConsoleDataStructure.AIConsoleException('Pick an AI Provider.');
        if (String.isBlank(view.modelIdentifier)) throw new AIConsoleDataStructure.AIConsoleException('Model Identifier is required.');
        if (String.isBlank(view.namedCredential)) throw new AIConsoleDataStructure.AIConsoleException('Named Credential is required.');
        if (view.temperature != null && (view.temperature < 0 || view.temperature > 1)) throw new AIConsoleDataStructure.AIConsoleException('Temperature must be between 0 and 1.');
        if (view.maxOutputTokens != null && view.maxOutputTokens < 1) throw new AIConsoleDataStructure.AIConsoleException('Maximum Output Tokens must be at least 1.');
        if (view.retryAttempts != null && (view.retryAttempts < 0 || view.retryAttempts > 10)) throw new AIConsoleDataStructure.AIConsoleException('Retry Attempts must be between 0 and 10.');
    }

    // =============================================================
    // Data Sources
    // =============================================================

    public static AIConsoleDataStructure.DataSourceView getDataSource(Id dataSourceId) {

        List<AIDataSource__c> sources = [ SELECT Id, Name, SourceName__c, DeveloperName__c, Description__c, SourceType__c, BindingType__c, TargetObject__c, OutputDescription__c, SOQLTemplate__c, InputSchema__c, ApexClassName__c, IsActive__c
                                          FROM AIDataSource__c WHERE Id = :dataSourceId LIMIT 1 ];
        if (sources.isEmpty()) throw new AIConsoleDataStructure.AIConsoleException('That data source no longer exists.');

        AIDataSource__c source = sources[0];
        AIConsoleDataStructure.DataSourceView view = new AIConsoleDataStructure.DataSourceView();
        view.id = source.Id;
        view.name = AIConsoleUtility.dataSourceName(source);
        view.developerName = source.DeveloperName__c;
        view.description = source.Description__c;
        view.sourceType = source.SourceType__c;
        view.bindingType = source.BindingType__c;
        view.targetObject = source.TargetObject__c;
        view.outputDescription = source.OutputDescription__c;
        view.soqlTemplate = source.SOQLTemplate__c;
        view.inputSchema = source.InputSchema__c;
        view.apexClassName = source.ApexClassName__c;
        view.isActive = source.IsActive__c == true;

        for (AIAgentDataSource__c link : [ SELECT AIAgent__c, AIAgent__r.Name FROM AIAgentDataSource__c WHERE AIDataSource__c = :dataSourceId ORDER BY AIAgent__r.Name LIMIT 50 ]) {
            AIConsoleDataStructure.RelatedLine line = new AIConsoleDataStructure.RelatedLine();
            line.id = link.AIAgent__c;
            line.name = link.AIAgent__r.Name;
            view.usedBy.add(line);
        }

        Datetime rangeStart = System.now().addDays(-14);
        Integer calls = 0;
        Integer failures = 0;
        List<Decimal> durations = new List<Decimal>();
        for (AIExecutionStep__c step : [ SELECT Status__c, DurationMilliseconds__c FROM AIExecutionStep__c WHERE AIDataSource__c = :dataSourceId AND CreatedDate >= :rangeStart ORDER BY DurationMilliseconds__c ASC LIMIT 5000 ]) {
            calls++;
            if (step.Status__c == AIAssistApplicationConstants.EXECUTION_STEP_STATUS_FAILED) failures++;
            if (step.DurationMilliseconds__c != null) durations.add(step.DurationMilliseconds__c);
        }
        String median = durations.isEmpty() ? null : 'median ' + AIConsoleUtility.formatNumber(durations[durations.size() / 2]) + ' ms';
        view.usageLast14Days = calls == 0 ? 'No calls yet' : calls + (calls == 1 ? ' call · ' : ' calls · ') + failures + (failures == 1 ? ' failure' : ' failures') + (median == null ? '' : ' · ' + median);

        return view;
    }

    // assignToAgentId: "Save & assign" from the wizard - also links the saved source to that agent.
    public static Id saveDataSource(AIConsoleDataStructure.DataSourceView view, Id assignToAgentId) {

        if (view == null || String.isBlank(view.name)) throw new AIConsoleDataStructure.AIConsoleException('Source Name is required.');
        if (String.isBlank(view.description)) throw new AIConsoleDataStructure.AIConsoleException('Description is required - the AI reads it to decide when to call the source.');
        if (String.isBlank(view.sourceType)) throw new AIConsoleDataStructure.AIConsoleException('Pick a Source Type.');
        if (String.isBlank(view.bindingType)) throw new AIConsoleDataStructure.AIConsoleException('Pick a Binding Type.');
        if (String.isBlank(view.targetObject)) throw new AIConsoleDataStructure.AIConsoleException('Target Object is required.');

        Boolean isSoql = view.sourceType == AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL;
        if (isSoql && String.isBlank(view.soqlTemplate)) throw new AIConsoleDataStructure.AIConsoleException('SOQL Template is required.');
        if (!isSoql && String.isBlank(view.apexClassName)) throw new AIConsoleDataStructure.AIConsoleException('Apex Class Name is required.');
        if (isSoql && !view.soqlTemplate.trim().toUpperCase().startsWith('SELECT')) throw new AIConsoleDataStructure.AIConsoleException('A SOQL Template must be a SELECT query.');
        if (String.isNotBlank(view.inputSchema)) {
            try { JSON.deserializeUntyped(view.inputSchema); } catch (Exception ex) { throw new AIConsoleDataStructure.AIConsoleException('Input Schema isn\'t valid JSON.'); }
        }

        AIDataSource__c source = view.id == null ? new AIDataSource__c() : new AIDataSource__c(Id = view.id);
        source.SourceName__c = view.name.trim().left(80);
        source.DeveloperName__c = String.isBlank(view.developerName) ? null : view.developerName.trim().left(75);
        source.Description__c = view.description;
        source.SourceType__c = view.sourceType;
        source.BindingType__c = view.bindingType;
        source.TargetObject__c = view.targetObject.trim();
        source.OutputDescription__c = view.outputDescription;
        source.SOQLTemplate__c = isSoql ? view.soqlTemplate.trim() : null;
        source.ApexClassName__c = isSoql ? null : view.apexClassName.trim();
        source.InputSchema__c = view.inputSchema;
        source.IsActive__c = view.isActive == true;
        upsert source;

        if (assignToAgentId != null) {
            AIConsoleAgentService.queryAgent(assignToAgentId);
            Integer existing = [ SELECT COUNT() FROM AIAgentDataSource__c WHERE AIAgent__c = :assignToAgentId AND AIDataSource__c = :source.Id ];
            if (existing == 0) insert new AIAgentDataSource__c(AIAgent__c = assignToAgentId, AIDataSource__c = source.Id, IsActive__c = true);
        }

        return source.Id;
    }

    public static void setDataSourceActive(Id dataSourceId, Boolean isActive) {
        update new AIDataSource__c(Id = dataSourceId, IsActive__c = isActive == true);
    }

    // Runs the form's SOQL against a test record, read-only as the running user. Every bind the template names is filled - :recordId with the test record, anything else left null.
    public static AIConsoleDataStructure.DataSourceTestResult testDataSource(AIConsoleDataStructure.DataSourceView view, Id testRecordId) {

        AIConsoleDataStructure.DataSourceTestResult result = new AIConsoleDataStructure.DataSourceTestResult();
        Boolean isSoql = view == null || view.sourceType != AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX;

        if (view != null && view.bindingType == AIConsoleConstants.BINDING_BOUND && testRecordId == null) {
            result.message = 'Pick a test record - bound sources run on the open record.';
            return result;
        }

        Long startedAt = System.currentTimeMillis();

        try {
            List<Object> rows;

            if (isSoql) {
                if (view == null || String.isBlank(view.soqlTemplate)) throw new AIConsoleDataStructure.AIConsoleException('Write the SOQL Template first.');
                String query = capLimit(view.soqlTemplate.trim(), AIConsoleConstants.TEST_ROW_LIMIT);
                rows = AiSoqlTemplateRunner.run(query, bindsFor(query, testRecordId), AccessLevel.USER_MODE);
            } else {
                if (view.id == null) throw new AIConsoleDataStructure.AIConsoleException('Save the data source first - Apex sources are tested through their saved class.');
                rows = AiDataSourceDispatcher.execute(view.id, testRecordId, new Map<String, Object>(), AccessLevel.USER_MODE, null);
            }

            result.durationMs = System.currentTimeMillis() - startedAt;
            result.success = true;
            result.rowCount = rows == null ? 0 : rows.size();
            fillRows(result, rows, view?.targetObject);

        } catch (Exception ex) {
            result.durationMs = System.currentTimeMillis() - startedAt;
            result.success = false;
            result.message = ex.getCause() != null ? ex.getCause().getMessage() : ex.getMessage();
        }

        return result;
    }

    private static void fillRows(AIConsoleDataStructure.DataSourceTestResult result, List<Object> rows, String targetObject) {

        if (rows == null || rows.isEmpty()) {
            result.piiNote = 'No rows returned';
            return;
        }

        List<Map<String, Object>> flatRows = new List<Map<String, Object>>();
        for (Integer index = 0; index < Math.min(rows.size(), AIConsoleConstants.TEST_ROW_LIMIT); index++) {
            Object row = rows[index];
            Map<String, Object> values = row instanceof SObject ? flatten((SObject) row) : (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(row));
            flatRows.add(values);
            for (String key : values.keySet()) {
                if (key != 'attributes' && !result.columns.contains(key)) result.columns.add(key);
            }
        }
        Integer idColumn = result.columns.indexOf('Id');
        if (idColumn >= 0) result.columns.remove(idColumn);

        for (Map<String, Object> values : flatRows) {
            List<String> cells = new List<String>();
            for (String column : result.columns) cells.add(values.get(column) == null ? '' : String.valueOf(values.get(column)));
            result.rows.add(cells);
        }

        Integer piiFields = 0;
        String rowObject = rows[0] instanceof SObject ? ((SObject) rows[0]).getSObjectType().getDescribe().getName() : targetObject;
        for (String column : result.columns) {
            String objectName = column.contains('.') ? null : rowObject;
            if (objectName != null && AIPiiFieldRegistry.isPiiField(objectName, column)) piiFields++;
        }
        result.piiNote = piiFields == 0 ? 'No PII fields in the result' : piiFields + (piiFields == 1 ? ' PII field' : ' PII fields') + ' in the result · masked before the AI sees it';
    }

    // Parent fields come back as Contact.Name - one level deep, which is what the SOQL Builder can pick.
    private static Map<String, Object> flatten(SObject record) {
        Map<String, Object> values = new Map<String, Object>();
        for (String key : record.getPopulatedFieldsAsMap().keySet()) {
            Object value = record.get(key);
            if (value instanceof SObject) {
                SObject parent = (SObject) value;
                for (String parentKey : parent.getPopulatedFieldsAsMap().keySet()) {
                    if (parentKey != 'Id') values.put(key + '.' + parentKey, parent.get(parentKey));
                }
            } else if (!(value instanceof List<SObject>)) {
                values.put(key, value);
            }
        }
        return values;
    }

    // Any LIMIT above the cap comes down to it; no LIMIT gets one.
    public static String capLimit(String query, Integer cap) {
        Matcher matcher = LIMIT_PATTERN.matcher(query);
        if (!matcher.find()) return query + ' LIMIT ' + cap;

        Integer existing = Integer.valueOf(matcher.group().replaceAll('(?i)LIMIT\\s+', ''));
        return existing <= cap ? query : matcher.replaceFirst('LIMIT ' + cap);
    }

    public static Map<String, Object> bindsFor(String query, Id recordId) {
        Map<String, Object> binds = new Map<String, Object>();
        Matcher matcher = BIND_PATTERN.matcher(query);
        while (matcher.find()) binds.put(matcher.group(1), null);
        if (binds.containsKey('recordId')) binds.put('recordId', recordId);
        return binds;
    }

    public static List<String> bindNames(String query) {
        List<String> names = new List<String>();
        Matcher matcher = BIND_PATTERN.matcher(query == null ? '' : query);
        while (matcher.find()) if (!names.contains(matcher.group(1))) names.add(matcher.group(1));
        return names;
    }

    // =============================================================
    // Workflow Actions
    // =============================================================

    public static AIConsoleDataStructure.WorkflowActionView getWorkflowAction(Id actionId) {

        List<AIWorkflowAction__c> actions = [ SELECT Id, Name, ActionName__c, DeveloperName__c, Description__c, ActionType__c, ExecutionType__c, FlowAPIName__c, ApexClassName__c, TargetObject__c, InputSchema__c,
                                                     OutputDescription__c, RequiresConfirmation__c, ConfirmationMessage__c, IsActive__c
                                              FROM AIWorkflowAction__c WHERE Id = :actionId LIMIT 1 ];
        if (actions.isEmpty()) throw new AIConsoleDataStructure.AIConsoleException('That workflow action no longer exists.');

        AIWorkflowAction__c action = actions[0];
        AIConsoleDataStructure.WorkflowActionView view = new AIConsoleDataStructure.WorkflowActionView();
        view.id = action.Id;
        view.name = AIConsoleUtility.workflowActionName(action);
        view.developerName = action.DeveloperName__c;
        view.description = action.Description__c;
        view.actionType = action.ActionType__c;
        view.executionType = action.ExecutionType__c;
        view.flowApiName = action.FlowAPIName__c;
        view.apexClassName = action.ApexClassName__c;
        view.targetObject = action.TargetObject__c;
        view.inputSchema = action.InputSchema__c;
        view.outputDescription = action.OutputDescription__c;
        view.requiresConfirmation = action.RequiresConfirmation__c == true;
        view.confirmationMessage = action.ConfirmationMessage__c;
        view.isActive = action.IsActive__c == true;
        view.previewInputs = previewInputs(action.InputSchema__c);

        for (AIAgentWorkflowAction__c link : [ SELECT AIAgent__c, AIAgent__r.Name FROM AIAgentWorkflowAction__c WHERE AIWorkflowAction__c = :actionId ORDER BY AIAgent__r.Name LIMIT 50 ]) {
            AIConsoleDataStructure.RelatedLine line = new AIConsoleDataStructure.RelatedLine();
            line.id = link.AIAgent__c;
            line.name = link.AIAgent__r.Name;
            view.usedBy.add(line);
        }

        return view;
    }

    public static Id saveWorkflowAction(AIConsoleDataStructure.WorkflowActionView view) {

        if (view == null || String.isBlank(view.name)) throw new AIConsoleDataStructure.AIConsoleException('Action Name is required.');
        if (String.isBlank(view.actionType)) throw new AIConsoleDataStructure.AIConsoleException('Pick a Type.');
        if (String.isBlank(view.executionType)) throw new AIConsoleDataStructure.AIConsoleException('Pick an Execution type.');

        Boolean isFlow = view.actionType == AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW;
        if (isFlow && String.isBlank(view.flowApiName)) throw new AIConsoleDataStructure.AIConsoleException('Flow API Name is required.');
        if (!isFlow && String.isBlank(view.apexClassName)) throw new AIConsoleDataStructure.AIConsoleException('Apex Class Name is required.');
        if (view.requiresConfirmation == true && String.isBlank(view.confirmationMessage)) throw new AIConsoleDataStructure.AIConsoleException('Write the confirmation message users see before it runs.');
        if (String.isNotBlank(view.inputSchema)) {
            try { JSON.deserializeUntyped(view.inputSchema); } catch (Exception ex) { throw new AIConsoleDataStructure.AIConsoleException('Input Schema isn\'t valid JSON.'); }
        }

        AIWorkflowAction__c action = view.id == null ? new AIWorkflowAction__c() : new AIWorkflowAction__c(Id = view.id);
        action.ActionName__c = view.name.trim().left(50);
        action.DeveloperName__c = String.isBlank(view.developerName) ? null : view.developerName.trim().left(75);
        action.Description__c = view.description;
        action.ActionType__c = view.actionType;
        action.ExecutionType__c = view.executionType;
        action.FlowAPIName__c = isFlow ? view.flowApiName.trim() : null;
        action.ApexClassName__c = isFlow ? null : view.apexClassName.trim();
        action.TargetObject__c = view.targetObject;
        action.InputSchema__c = view.inputSchema;
        action.OutputDescription__c = view.outputDescription;
        action.RequiresConfirmation__c = view.requiresConfirmation == true;
        action.ConfirmationMessage__c = view.confirmationMessage;
        action.IsActive__c = view.isActive == true;
        upsert action;

        return action.Id;
    }

    // Input Schema as a JSON Schema ({"properties": {...}}) or a plain {"subject": "string"} map - one preview row per input, with a placeholder value.
    private static List<AIConsoleDataStructure.SummaryItem> previewInputs(String inputSchema) {

        List<AIConsoleDataStructure.SummaryItem> items = new List<AIConsoleDataStructure.SummaryItem>();
        if (String.isBlank(inputSchema)) return items;

        try {
            Map<String, Object> schema = (Map<String, Object>) JSON.deserializeUntyped(inputSchema);
            Map<String, Object> properties = schema.get('properties') instanceof Map<String, Object> ? (Map<String, Object>) schema.get('properties') : schema;

            for (String key : properties.keySet()) {
                String label = humanise(key);
                items.add(new AIConsoleDataStructure.SummaryItem(label, '[' + label + ']'));
            }
        } catch (Exception ex) {
            return items;
        }

        return items;
    }

    // dueDate -> "Due date", follow_up -> "Follow up"
    public static String humanise(String key) {
        String spaced = key.replaceAll('_', ' ').replaceAll('([a-z])([A-Z])', '$1 $2').toLowerCase().trim();
        return spaced.capitalize();
    }
}