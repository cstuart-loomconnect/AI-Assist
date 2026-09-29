/*
Class Name: AIWorkflowActionTriggerTest

=================================================================
=================================================================

Description: Testing utility for the AI Workflow Action Trigger.

=================================================================
=================================================================
Applicable Classes:

AIWorkflowActionTrigger: Coverage 100%
AIWorkflowActionTriggerHandler: Coverage 88%

Version      Date               Author                   Description
1.0          2026-09-10         Chandler Stuart          Initial development
*/

@IsTest private class AIWorkflowActionTriggerTest {

    // testScenario1: Bulk inserting Flow-type AIWorkflowAction__c records generates each record's PublicId__c and inserts cleanly, since Apex Class Name validation only applies to Apex-type records.
    // testScenario2: Inserting a Workflow Action with a non-existent Apex Class Name raises a validation error on ApexClassName__c and rolls back the insert.
    // testScenario3: Inserting Workflow Actions whose Apex Class Name doesn't implement IAIWorkflowActionExecutor raises a validation error and rolls back the insert - including when two records share the same invalid class name.
    // testScenario4: Inserting a Workflow Action with an uninstantiable Apex Class Name raises a validation error and rolls back the insert.
    // testScenario5: Updating an AIWorkflowAction__c's Action Type to Apex with an Apex Class Name that doesn't implement IAIWorkflowActionExecutor raises a validation error on update.
    // testScenario6: Updating an unrelated field on an Apex-type AIWorkflowAction__c, leaving Action Type and Apex Class Name unchanged, does not re-run Apex Class Name validation.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        List<AIWorkflowAction__c> flowActions = AIAssistTestDataFactory.createAIWorkflowActions(2, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW, 'AIWorkflowActionTriggerTest_Flow', false);

        Test.startTest();
            insert flowActions;
        Test.stopTest();

        List<AIWorkflowAction__c> inserted = [SELECT PublicId__c FROM AIWorkflowAction__c WHERE Id IN :flowActions];

        Assert.areEqual(2, inserted.size(), 'Both bulk-inserted Workflow Actions should be created.');

        for (AIWorkflowAction__c action : inserted) {
            Assert.isNotNull(action.PublicId__c, 'PublicId__c should be generated on insert.');
        }
    }

    @IsTest static void testScenario2() {

        AIWorkflowAction__c notFoundAction = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AIWorkflowActionTriggerTest_NonExistentClass', false)[0];

        Test.startTest();
            try {
                insert notFoundAction;
                Assert.fail('Inserting a Workflow Action with a non-existent Apex Class Name should have thrown.');
            } catch (DmlException e) {
                Assert.isTrue(e.getMessage().contains('could not be found'), 'Error should explain the class could not be found.');
            }
        Test.stopTest();
    }

    @IsTest static void testScenario3() {

        List<AIWorkflowAction__c> notImplementingActions = AIAssistTestDataFactory.createAIWorkflowActions(2, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AIAssistApplicationConstants', false); // A real, instantiable class that doesn't implement IAIWorkflowActionExecutor. Two records share it to prove the per-class-name error caching still flags every record.

        Test.startTest();
            try {
                insert notImplementingActions;
                Assert.fail('Inserting Workflow Actions whose Apex Class Name doesn\'t implement IAIWorkflowActionExecutor should have thrown.');
            } catch (DmlException e) {
                Assert.isTrue(e.getMessage().contains('must implement the IAIWorkflowActionExecutor interface'), 'Error should explain the interface requirement.');
            }
        Test.stopTest();
    }

    @IsTest static void testScenario4() {

        AIWorkflowAction__c notInstantiableAction = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'IAIWorkflowActionExecutor', false)[0]; // The interface itself: found by Type.forName but can never be constructed.

        Test.startTest();
            try {
                insert notInstantiableAction;
                Assert.fail('Inserting a Workflow Action with an uninstantiable Apex Class Name should have thrown.');
            } catch (DmlException e) {
                Assert.isTrue(e.getMessage().contains('could not be instantiated'), 'Error should explain the class could not be instantiated.');
            }
        Test.stopTest();
    }

    @IsTest static void testScenario5() {

        AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW, 'AIWorkflowActionTriggerTest_Flow', true)[0];

        action.ActionType__c = AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX;
        action.ApexClassName__c = 'AIAssistApplicationConstants'; // A real, instantiable class that doesn't implement IAIWorkflowActionExecutor.

        Test.startTest();
            try {
                update action;
                Assert.fail('Updating a Workflow Action to Apex Action Type with a class that doesn\'t implement IAIWorkflowActionExecutor should have thrown.');
            } catch (DmlException e) {
                Assert.isTrue(e.getMessage().contains('must implement the IAIWorkflowActionExecutor interface'), 'Error should explain the interface requirement.');
            }
        Test.stopTest();
    }

    @IsTest static void testScenario6() {

        // Apex Class Name validation can't be satisfied by any real class yet, since nothing in the org implements IAIWorkflowActionExecutor.
        // Deactivating the application bypasses the trigger entirely so an Apex-type record can be persisted, mirroring how a record could
        // already exist with an unvalidated Apex Class Name (for example, loaded while the application was inactive).
        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = false;
        update settings;

        AIWorkflowAction__c apexAction = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AIAssistApplicationConstants', true)[0];

        settings.IsApplicationActive__c = true;
        update settings;

        apexAction.Description__c = 'Updated description only.';

        Test.startTest();
            update apexAction; // Action Type and Apex Class Name are unchanged, so validation should not re-run.
        Test.stopTest();

        Assert.areEqual('Updated description only.', [SELECT Description__c FROM AIWorkflowAction__c WHERE Id = :apexAction.Id].Description__c, 'The unrelated field update should have been saved.');
    }
}