/*
Class Name: IAIWorkflowActionExecutor

=================================================================
=================================================================

Description: Contract for the Apex class referenced by AIWorkflowAction__c.ApexClassName__c
when ActionType__c is Apex. Implementing classes perform the action and return its result.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public interface IAIWorkflowActionExecutor {

    Object execute(Id recordId, Map<String, Object> inputParameters);

}