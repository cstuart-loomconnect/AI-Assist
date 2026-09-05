/*
Class Name: AIDataSourceValidationException

=================================================================
=================================================================

Description: Thrown by AIDataSourceTriggerHandler when an AIDataSource__c record's
ApexClassName__c doesn't resolve to a class implementing IAIDataSourceExecutor.

=================================================================
=================================================================

Version      Date            Author                   Description
1.0          2026-09-05      Chandler Stuart          Initial development
*/

public class AIDataSourceValidationException extends Exception {}