/*
Class Name: AIDataSourceTriggerHandler

=================================================================
=================================================================

Description: Handler for managing AI Data Source events related to AI Assist, performing
the business logic that runs on the AI Data Source trigger.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIDataSourceTriggerHandler {

    private static Boolean isBeforeInsertHandlerRunning = false;
    private static Boolean isBeforeUpdateHandlerRunning = false;

    public static void handleBeforeInsert(List<AIDataSource__c> newDataSources) {
        try {

            if (!isBeforeInsertHandlerRunning) {

                isBeforeInsertHandlerRunning = true;

                AIAssistGlobalUtility.generatePublicId(newDataSources);

                List<AIDataSource__c> apexDataSources = new List<AIDataSource__c>(); // Records where Source Type is Apex and need their Apex Class Name validated.

                for (AIDataSource__c dataSource : newDataSources) {
                    if (String.isNotBlank(dataSource.SourceType__c) && dataSource.SourceType__c.equalsIgnoreCase(AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX)) { 
                        apexDataSources.add(dataSource); 
                    }
                }

                if (!apexDataSources.isEmpty()) { validateApexClassImplementsExecutor(apexDataSources); }

            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIDataSourceTriggerHandler', 'handleBeforeInsert');
        }
    }

    public static void handleBeforeUpdate(Map<Id, AIDataSource__c> oldDataSourcesById, Map<Id, AIDataSource__c> newDataSourcesById) {
        try {

            if (!isBeforeUpdateHandlerRunning) {

                isBeforeUpdateHandlerRunning = true;

                if (newDataSourcesById == null || newDataSourcesById.isEmpty() || oldDataSourcesById == null) return;

                List<AIDataSource__c> apexDataSourcesToValidate = new List<AIDataSource__c>(); // Records where Source Type is Apex and either Source Type or Apex Class Name changed.

                for (AIDataSource__c newDataSource : newDataSourcesById.values()) {

                    AIDataSource__c oldDataSource = oldDataSourcesById.get(newDataSource.Id);
                    if (oldDataSource == null) continue;

                    if (String.isBlank(newDataSource.SourceType__c) || newDataSource.SourceType__c.equalsIgnoreCase(AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX)) continue;
                    if (oldDataSource.SourceType__c.equalsIgnoreCase(newDataSource.SourceType__c) && oldDataSource.ApexClassName__c.equalsIgnoreCase(newDataSource.ApexClassName__c)) continue; // Neither field changed, no need to re-validate.

                    apexDataSourcesToValidate.add(newDataSource);

                }

                if (!apexDataSourcesToValidate.isEmpty()) { validateApexClassImplementsExecutor(apexDataSourcesToValidate); }

            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIDataSourceTriggerHandler', 'handleBeforeUpdate');
        }
    }

    private static void validateApexClassImplementsExecutor(List<AIDataSource__c> dataSources) {

        if (dataSources == null || dataSources.isEmpty()) return;

        Set<String> validatedClassNames = new Set<String>();
        Map<String, String> classNameToErrorMessage = new Map<String, String>();

        for (AIDataSource__c dataSource : dataSources) {

            try {

                String className = dataSource.ApexClassName__c.trim();

                if (String.isBlank(className)) continue;

                if (!validatedClassNames.contains(className)) {

                    String errorMessage;
                    Type apexType = Type.forName(className);

                    if (apexType == null) {
                        errorMessage = 'Apex Class Name "' + className + '" could not be found.';
                    } else {
                        Object instance;
                        try {
                            instance = apexType.newInstance();
                            if (!(instance instanceof IAIDataSourceExecutor)) { errorMessage = 'Apex Class Name "' + className + '" must implement the IAIDataSourceExecutor interface.'; }
                        } catch (Exception e) {
                            errorMessage = 'Apex Class Name "' + className + '" could not be instantiated. It must be a public, no-argument constructable class.';
                        }
                    }

                    if (errorMessage != null) classNameToErrorMessage.put(className, errorMessage);

                    validatedClassNames.add(className);
                }

                if (classNameToErrorMessage.containsKey(className)) {
                    dataSource.ApexClassName__c.addError(classNameToErrorMessage.get(className));
                }

            } catch (Exception e) {
                // Isolate failure to this record only; continue validating the rest.
                AIPlatformLogManager.logException(e, 'AIDataSourceTriggerHandler', 'validateApexClassImplementsExecutor');
                dataSource.ApexClassName__c.addError('An unexpected error occurred while validating the Apex Class Name. Please contact your administrator.');
            }
        }
    }
}