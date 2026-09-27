/*
Class Name: AIPlatformLogManagerTest

=================================================================
=================================================================

Description: This class contains unit tests for the AIPlatformLogManager class, which is responsible for logging exceptions and events related to the AI Assist Platform.
The tests cover various scenarios, including logging exceptions, handling invalid input, respecting global settings, and ensuring that logs are correctly inserted into the AIPlatformLog__c custom object.

=================================================================
=================================================================
Applicable Classes:

AIPlatformLogEventHandler: Converage 95%
AIPlatformLogEventTrigger: Coverage 100%
AIPlatformLogManager: Coverage 26%

Version      Date           Author                   Description
1.0          2026-09-09     Chandler Stuart          Initial development
1.1          2026-09-27     Chandler Stuart          Added testScenario7 - over-length exception message.
*/

@IsTest private class AIPlatformLogManagerTest {

    // testScenario1: Test logging a single exception and verify that the log record is inserted correctly.
    // testScenario2: Test logging an exception with a blank className and verify that no log record is inserted.
    // testScenario3: Test logging a null exception and verify that no log record is inserted.
    // testScenario4: Test logging an exception when DisablePlatformLogs__c is true and verify that no log record is inserted.
    // testScenario5: Test logging a custom message and verify that the log record is inserted correctly with the provided details.
    // testScenario6: Test logging an exception when IsApplicationActive__c is false and verify that no log record is inserted.
    // testScenario7: Test logging an exception whose message is over 255 characters and verify the log is still inserted, with the message truncated and kept in full in ExceptionLogDetail__c.

    private class TestLoggingException extends Exception {}

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = true;
        settings.DisableExceptionLogging__c = false;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        Test.startTest();
        
            try { throw new TestLoggingException('Something went wrong'); } 
            catch (Exception e) { AIPlatformLogManager.logException(e, 'SomeClass', 'someMethod'); }

        Test.stopTest();

        List<AIPlatformLog__c> logs = [SELECT ClassName__c, MethodName__c, ExceptionType__c, ExceptionMessage__c FROM AIPlatformLog__c];

        Assert.areEqual(1, logs.size(), 'Expected exactly one log record to be inserted.');
        Assert.areEqual('SomeClass', logs[0].ClassName__c);
        Assert.areEqual('someMethod', logs[0].MethodName__c);
        Assert.areEqual('AIPlatformLogManagerTest.TestLoggingException', logs[0].ExceptionType__c);
        Assert.areEqual('Something went wrong', logs[0].ExceptionMessage__c);

    }

    @IsTest static void testScenario2() {

        Test.startTest();
        
            try { throw new TestLoggingException('Ignored'); } 
            catch (Exception e) { AIPlatformLogManager.logException(e, '', 'someMethod'); }
        
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM AIPlatformLog__c], 'No record should be inserted when className is blank.');
    
    }

    @IsTest static void testScenario3() {

        Test.startTest();
            AIPlatformLogManager.logException(null, 'SomeClass', 'someMethod');
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM AIPlatformLog__c], 'No record should be inserted when the exception is null.');

    }

    @IsTest static void testScenario4() {

        // Set DisableExceptionLogging__c to true to test that logging is skipped
        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.DisableExceptionLogging__c = true;
            upsert settings;

        Test.startTest();
        
            try { throw new TestLoggingException('Should not be logged'); } 
            catch (Exception e) { AIPlatformLogManager.logException(e, 'SomeClass', 'someMethod');}

        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM AIPlatformLog__c], 'No record should be inserted when DisableExceptionLogging__c is true.');

    }

    @IsTest static void testScenario5() {

        Id fakeRecordId = System.UserInfo.getUserId(); // Using current user ID as a placeholder for testing

        Test.startTest();
            AIPlatformLogManager.logCustomMessage('Custom warning', 'Additional detail text', 'CustomClass', 'customMethod', fakeRecordId);
        Test.stopTest();

        List<AIPlatformLog__c> logs = [SELECT ExceptionType__c, ExceptionMessage__c, ExceptionLogDetail__c, RelatedRecordId__c FROM AIPlatformLog__c];

        Assert.areEqual(1, logs.size(), 'Expected exactly one log record to be inserted for the custom message.');
        Assert.areEqual('Custom Message', logs[0].ExceptionType__c);
        Assert.areEqual('Custom warning', logs[0].ExceptionMessage__c);
        Assert.areEqual('Additional detail text', logs[0].ExceptionLogDetail__c);
        Assert.areEqual(String.valueOf(fakeRecordId), logs[0].RelatedRecordId__c);

    }

    @IsTest static void testScenario6() {

        // Set DisableExceptionLogging__c to true to test that logging is skipped
        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = false;
            upsert settings;

        Test.startTest();
        
            try { throw new TestLoggingException('Should not be logged'); } 
            catch (Exception e) { AIPlatformLogManager.logException(e, 'SomeClass', 'someMethod');}

        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM AIPlatformLog__c], 'No record should be inserted when DisableExceptionLogging__c is true.');


    }
    @IsTest static void testScenario7() {

        String longMessage = 'AI provider returned HTTP 400: '.rightPad(300, 'x');

        Test.startTest();

            try { throw new TestLoggingException(longMessage); }
            catch (Exception e) { AIPlatformLogManager.logException(e, 'SomeClass', 'someMethod'); }

        Test.stopTest();

        List<AIPlatformLog__c> logs = [SELECT ExceptionMessage__c, ExceptionLogDetail__c FROM AIPlatformLog__c];

        Assert.areEqual(1, logs.size(), 'An over-length message should still be logged, not silently dropped.');
        Assert.areEqual(longMessage.left(255), logs[0].ExceptionMessage__c, 'The message should be truncated to the field length.');
        Assert.isTrue(logs[0].ExceptionLogDetail__c.contains(longMessage), 'The full message should be kept in ExceptionLogDetail__c.');

    }
}
