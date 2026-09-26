/*
Class Name: AiDataSourceDispatcher

=================================================================
=================================================================

Description: Entry point Agent tool-calling invokes to run an AIDataSource__c and get back
its masked result. Routes to AiSoqlTemplateRunner or an IAIDataSourceExecutor based on
SourceType__c, then hands the raw result - along with the current conversation's Id, so PII
masking is recorded against the right conversation - to AiDataSourceResultProcessor. The
only class of the three that knows about the AIDataSource__c object itself.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-21     Chandler Stuart          Initial development
1.1          2026-09-26     Chandler Stuart          Catches rethrow without logging - AIAgentManager.invokeTool logs the failure once. Wrapped exceptions keep the original as their cause.
*/

public without sharing class AiDataSourceDispatcher {

    public class AIDataSourceExecutorException extends Exception {}

    // Loads and validates the Data Source, runs it under the given AccessLevel (defaults to USER_MODE), and returns the masked result. recordId may be null for an Unbound Data Source.
    public static List<Object> execute(Id dataSourceId, Id recordId, Map<String, Object> inputParameters, AccessLevel accessLevel, Id conversationId) {
        try {

            if (dataSourceId == null) throw new AIDataSourceExecutorException('AI Data Source not found for Id: ' + dataSourceId);

            AccessLevel effectiveAccessLevel = accessLevel == null ? System.AccessLevel.USER_MODE : accessLevel;

            // Looks up the Data Source record by Id, respecting the running user's access to the config object itself.
            List<AIDataSource__c> dataSources = [ SELECT Id, DeveloperName__c, SourceType__c, IsActive__c, SOQLTemplate__c, ApexClassName__c, TargetObject__c
                                                   FROM AIDataSource__c
                                                   WHERE Id = :dataSourceId
                                                   WITH USER_MODE
                                                   LIMIT 1 ];

            if (dataSources.isEmpty()) throw new AIDataSourceExecutorException('AI Data Source not found for Id: ' + dataSourceId);

            AIDataSource__c dataSource = dataSources[0];

            if (!dataSource.IsActive__c) throw new AIDataSourceExecutorException('AI Data Source "' + dataSource.DeveloperName__c + '" is not active.');

            List<SObject> rawResults = runDataSource(dataSource, recordId, inputParameters == null ? new Map<String, Object>() : inputParameters, effectiveAccessLevel);

            // AiDataSourceResultProcessor masks PII values through a static seam rather than a process() parameter, so the conversation it should record masked pairings against must be set immediately before calling it.
            AiDataSourceResultProcessor.setCurrentConversationId(conversationId);

            return AiDataSourceResultProcessor.process(rawResults, effectiveAccessLevel);

        } catch (Exception ex) {
            throw ex instanceof AIDataSourceExecutorException ? ex : new AIDataSourceExecutorException('Failed to execute AI Data Source: ' + ex.getMessage(), ex);
        }
    }

    // Branches on SourceType__c to the matching retrieval path.
    private static List<SObject> runDataSource(AIDataSource__c dataSource, Id recordId, Map<String, Object> inputParameters, AccessLevel accessLevel) {
        try {

            if (dataSource == null) throw new AIDataSourceExecutorException('AI Data Source is required.');
            if (String.isBlank(dataSource.SourceType__c)) throw new AIDataSourceExecutorException('AI Data Source "' + dataSource.DeveloperName__c + '" has no Source Type configured.');

            if (dataSource.SourceType__c.equalsIgnoreCase(AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL)) { return runSoqlDataSource(dataSource, recordId, inputParameters, accessLevel); }
            if (dataSource.SourceType__c.equalsIgnoreCase(AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX)) { return runApexDataSource(dataSource, recordId, inputParameters); }

            throw new AIDataSourceExecutorException('Unsupported Source Type "' + dataSource.SourceType__c + '" for AI Data Source "' + dataSource.DeveloperName__c + '".');

        } catch (Exception ex) {
            throw ex instanceof AIDataSourceExecutorException ? ex : new AIDataSourceExecutorException('Failed to run AI Data Source: ' + ex.getMessage(), ex);
        }
    }

    // Builds the bind Map (adding recordId when present) and delegates to AiSoqlTemplateRunner.
    private static List<SObject> runSoqlDataSource(AIDataSource__c dataSource, Id recordId, Map<String, Object> inputParameters, AccessLevel accessLevel) {
        try {

            if (dataSource == null) throw new AIDataSourceExecutorException('AI Data Source is required.');
            if (String.isBlank(dataSource.SOQLTemplate__c)) throw new AIDataSourceExecutorException('AI Data Source "' + dataSource.DeveloperName__c + '" has no SOQL Template configured.');

            Map<String, Object> bindValues = inputParameters == null ? new Map<String, Object>() : new Map<String, Object>(inputParameters);
            if (recordId != null) bindValues.put('recordId', recordId);

            return AiSoqlTemplateRunner.run(dataSource.SOQLTemplate__c, bindValues, accessLevel);

        } catch (Exception ex) {
            throw ex instanceof AIDataSourceExecutorException ? ex : new AIDataSourceExecutorException('Failed to run SOQL AI Data Source: ' + ex.getMessage(), ex);
        }
    }

    // IAIDataSourceExecutor implementations own their own security context - this class only decides which one to invoke.
    private static List<SObject> runApexDataSource(AIDataSource__c dataSource, Id recordId, Map<String, Object> inputParameters) {
        try {

            if (dataSource == null) throw new AIDataSourceExecutorException('AI Data Source is required.');
            if (String.isBlank(dataSource.ApexClassName__c)) throw new AIDataSourceExecutorException('AI Data Source "' + dataSource.DeveloperName__c + '" has no Apex Class Name configured.');

            Type apexType = Type.forName(dataSource.ApexClassName__c.trim());
            if (apexType == null) throw new AIDataSourceExecutorException('Apex Class Name "' + dataSource.ApexClassName__c + '" could not be found.');

            Object executorInstance = apexType.newInstance();
            if (!(executorInstance instanceof IAIDataSourceExecutor)) throw new AIDataSourceExecutorException('Apex Class Name "' + dataSource.ApexClassName__c + '" must implement IAIDataSourceExecutor.');

            return ((IAIDataSourceExecutor) executorInstance).execute(recordId, inputParameters == null ? new Map<String, Object>() : inputParameters);

        } catch (Exception ex) {
            throw ex instanceof AIDataSourceExecutorException ? ex : new AIDataSourceExecutorException('Failed to run Apex AI Data Source: ' + ex.getMessage(), ex);
        }
    }

}