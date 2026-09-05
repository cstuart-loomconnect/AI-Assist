/*
Class Name: AIDataSourceTriggerHandler

=================================================================
=================================================================

Description: Handler for managing AI Data Source events related to AI Assist. Generates
PublicId__c when blank, and, when SourceType__c is Apex, validates that ApexClassName__c
names a class implementing the IAIDataSourceExecutor interface.

=================================================================
=================================================================

Version      Date            Author                   Description
1.0          2026-09-05      Chandler Stuart          Initial development
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
                    if (dataSource.SourceType__c == AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX) { apexDataSources.add(dataSource); }
                }

                if (!apexDataSources.isEmpty()) { validateApexClassImplementsExecutor(apexDataSources); }

            }

        } catch (AIDataSourceValidationException e) {
            throw e; // Re-throw so the save is blocked and the user sees the validation failure.
        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIDataSourceTriggerHandler', 'handleBeforeInsert');
        }
    }

    public static void handleBeforeUpdate(Map<Id, AIDataSource__c> oldDataSourcesById, Map<Id, AIDataSource__c> newDataSourcesById) {
        try {

            if (!isBeforeUpdateHandlerRunning) {

                isBeforeUpdateHandlerRunning = true;

                if (newDataSourcesById == null || newDataSourcesById.isEmpty() || oldDataSourcesById == null) return;

                AIAssistGlobalUtility.generatePublicId(newDataSourcesById.values());

                List<AIDataSource__c> apexDataSourcesToValidate = new List<AIDataSource__c>(); // Records where Source Type is Apex and either Source Type or Apex Class Name changed.

                for (AIDataSource__c newDataSource : newDataSourcesById.values()) {

                    AIDataSource__c oldDataSource = oldDataSourcesById.get(newDataSource.Id);
                    if (oldDataSource == null) continue;

                    if (newDataSource.SourceType__c != AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX) continue;
                    if (oldDataSource.SourceType__c == newDataSource.SourceType__c && oldDataSource.ApexClassName__c == newDataSource.ApexClassName__c) continue; // Neither field changed, no need to re-validate.

                    apexDataSourcesToValidate.add(newDataSource);

                }

                if (!apexDataSourcesToValidate.isEmpty()) { validateApexClassImplementsExecutor(apexDataSourcesToValidate); }

            }

        } catch (AIDataSourceValidationException e) {
            throw e; // Re-throw so the save is blocked and the user sees the validation failure.
        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIDataSourceTriggerHandler', 'handleBeforeUpdate');
        }
    }

    // Throws AIDataSourceValidationException for any record whose ApexClassName__c doesn't resolve to a class implementing IAIDataSourceExecutor. Callers must only pass records where Source Type is Apex.
    private static void validateApexClassImplementsExecutor(List<AIDataSource__c> dataSources) {

        for (AIDataSource__c dataSource : dataSources) {

            if (String.isBlank(dataSource.ApexClassName__c)) continue;

            Type apexType = Type.forName(dataSource.ApexClassName__c);

            if (apexType == null) {
                throw new AIDataSourceValidationException('Apex Class Name "' + dataSource.ApexClassName__c + '" could not be found.');
            }

            Object instance;
            try {
                instance = apexType.newInstance();
            } catch (Exception e) {
                throw new AIDataSourceValidationException('Apex Class Name "' + dataSource.ApexClassName__c + '" could not be instantiated. It must be a public, no-argument constructable class.');
            }

            if (!(instance instanceof IAIDataSourceExecutor)) {
                throw new AIDataSourceValidationException('Apex Class Name "' + dataSource.ApexClassName__c + '" must implement the IAIDataSourceExecutor interface.');
            }

        }
    }
}