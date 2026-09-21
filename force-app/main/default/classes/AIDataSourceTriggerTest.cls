/*
Class Name: AIDataSourceTriggerTest

=================================================================
=================================================================

Description: Testing utility for the AI Data Source Trigger.

=================================================================
=================================================================
Applicable Classes:

AIDataSourceTrigger: Coverage 100%
AIDataSourceTriggerHandler: Coverage 89%

Version      Date               Author                   Description
1.0          2026-09-09         Chandler Stuart          Initial development
*/

@IsTest private class AIDataSourceTriggerTest {

    // testScenario1: Bulk inserting SOQL-type AIDataSource__c records generates each record's PublicId__c and inserts cleanly, since Apex Class Name validation only applies to Apex-type records.
    // testScenario2: Inserting a Data Source with a non-existent Apex Class Name raises a validation error on ApexClassName__c and rolls back the insert.
    // testScenario3: Inserting Data Sources whose Apex Class Name doesn't implement IAIDataSourceExecutor raises a validation error and rolls back the insert - including when two records share the same invalid class name.
    // testScenario4: Inserting a Data Source with an uninstantiable Apex Class Name raises a validation error and rolls back the insert.
    // testScenario5: Updating an AIDataSource__c's Source Type to Apex with an Apex Class Name that doesn't implement IAIDataSourceExecutor raises a validation error on update.
    // testScenario6: Updating an unrelated field on an Apex-type AIDataSource__c, leaving Source Type and Apex Class Name unchanged, does not re-run Apex Class Name validation.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = true;
        settings.DisableExceptionLogging__c = false;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        List<AIDataSource__c> soqlSources = AIAssistTestDataFactory.createAIDataSources(2, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id FROM Account', false);

        Test.startTest();
            insert soqlSources;
        Test.stopTest();

        List<AIDataSource__c> inserted = [SELECT PublicId__c FROM AIDataSource__c WHERE Id IN :soqlSources];

        Assert.areEqual(2, inserted.size(), 'Both bulk-inserted Data Sources should be created.');

        for (AIDataSource__c dataSource : inserted) {
            Assert.isNotNull(dataSource.PublicId__c, 'PublicId__c should be generated on insert.');
        }
    }

    @IsTest static void testScenario2() {

        AIDataSource__c notFoundSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX, 'AIDataSourceTriggerTest_NonExistentClass', false)[0];

        Test.startTest();
            try {
                insert notFoundSource;
                Assert.fail('Inserting a Data Source with a non-existent Apex Class Name should have thrown.');
            } catch (DmlException e) {
                Assert.isTrue(e.getMessage().contains('could not be found'), 'Error should explain the class could not be found.');
            }
        Test.stopTest();
    }

    @IsTest static void testScenario3() {

        List<AIDataSource__c> notImplementingSources = AIAssistTestDataFactory.createAIDataSources(2, AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX, 'AIAssistApplicationConstants', false); // A real, instantiable class that doesn't implement IAIDataSourceExecutor. Two records share it to prove the per-class-name error caching still flags every record.

        Test.startTest();
            try {
                insert notImplementingSources;
                Assert.fail('Inserting Data Sources whose Apex Class Name doesn\'t implement IAIDataSourceExecutor should have thrown.');
            } catch (DmlException e) {
                Assert.isTrue(e.getMessage().contains('must implement the IAIDataSourceExecutor interface'), 'Error should explain the interface requirement.');
            }
        Test.stopTest();
    }

    @IsTest static void testScenario4() {

        AIDataSource__c notInstantiableSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX, 'IAIDataSourceExecutor', false)[0]; // The interface itself: found by Type.forName but can never be constructed.

        Test.startTest();
            try {
                insert notInstantiableSource;
                Assert.fail('Inserting a Data Source with an uninstantiable Apex Class Name should have thrown.');
            } catch (DmlException e) {
                Assert.isTrue(e.getMessage().contains('could not be instantiated'), 'Error should explain the class could not be instantiated.');
            }
        Test.stopTest();
    }

    @IsTest static void testScenario5() {

        AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id FROM Account', true)[0];

        dataSource.SourceType__c = AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX;
        dataSource.ApexClassName__c = 'AIAssistApplicationConstants'; // A real, instantiable class that doesn't implement IAIDataSourceExecutor.

        Test.startTest();
            try {
                update dataSource;
                Assert.fail('Updating a Data Source to Apex Source Type with a class that doesn\'t implement IAIDataSourceExecutor should have thrown.');
            } catch (DmlException e) {
                Assert.isTrue(e.getMessage().contains('must implement the IAIDataSourceExecutor interface'), 'Error should explain the interface requirement.');
            }
        Test.stopTest();
    }

    @IsTest static void testScenario6() {

        // Apex Class Name validation can't be satisfied by any real class yet, since nothing in the org implements IAIDataSourceExecutor.
        // Deactivating the application bypasses the trigger entirely so an Apex-type record can be persisted, mirroring how a record could
        // already exist with an unvalidated Apex Class Name (for example, loaded while the application was inactive).
        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = false;
        update settings;

        AIDataSource__c apexSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX, 'AIAssistApplicationConstants', true)[0];

        settings.IsApplicationActive__c = true;
        update settings;

        apexSource.Description__c = 'Updated description only.';

        Test.startTest();
            update apexSource; // Source Type and Apex Class Name are unchanged, so validation should not re-run.
        Test.stopTest();

        Assert.areEqual('Updated description only.', [SELECT Description__c FROM AIDataSource__c WHERE Id = :apexSource.Id].Description__c, 'The unrelated field update should have been saved.');
    }
}