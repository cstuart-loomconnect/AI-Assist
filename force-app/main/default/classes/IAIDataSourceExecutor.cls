/*
Class Name: IAIDataSourceExecutor

=================================================================
=================================================================

Description: Contract for the Apex class referenced by AIDataSource__c.ApexClassName__c
when SourceType__c is Apex. Implementing classes retrieve and return the records for
that data source, scoped to AIDataSource__c.TargetObject__c.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-09     Chandler Stuart          Initial development
*/

public interface IAIDataSourceExecutor {

    List<SObject> execute(Id recordId, Map<String, Object> inputParameters);

}