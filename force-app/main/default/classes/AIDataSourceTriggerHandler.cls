/*
Class Name: AIDataSourceTriggerHandler

=================================================================
=================================================================

Description: Handler for managing AI Data Source events related to AI Assist, performing
the business logic that runs on the AI Data Source trigger.

=================================================================
=================================================================

Version      Date               Author                   Description
1.0          2026-09-09         Chandler Stuart          Initial development
1.1          2026-09-27         Chandler Stuart          Validates InputSchema__c is a JSON object on save - AIAgentManager advertises it to the model as-is, and a bad schema would fail every turn for the agent.
1.2          2026-09-27         Chandler Stuart          Validates DeveloperName__c is a valid AI provider tool name.
*/

public without sharing class AIDataSourceTriggerHandler {

    private static Boolean isBeforeInsertHandlerRunning = false;
    private static Boolean isBeforeUpdateHandlerRunning = false;

    public static void handleBeforeInsert(List<AIDataSource__c> newDataSources) {
        try {

            if (isBeforeInsertHandlerRunning) return;
            isBeforeInsertHandlerRunning = true;

            AIAssistGlobalUtility.generatePublicId(newDataSources);

            List<AIDataSource__c> apexDataSources = new List<AIDataSource__c>(); // Records where Source Type is Apex and need their Apex Class Name validated.
            List<AIDataSource__c> inputSchemasToValidate = new List<AIDataSource__c>(); // Records with an Input Schema populated.
            List<AIDataSource__c> developerNamesToValidate = new List<AIDataSource__c>(); // Records with a Developer Name populated.

            for (AIDataSource__c dataSource : newDataSources) {
                if (String.isNotBlank(dataSource.SourceType__c) && dataSource.SourceType__c.equalsIgnoreCase(AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX)) {
                    apexDataSources.add(dataSource);
                }
                if (String.isNotBlank(dataSource.InputSchema__c)) inputSchemasToValidate.add(dataSource);
                if (String.isNotBlank(dataSource.DeveloperName__c)) developerNamesToValidate.add(dataSource);
            }

            if (!apexDataSources.isEmpty()) { validateApexClassImplementsExecutor(apexDataSources); }
            if (!inputSchemasToValidate.isEmpty()) { validateInputSchemaIsJsonObject(inputSchemasToValidate); }
            if (!developerNamesToValidate.isEmpty()) { validateDeveloperNameIsValidToolName(developerNamesToValidate); }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIDataSourceTriggerHandler', 'handleBeforeInsert');
        }
    }

    public static void handleBeforeUpdate(Map<Id, AIDataSource__c> oldDataSourcesById, Map<Id, AIDataSource__c> newDataSourcesById) {
        try {

            if (isBeforeUpdateHandlerRunning) return;
            isBeforeUpdateHandlerRunning = true;

            if (newDataSourcesById == null || newDataSourcesById.isEmpty() || oldDataSourcesById == null) return;

            List<AIDataSource__c> apexDataSourcesToValidate = new List<AIDataSource__c>(); // Records where Source Type is Apex and either Source Type or Apex Class Name changed.
            List<AIDataSource__c> inputSchemasToValidate = new List<AIDataSource__c>(); // Records whose Input Schema changed and is populated.
            List<AIDataSource__c> developerNamesToValidate = new List<AIDataSource__c>(); // Records whose Developer Name changed and is populated.

            for (AIDataSource__c newDataSource : newDataSourcesById.values()) {

                AIDataSource__c oldDataSource = oldDataSourcesById.get(newDataSource.Id);
                if (oldDataSource == null) continue;

                if (String.isNotBlank(newDataSource.InputSchema__c) && oldDataSource.InputSchema__c != newDataSource.InputSchema__c) inputSchemasToValidate.add(newDataSource);
                if (String.isNotBlank(newDataSource.DeveloperName__c) && oldDataSource.DeveloperName__c != newDataSource.DeveloperName__c) developerNamesToValidate.add(newDataSource);

                if (String.isBlank(newDataSource.SourceType__c) || !newDataSource.SourceType__c.equalsIgnoreCase(AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX)) continue;
                if (oldDataSource.SourceType__c == newDataSource.SourceType__c && oldDataSource.ApexClassName__c == newDataSource.ApexClassName__c) continue; // Neither field changed, no need to re-validate.

                apexDataSourcesToValidate.add(newDataSource);

            }

            if (!apexDataSourcesToValidate.isEmpty()) { validateApexClassImplementsExecutor(apexDataSourcesToValidate); }
            if (!inputSchemasToValidate.isEmpty()) { validateInputSchemaIsJsonObject(inputSchemasToValidate); }
            if (!developerNamesToValidate.isEmpty()) { validateDeveloperNameIsValidToolName(developerNamesToValidate); }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIDataSourceTriggerHandler', 'handleBeforeUpdate');
        }
    }

    // Adds a validation error to any record whose ApexClassName__c doesn't resolve to a class implementing IAIDataSourceExecutor. Callers must only pass records where Source Type is Apex. Class names are validated once per distinct value to avoid repeating Type.forName/instantiation for records sharing the same Apex Class Name.
    private static void validateApexClassImplementsExecutor(List<AIDataSource__c> dataSources) {
        try {

            if (dataSources == null || dataSources.isEmpty()) return;

            Map<String, String> classNameToErrorMessage = new Map<String, String>();

            for (AIDataSource__c dataSource : dataSources) {

                if (String.isBlank(dataSource.ApexClassName__c)) continue;

                String className = dataSource.ApexClassName__c.trim();

                if (!classNameToErrorMessage.containsKey(className)) {

                    String errorMessage;
                    Type apexType = Type.forName(className);

                    if (apexType == null) {
                        errorMessage = 'Apex Class Name "' + className + '" could not be found.';
                    } else {
                        try {
                            Object instance = apexType.newInstance();
                            if (!(instance instanceof IAIDataSourceExecutor)) { errorMessage = 'Apex Class Name "' + className + '" must implement the IAIDataSourceExecutor interface.'; }
                        } catch (Exception e) {
                            errorMessage = 'Apex Class Name "' + className + '" could not be instantiated. It must be a public, no-argument constructable class.';
                        }
                    }

                    classNameToErrorMessage.put(className, errorMessage);
                }

                String errorMessage = classNameToErrorMessage.get(className);
                if (errorMessage != null) { dataSource.ApexClassName__c.addError(errorMessage); }

            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIDataSourceTriggerHandler', 'validateApexClassImplementsExecutor');
        }
    }

    // Adds a validation error to any record whose InputSchema__c isn't a JSON object (e.g. {"type": "object", "properties": {...}}). Blank is allowed - AIAgentManager then advertises an empty object schema.
    // Invalid JSON and a JSON array are both rejected here, at save time, because AIAgentManager parses this for every turn and a bad value would fail every turn for the agent.
    private static void validateInputSchemaIsJsonObject(List<AIDataSource__c> dataSources) {
        try {

            if (dataSources == null || dataSources.isEmpty()) return;

            for (AIDataSource__c dataSource : dataSources) {

                if (String.isBlank(dataSource.InputSchema__c)) continue;

                Object parsedSchema;
                try {
                    parsedSchema = JSON.deserializeUntyped(dataSource.InputSchema__c);
                } catch (JSONException invalidJson) {
                    dataSource.InputSchema__c.addError('Input Schema must be valid JSON: ' + invalidJson.getMessage());
                    continue;
                }

                if (!(parsedSchema instanceof Map<String, Object>)) {
                    dataSource.InputSchema__c.addError('Input Schema must be a JSON object, e.g. {"type": "object", "properties": {}}.');
                }
            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIDataSourceTriggerHandler', 'validateInputSchemaIsJsonObject');
        }
    }

    // Adds a validation error to any record whose DeveloperName__c isn't a valid AI provider tool name - AIAgentManager sends it to the model as the tool's name, and both Anthropic and OpenAI reject anything other than letters, numbers, underscores and hyphens (1-64 characters). One bad name would fail every turn for every agent using the Data Source.
    // Blank is allowed - AIAgentManager doesn't offer a Data Source with no Developer Name as a tool.
    private static void validateDeveloperNameIsValidToolName(List<AIDataSource__c> dataSources) {
        try {

            if (dataSources == null || dataSources.isEmpty()) return;

            for (AIDataSource__c dataSource : dataSources) {

                if (String.isBlank(dataSource.DeveloperName__c)) continue;

                if (!Pattern.matches(AIAssistApplicationConstants.AI_PROVIDER_TOOL_NAME_PATTERN, dataSource.DeveloperName__c)) {
                    dataSource.DeveloperName__c.addError('Developer Name can only contain letters, numbers, underscores and hyphens, and must be 64 characters or fewer - it is sent to the AI provider as the tool name.');
                }
            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIDataSourceTriggerHandler', 'validateDeveloperNameIsValidToolName');
        }
    }
}