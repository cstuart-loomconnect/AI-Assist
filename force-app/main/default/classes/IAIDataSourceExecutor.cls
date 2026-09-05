/*
Class Name: IAIDataSourceExecutor

=================================================================
=================================================================

Description: Contract for the Apex class referenced by AIDataSource__c.ApexClassName__c
when SourceType__c is Apex. Implementing classes retrieve and return the data for that
data source.

=================================================================
=================================================================

Version      Date            Author                   Description
1.0          2026-09-05      Chandler Stuart          Initial development
*/

public interface IAIDataSourceExecutor {

    Object execute(Id recordId, Map<String, Object> inputParameters);

}