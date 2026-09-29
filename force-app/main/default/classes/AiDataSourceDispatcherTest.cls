/*
Class Name: AiDataSourceDispatcherTest

=================================================================
=================================================================

Description: Testing utility for AiDataSourceDispatcher.

=================================================================
=================================================================
Applicable Classes:

AiDataSourceDispatcher: Coverage 100%

Version      Date               Author                   Description
1.0          2026-09-21         Chandler Stuart          Initial development
*/

@IsTest private class AiDataSourceDispatcherTest {

    // testScenario1: A SOQL Data Source runs its template correctly whether Bound (recordId bound in) or Unbound (only AI-supplied input parameters bound in).
    // testScenario2: An Apex Data Source resolves its ApexClassName__c and returns the IAIDataSourceExecutor's result - also proving null inputParameters and an explicit AccessLevel are both handled without error.
    // testScenario3: A null Data Source Id, and a Data Source Id that doesn't resolve to a record, both throw AIDataSourceExecutorException rather than running.
    // testScenario4: An inactive Data Source throws AIDataSourceExecutorException rather than running.
    // testScenario5: A misconfigured Data Source - no Source Type, or an Apex Class Name that doesn't implement IAIDataSourceExecutor - throws a clear AIDataSourceExecutorException.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        upsert settings;

        AIAssistTestDataFactory.createAccounts(1, true);
    }

    @IsTest static void testScenario1() {

        Account testAccount = [SELECT Id, Name FROM Account LIMIT 1];

        AIDataSource__c boundDataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id, Name FROM Account WHERE Id = :recordId', false)[0];
        boundDataSource.IsActive__c = true;

        AIDataSource__c unboundDataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id, Name FROM Account WHERE Name = :accountName', false)[0];
        unboundDataSource.IsActive__c = true;

        insert new List<AIDataSource__c>{ boundDataSource, unboundDataSource };

        Test.startTest();
            List<Object> boundResults = AiDataSourceDispatcher.execute(boundDataSource.Id, testAccount.Id, null, null, null);
            List<Object> unboundResults = AiDataSourceDispatcher.execute(unboundDataSource.Id, null, new Map<String, Object>{ 'accountName' => testAccount.Name }, null, null);
        Test.stopTest();

        Assert.areEqual(1, boundResults.size(), 'Bound Data Source should return the one Account matched by recordId.');
        Assert.areEqual(testAccount.Name, ((Map<String, Object>) boundResults[0]).get('Name'), 'The flattened result should carry the real Account Name through unmasked, since Name isn\'t registered as PII.');

        Assert.areEqual(1, unboundResults.size(), 'Unbound Data Source should return the one Account matched purely by the AI-supplied input parameter, with no recordId.');
    }

    @IsTest static void testScenario2() {

        Account testAccount = [SELECT Id, Name FROM Account LIMIT 1];

        AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX, 'AiDataSourceDispatcherTest.TestExecutor', false)[0];
        dataSource.IsActive__c = true;
        insert dataSource;

        Test.startTest();
            List<Object> results = AiDataSourceDispatcher.execute(dataSource.Id, testAccount.Id, null, AccessLevel.SYSTEM_MODE, null); // null inputParameters and an explicit AccessLevel together.
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Should return the one Account the test executor resolved by recordId.');
        Assert.areEqual(testAccount.Id, ((Map<String, Object>) results[0]).get('Id'), 'The flattened result should carry the Account Id returned by the Apex executor.');
    }

    @IsTest static void testScenario3() {

        AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id FROM Account', false)[0];
        dataSource.IsActive__c = true;
        insert dataSource;
        Id deletedDataSourceId = dataSource.Id;
        delete dataSource;

        Test.startTest();

            try {
                AiDataSourceDispatcher.execute(null, null, null, null, null);
                Assert.fail('A null Data Source Id should have thrown.');
            } catch (AiDataSourceDispatcher.AIDataSourceExecutorException ex) {
                Assert.isTrue(ex.getMessage().contains('not found'), 'Error should explain the Data Source wasn\'t found.');
            }

            try {
                AiDataSourceDispatcher.execute(deletedDataSourceId, null, null, null, null);
                Assert.fail('A Data Source Id with no matching record should have thrown.');
            } catch (AiDataSourceDispatcher.AIDataSourceExecutorException ex) {
                Assert.isTrue(ex.getMessage().contains('not found'), 'Error should explain the Data Source wasn\'t found.');
            }

        Test.stopTest();
    }

    @IsTest static void testScenario4() {

        AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id FROM Account', false)[0];
        dataSource.IsActive__c = false; // Explicit - createAIDataSources doesn't set it, and the field's own default is already false.
        insert dataSource;

        Test.startTest();
            try {
                AiDataSourceDispatcher.execute(dataSource.Id, null, null, null, null);
                Assert.fail('An inactive Data Source should have thrown.');
            } catch (AiDataSourceDispatcher.AIDataSourceExecutorException ex) {
                Assert.isTrue(ex.getMessage().contains('is not active'), 'Error should explain the Data Source is inactive.');
            }
        Test.stopTest();
    }

    @IsTest static void testScenario5() {

        AIDataSource__c noSourceTypeDataSource = AIAssistTestDataFactory.createAIDataSources(1, null, null, false)[0]; // No Source Type - the field isn't required, so this insert is valid on its own.
        noSourceTypeDataSource.IsActive__c = true;
        insert noSourceTypeDataSource;

        // AIDataSourceTriggerHandler validates ApexClassName__c on Apex-type records at insert time, so the app is deactivated to bypass
        // that trigger and get an otherwise-invalid record persisted, mirroring how such a record could already exist in an org.
        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = false;
        update settings;

        AIDataSource__c notImplementingDataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX, 'AIAssistApplicationConstants', false)[0]; // A real, instantiable class that doesn't implement IAIDataSourceExecutor.
        notImplementingDataSource.IsActive__c = true;
        insert notImplementingDataSource;

        settings.IsApplicationActive__c = true;
        update settings;

        Test.startTest();

            try {
                AiDataSourceDispatcher.execute(noSourceTypeDataSource.Id, null, null, null, null);
                Assert.fail('A Data Source with no Source Type configured should have thrown.');
            } catch (AiDataSourceDispatcher.AIDataSourceExecutorException ex) {
                Assert.isTrue(ex.getMessage().contains('no Source Type configured'), 'Error should explain the Source Type is missing.');
            }

            try {
                AiDataSourceDispatcher.execute(notImplementingDataSource.Id, null, null, null, null);
                Assert.fail('An Apex Class Name that doesn\'t implement IAIDataSourceExecutor should have thrown.');
            } catch (AiDataSourceDispatcher.AIDataSourceExecutorException ex) {
                Assert.isTrue(ex.getMessage().contains('must implement IAIDataSourceExecutor'), 'Error should explain the interface requirement.');
            }

        Test.stopTest();
    }

    // A minimal, real IAIDataSourceExecutor implementation - AiDataSourceDispatcher resolves Apex Class Names via Type.forName(), so a genuine class is required rather than a mock.
    public class TestExecutor implements IAIDataSourceExecutor {

        public List<SObject> execute(Id recordId, Map<String, Object> inputParameters) {

            if (recordId != null) return [SELECT Id, Name FROM Account WHERE Id = :recordId];

            String accountName = inputParameters == null ? null : (String) inputParameters.get('accountName');
            if (String.isBlank(accountName)) return new List<SObject>();

            return [SELECT Id, Name FROM Account WHERE Name = :accountName];

        }

    }
}