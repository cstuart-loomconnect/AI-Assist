/*
Class Name: AiWorkflowActionDispatcher

=================================================================
=================================================================

Description: Entry point Agent tool-calling invokes to run an AIWorkflowAction__c. The
Workflow Action equivalent of AiDataSourceDispatcher.

Flow:
[1] Load and validate the record.
[2] Apex: Type.forName(ApexClassName__c) -> IAIWorkflowActionExecutor.execute().
[3] Flow: start FlowAPIName__c, read back its "output" variable (a naming convention - Apex
    can't discover a Flow's declared outputs at runtime).

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-21     Chandler Stuart          Initial development
1.1          2026-09-26     Chandler Stuart          Only the execute entry point logs; private run* methods rethrow unlogged. Wrapped exceptions keep the original as their cause.
*/

public without sharing class AiWorkflowActionDispatcher {

    private static final String FLOW_OUTPUT_VARIABLE_NAME = 'output';

    public class AIWorkflowActionExecutorException extends Exception {}

    // Loads and validates the Workflow Action, then runs it. recordId may be null for a Workflow Action that doesn't operate against a specific record.
    public static Object execute(Id workflowActionId, Id recordId, Map<String, Object> inputParameters) {
        try {

            if (workflowActionId == null) throw new AIWorkflowActionExecutorException('AI Workflow Action not found for Id: ' + workflowActionId);

            List<AIWorkflowAction__c> workflowActions = [ SELECT Id, DeveloperName__c, ActionType__c, IsActive__c, ApexClassName__c, FlowAPIName__c, TargetObject__c
                                                            FROM AIWorkflowAction__c
                                                            WHERE Id = :workflowActionId
                                                            WITH USER_MODE
                                                            LIMIT 1 ];

            if (workflowActions.isEmpty()) throw new AIWorkflowActionExecutorException('AI Workflow Action not found for Id: ' + workflowActionId);

            AIWorkflowAction__c workflowAction = workflowActions[0];

            if (!workflowAction.IsActive__c) throw new AIWorkflowActionExecutorException('AI Workflow Action "' + workflowAction.DeveloperName__c + '" is not active.');

            return runWorkflowAction(workflowAction, recordId, inputParameters == null ? new Map<String, Object>() : inputParameters);

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AiWorkflowActionDispatcher', 'execute');
            throw ex instanceof AIWorkflowActionExecutorException ? ex : new AIWorkflowActionExecutorException('Failed to execute AI Workflow Action: ' + ex.getMessage(), ex);
        }
    }

    // Branches on ActionType__c to the matching execution path.
    private static Object runWorkflowAction(AIWorkflowAction__c workflowAction, Id recordId, Map<String, Object> inputParameters) {
        try {

            if (String.isBlank(workflowAction.ActionType__c)) throw new AIWorkflowActionExecutorException('AI Workflow Action "' + workflowAction.DeveloperName__c + '" has no Action Type configured.');

            if (workflowAction.ActionType__c.equalsIgnoreCase(AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX)) { return runApexWorkflowAction(workflowAction, recordId, inputParameters); }
            if (workflowAction.ActionType__c.equalsIgnoreCase(AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW)) { return runFlowWorkflowAction(workflowAction, recordId, inputParameters); }

            throw new AIWorkflowActionExecutorException('Unsupported Action Type "' + workflowAction.ActionType__c + '" for AI Workflow Action "' + workflowAction.DeveloperName__c + '".');

        } catch (Exception ex) {
            throw ex instanceof AIWorkflowActionExecutorException ? ex : new AIWorkflowActionExecutorException('Failed to run AI Workflow Action: ' + ex.getMessage(), ex);
        }
    }

    // IAIWorkflowActionExecutor implementations own their own security context - this class only decides which one to invoke.
    private static Object runApexWorkflowAction(AIWorkflowAction__c workflowAction, Id recordId, Map<String, Object> inputParameters) {
        try {

            if (String.isBlank(workflowAction.ApexClassName__c)) throw new AIWorkflowActionExecutorException('AI Workflow Action "' + workflowAction.DeveloperName__c + '" has no Apex Class Name configured.');

            Type apexType = Type.forName(workflowAction.ApexClassName__c.trim());
            if (apexType == null) throw new AIWorkflowActionExecutorException('Apex Class Name "' + workflowAction.ApexClassName__c + '" could not be found.');

            Object executorInstance = apexType.newInstance();
            if (!(executorInstance instanceof IAIWorkflowActionExecutor)) throw new AIWorkflowActionExecutorException('Apex Class Name "' + workflowAction.ApexClassName__c + '" must implement IAIWorkflowActionExecutor.');

            return ((IAIWorkflowActionExecutor) executorInstance).execute(recordId, inputParameters);

        } catch (Exception ex) {
            throw ex instanceof AIWorkflowActionExecutorException ? ex : new AIWorkflowActionExecutorException('Failed to run Apex AI Workflow Action: ' + ex.getMessage(), ex);
        }
    }

    // Starts the configured Flow with recordId (when present) and inputParameters as its input variables, then reads back its "output" variable by the documented naming convention.
    private static Object runFlowWorkflowAction(AIWorkflowAction__c workflowAction, Id recordId, Map<String, Object> inputParameters) {
        try {

            if (String.isBlank(workflowAction.FlowAPIName__c)) throw new AIWorkflowActionExecutorException('AI Workflow Action "' + workflowAction.DeveloperName__c + '" has no Flow API Name configured.');

            Map<String, Object> flowInputs = new Map<String, Object>(inputParameters);
            if (recordId != null) flowInputs.put('recordId', recordId);

            Flow.Interview interview = Flow.Interview.createInterview(workflowAction.FlowAPIName__c, flowInputs);
            interview.start();

            return interview.getVariableValue(FLOW_OUTPUT_VARIABLE_NAME);

        } catch (Exception ex) {
            throw ex instanceof AIWorkflowActionExecutorException ? ex : new AIWorkflowActionExecutorException('Failed to run Flow AI Workflow Action: ' + ex.getMessage(), ex);
        }
    }

}