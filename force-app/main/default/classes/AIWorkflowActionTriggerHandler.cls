/*
Class Name: AIWorkflowActionTriggerHandler

=================================================================
=================================================================

Description: Handler for managing AI Workflow Action events related to AI Assist,
performing the business logic that runs on the AI Workflow Action trigger.

=================================================================
=================================================================

Version      Date               Author                   Description
1.0          2026-09-06         Chandler Stuart          Initial development
*/

public without sharing class AIWorkflowActionTriggerHandler {

    private static Boolean isBeforeInsertHandlerRunning = false;
    private static Boolean isBeforeUpdateHandlerRunning = false;

    public static void handleBeforeInsert(List<AIWorkflowAction__c> newActions) {
        try {

            if (isBeforeInsertHandlerRunning) return;
            isBeforeInsertHandlerRunning = true;

            AIAssistGlobalUtility.generatePublicId(newActions);

            List<AIWorkflowAction__c> apexActions = new List<AIWorkflowAction__c>(); // Records where Action Type is Apex and need their Apex Class Name validated.

            for (AIWorkflowAction__c action : newActions) {
                if (action.ActionType__c == AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX) { apexActions.add(action); }
            }

            if (!apexActions.isEmpty()) { validateApexClassImplementsExecutor(apexActions); }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIWorkflowActionTriggerHandler', 'handleBeforeInsert');
        }
    }

    public static void handleBeforeUpdate(Map<Id, AIWorkflowAction__c> oldActionsById, Map<Id, AIWorkflowAction__c> newActionsById) {
        try {

            if (isBeforeUpdateHandlerRunning) return;
            isBeforeUpdateHandlerRunning = true;

            if (newActionsById == null || newActionsById.isEmpty() || oldActionsById == null) return;

            List<AIWorkflowAction__c> apexActionsToValidate = new List<AIWorkflowAction__c>(); // Records where Action Type is Apex and either Action Type or Apex Class Name changed.

            for (AIWorkflowAction__c newAction : newActionsById.values()) {

                AIWorkflowAction__c oldAction = oldActionsById.get(newAction.Id);
                if (oldAction == null) continue;

                if (newAction.ActionType__c != AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX) continue;
                if (oldAction.ActionType__c == newAction.ActionType__c && oldAction.ApexClassName__c == newAction.ApexClassName__c) continue; // Neither field changed, no need to re-validate.

                apexActionsToValidate.add(newAction);

            }

            if (!apexActionsToValidate.isEmpty()) { validateApexClassImplementsExecutor(apexActionsToValidate); }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIWorkflowActionTriggerHandler', 'handleBeforeUpdate');
        }
    }

    // Adds a validation error to any record whose ApexClassName__c doesn't resolve to a class implementing IAIWorkflowActionExecutor. Callers must only pass records where Action Type is Apex.
    private static void validateApexClassImplementsExecutor(List<AIWorkflowAction__c> actions) {
        try {

            for (AIWorkflowAction__c action : actions) {

                if (!String.isNotBlank(action.ApexClassName__c)) continue;

                Type apexType = Type.forName(action.ApexClassName__c);

                if (apexType == null) {
                    action.ApexClassName__c.addError('Apex Class Name "' + action.ApexClassName__c + '" could not be found.');
                    continue;
                }

                Object instance;
                try {
                    instance = apexType.newInstance();
                } catch (Exception e) {
                    action.ApexClassName__c.addError('Apex Class Name "' + action.ApexClassName__c + '" could not be instantiated. It must be a public, no-argument constructable class.');
                    continue;
                }

                if (!(instance instanceof IAIWorkflowActionExecutor)) {
                    action.ApexClassName__c.addError('Apex Class Name "' + action.ApexClassName__c + '" must implement the IAIWorkflowActionExecutor interface.');
                }

            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIWorkflowActionTriggerHandler', 'validateApexClassImplementsExecutor');
        }
    }
}