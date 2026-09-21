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

            for (AIDataSource__c dataSource : newDataSources) {
                if (String.isNotBlank(dataSource.SourceType__c) && dataSource.SourceType__c.equalsIgnoreCase(AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX)) {
                    apexDataSources.add(dataSource);
                }
            }

            if (!apexDataSources.isEmpty()) { validateApexClassImplementsExecutor(apexDataSources); }

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

            for (AIDataSource__c newDataSource : newDataSourcesById.values()) {

                AIDataSource__c oldDataSource = oldDataSourcesById.get(newDataSource.Id);
                if (oldDataSource == null) continue;

                if (String.isBlank(newDataSource.SourceType__c) || !newDataSource.SourceType__c.equalsIgnoreCase(AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX)) continue;
                if (oldDataSource.SourceType__c == newDataSource.SourceType__c && oldDataSource.ApexClassName__c == newDataSource.ApexClassName__c) continue; // Neither field changed, no need to re-validate.

                apexDataSourcesToValidate.add(newDataSource);

            }

            if (!apexDataSourcesToValidate.isEmpty()) { validateApexClassImplementsExecutor(apexDataSourcesToValidate); }

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
}