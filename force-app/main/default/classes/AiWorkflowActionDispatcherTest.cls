/*
Class Name: AiWorkflowActionDispatcherTest

=================================================================
=================================================================

Description: Testing utility for AiWorkflowActionDispatcher.

=================================================================
=================================================================
Applicable Classes:

AiWorkflowActionDispatcher: Coverage 100%

Version      Date               Author                   Description
1.0          2026-09-21         Chandler Stuart          Initial development
*/

@IsTest private class AiWorkflowActionDispatcherTest {

    // testScenario1: An Apex Workflow Action resolves its ApexClassName__c and returns the IAIWorkflowActionExecutor's result - also proving null inputParameters and no recordId are both handled without error.
    // testScenario2: A null Workflow Action Id, and a Workflow Action Id that doesn't resolve to a record, both throw AIWorkflowActionExecutorException rather than running.
    // testScenario3: An inactive Workflow Action throws AIWorkflowActionExecutorException rather than running.
    // testScenario4: A Workflow Action with no Action Type configured throws AIWorkflowActionExecutorException.
    // testScenario5: An Apex Class Name that doesn't implement IAIWorkflowActionExecutor throws AIWorkflowActionExecutorException.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = true;
        settings.DisableExceptionLogging__c = false;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AiWorkflowActionDispatcherTest.TestExecutor', false)[0];
        action.IsActive__c = true;
        insert action;

        Test.startTest();
            Object result = AiWorkflowActionDispatcher.execute(action.Id, null, null);
        Test.stopTest();

        Assert.areEqual('executed', result, 'Should return the value the test executor returned.');
    }

    @IsTest static void testScenario2() {

        AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AiWorkflowActionDispatcherTest.TestExecutor', false)[0];
        action.IsActive__c = true;
        insert action;
        Id deletedActionId = action.Id;
        delete action;

        Test.startTest();

            try {
                AiWorkflowActionDispatcher.execute(null, null, null);
                Assert.fail('A null Workflow Action Id should have thrown.');
            } catch (AiWorkflowActionDispatcher.AIWorkflowActionExecutorException ex) {
                Assert.isTrue(ex.getMessage().contains('not found'), 'Error should explain the Workflow Action wasn\'t found.');
            }

            try {
                AiWorkflowActionDispatcher.execute(deletedActionId, null, null);
                Assert.fail('A Workflow Action Id with no matching record should have thrown.');
            } catch (AiWorkflowActionDispatcher.AIWorkflowActionExecutorException ex) {
                Assert.isTrue(ex.getMessage().contains('not found'), 'Error should explain the Workflow Action wasn\'t found.');
            }

        Test.stopTest();
    }

    @IsTest static void testScenario3() {

        AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AiWorkflowActionDispatcherTest.TestExecutor', false)[0];
        action.IsActive__c = false; // Explicit - createAIWorkflowActions doesn't set it, and the field's own default is already false.
        insert action;

        Test.startTest();
            try {
                AiWorkflowActionDispatcher.execute(action.Id, null, null);
                Assert.fail('An inactive Workflow Action should have thrown.');
            } catch (AiWorkflowActionDispatcher.AIWorkflowActionExecutorException ex) {
                Assert.isTrue(ex.getMessage().contains('is not active'), 'Error should explain the Workflow Action is inactive.');
            }
        Test.stopTest();
    }

    @IsTest static void testScenario4() {

        AIWorkflowAction__c action = new AIWorkflowAction__c(IsActive__c = true); // No ActionType__c - the field isn't required, so this insert is valid on its own.
        insert action;

        Test.startTest();
            try {
                AiWorkflowActionDispatcher.execute(action.Id, null, null);
                Assert.fail('A Workflow Action with no Action Type configured should have thrown.');
            } catch (AiWorkflowActionDispatcher.AIWorkflowActionExecutorException ex) {
                Assert.isTrue(ex.getMessage().contains('no Action Type configured'), 'Error should explain the Action Type is missing.');
            }
        Test.stopTest();
    }

    @IsTest static void testScenario5() {

        // AIWorkflowActionTriggerHandler validates ApexClassName__c on Apex-type records at insert time, so the app is deactivated to bypass
        // that trigger and get an otherwise-invalid record persisted, mirroring how such a record could already exist in an org.
        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = false;
        update settings;

        AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AIAssistApplicationConstants', false)[0]; // A real, instantiable class that doesn't implement IAIWorkflowActionExecutor.
        action.IsActive__c = true;
        insert action;

        settings.IsApplicationActive__c = true;
        update settings;

        Test.startTest();
            try {
                AiWorkflowActionDispatcher.execute(action.Id, null, null);
                Assert.fail('An Apex Class Name that doesn\'t implement IAIWorkflowActionExecutor should have thrown.');
            } catch (AiWorkflowActionDispatcher.AIWorkflowActionExecutorException ex) {
                Assert.isTrue(ex.getMessage().contains('must implement IAIWorkflowActionExecutor'), 'Error should explain the interface requirement.');
            }
        Test.stopTest();
    }

    // A minimal, real IAIWorkflowActionExecutor implementation - AiWorkflowActionDispatcher resolves Apex Class Names via Type.forName(), so a genuine class is required rather than a mock.
    public class TestExecutor implements IAIWorkflowActionExecutor {
        public Object execute(Id recordId, Map<String, Object> inputParameters) {
            return 'executed';
        }
    }
}