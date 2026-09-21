/*
Class Name: AiDataSourceDemoExecutor

=================================================================
=================================================================

Description: A real (non-test) IAIDataSourceExecutor implementation used by the demo Apex
AIDataSource__c created in scripts/apex/10_data_source_demo_setup.apex, so that Data Source
is genuinely runnable outside of test context. Returns the Account matching recordId, or
Accounts whose Name contains inputParameters.get('accountName') when recordId is null.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-21     Chandler Stuart          Initial development
*/

public class AiDataSourceDemoExecutor implements IAIDataSourceExecutor {

    public List<SObject> execute(Id recordId, Map<String, Object> inputParameters) {

        if (recordId != null) return [SELECT Id, Name FROM Account WHERE Id = :recordId];

        String nameFilter = inputParameters == null ? null : (String) inputParameters.get('accountName');
        if (String.isBlank(nameFilter)) return [SELECT Id, Name FROM Account LIMIT 10];

        return [SELECT Id, Name FROM Account WHERE Name LIKE :('%' + nameFilter + '%')];

    }

}