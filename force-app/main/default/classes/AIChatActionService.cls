/*
Class Name: AIChatActionService

=================================================================
=================================================================

Description: Suggested Workflow Action card data - the SuggestedAction shown under an AI reply
(toSuggestedAction) and its editable fields, parsed from AIWorkflowAction__c.InputSchema__c
(parseInputSchema). Also runs the action the user clicked (run): resolves the AIWorkflowAction__c
suggested on that reply, executes it through AiWorkflowActionDispatcher, and records the run as an
AIExecutionStep__c on the reply so a reload shows it as already run.

The permission re-check (are Suggested Actions turned on at all, for this user) happens in
AIChatController before run() is called, since it needs the UiSettings/UserState AIChatStateService
already built for the request - this class only concerns itself with the one action being run.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-28     Chandler Stuart          Split out of AIChatController.
*/

public with sharing class AIChatActionService {

    // Runs the Workflow Action suggested on message, when the user clicks it. Only the action actually suggested on that message can run. The run is recorded as an AIExecutionStep__c on the reply.
    public static AIChatDataStructure.ActionResult run(AIConversationMessage__c message, String inputsJson) {

        Id workflowActionId = AIChatDataStructure.toIdOrNull(message.SuggestedWorkflowActionId__c);
        if (workflowActionId == null) throw new AIChatDataStructure.AIChatControllerException('There is no suggested action on this reply.');

        Map<String, Object> inputs = String.isBlank(inputsJson) ? new Map<String, Object>() : (Map<String, Object>) JSON.deserializeUntyped(inputsJson);
        Id relatedRecordId = AIChatDataStructure.toIdOrNull(message.AIConversation__r.RelatedRecordId__c);

        AIChatDataStructure.ActionResult result = new AIChatDataStructure.ActionResult();

        try {
            Object output = AiWorkflowActionDispatcher.execute(workflowActionId, relatedRecordId, inputs);
            result.isSuccess = true;
            result.message = output instanceof String && String.isNotBlank((String) output) ? (String) output : 'Done.';
        } catch (AiWorkflowActionDispatcher.AIWorkflowActionExecutorException actionFailure) {
            // Already logged by the dispatcher - the detail can name classes and Flows, so the user gets a plain message.
            result.isSuccess = false;
            result.message = 'That action couldn\'t be completed. Nothing was changed by AI Assist.';
        }

        recordActionStep(message, workflowActionId, result.isSuccess);

        return result;
    }

    // An audit row on the reply the action was suggested on - also how the window knows, after a reload, that the action already ran.
    private static void recordActionStep(AIConversationMessage__c message, Id workflowActionId, Boolean isSuccess) {

        AggregateResult[] highestStep = [ SELECT MAX(StepOrder__c) highestOrder FROM AIExecutionStep__c WHERE AIConversationMessage__c = :message.Id ];
        Decimal highestOrder = highestStep.isEmpty() || highestStep[0].get('highestOrder') == null ? 0 : (Decimal) highestStep[0].get('highestOrder');

        insert new AIExecutionStep__c(
            AIConversationMessage__c = message.Id,
            AIWorkflowAction__c = workflowActionId,
            StepOrder__c = highestOrder + 1,
            Status__c = isSuccess ? AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS : AIAssistApplicationConstants.EXECUTION_STEP_STATUS_FAILED,
            StepDetail__c = (isSuccess ? 'Suggested action run by ' : 'Suggested action failed for ') + UserInfo.getName()
        );
    }

    public static AIChatDataStructure.SuggestedAction toSuggestedAction(AIWorkflowAction__c workflowAction) {

        AIChatDataStructure.SuggestedAction action = new AIChatDataStructure.SuggestedAction();
        action.id = workflowAction.Id;
        action.name = String.isBlank(workflowAction.ActionName__c) ? 'Run action' : workflowAction.ActionName__c;
        action.description = workflowAction.Description__c;
        action.requiresConfirmation = workflowAction.RequiresConfirmation__c;
        action.confirmationMessage = workflowAction.ConfirmationMessage__c;
        action.inputFields = parseInputSchema(workflowAction.InputSchema__c);

        return action;
    }

    // InputSchema__c is a JSON Schema object ({"properties": {...}, "required": [...]}) - each property becomes one field on "Edit first". A malformed schema just means no editable fields.
    @TestVisible private static List<AIChatDataStructure.ActionInputField> parseInputSchema(String inputSchema) {

        List<AIChatDataStructure.ActionInputField> fields = new List<AIChatDataStructure.ActionInputField>();
        if (String.isBlank(inputSchema)) return fields;

        try {

            Map<String, Object> schema = (Map<String, Object>) JSON.deserializeUntyped(inputSchema);
            Map<String, Object> properties = (Map<String, Object>) schema.get('properties');
            if (properties == null) return fields;

            Set<String> requiredNames = new Set<String>();
            if (schema.get('required') instanceof List<Object>) {
                for (Object requiredName : (List<Object>) schema.get('required')) requiredNames.add(String.valueOf(requiredName));
            }

            for (String propertyName : properties.keySet()) {

                Map<String, Object> property = (Map<String, Object>) properties.get(propertyName);
                String jsonType = property.get('type') == null ? 'string' : String.valueOf(property.get('type'));
                String format = property.get('format') == null ? null : String.valueOf(property.get('format'));

                AIChatDataStructure.ActionInputField field = new AIChatDataStructure.ActionInputField();
                field.name = propertyName;
                field.label = property.get('title') == null ? AIChatDataStructure.humanise(propertyName) : String.valueOf(property.get('title'));
                field.helpText = property.get('description') == null ? null : String.valueOf(property.get('description'));
                field.required = requiredNames.contains(propertyName);

                if (jsonType == 'integer' || jsonType == 'number') field.inputType = 'number';
                else if (jsonType == 'boolean') field.inputType = 'checkbox';
                else if (format == 'date') field.inputType = 'date';
                else if (format == 'date-time') field.inputType = 'datetime';
                else if (property.get('maxLength') != null && Integer.valueOf(property.get('maxLength')) > 255) field.inputType = 'textarea';
                else field.inputType = 'text';

                fields.add(field);
            }

        } catch (Exception malformedSchema) {
            return new List<AIChatDataStructure.ActionInputField>();
        }

        return fields;
    }
}