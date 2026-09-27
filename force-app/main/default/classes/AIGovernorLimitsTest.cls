/*
Class Name: AIGovernorLimitsTest

=================================================================
=================================================================

Description: Testing utility for the AIGovernorLimits class.

=================================================================
=================================================================
Applicable Classes:

AIGovernorLimits: Coverage 100%

Version      Date               Author                   Description
1.0          2026-09-27         Chandler Stuart          Initial development
1.1          2026-09-27         Chandler Stuart          Removed the getRetryDelayMinutes scenario along with the method.
*/

@IsTest private class AIGovernorLimitsTest {

    // testScenario1: isUncommittedDmlSince is false with no DML since the snapshot, and true once a record is inserted.
    // testScenario2: isUncommittedWorkException is true only for a CalloutException carrying the platform's "uncommitted work pending" message.
    // testScenario3: getRemainingCalloutMilliseconds counts down from the 120s budget, and isSafeToRunToolCall is true in a fresh transaction.

    @IsTest static void testScenario1() {

        Test.startTest();
            AIGovernorLimits.DmlSnapshot snapshot = AIGovernorLimits.takeDmlSnapshot();
            Boolean isDmlBeforeInsert = AIGovernorLimits.isUncommittedDmlSince(snapshot);

            insert new Account(Name = 'Governor Limits Test');
            Boolean isDmlAfterInsert = AIGovernorLimits.isUncommittedDmlSince(snapshot);
        Test.stopTest();

        Assert.isFalse(isDmlBeforeInsert, 'No DML has run since the snapshot.');
        Assert.isTrue(isDmlAfterInsert, 'The insert should be detected as uncommitted DML.');
        Assert.isFalse(AIGovernorLimits.isUncommittedDmlSince(null), 'A null snapshot should never report DML.');
    }

    @IsTest static void testScenario2() {

        Test.startTest();
            Boolean isUncommittedWork = AIGovernorLimits.isUncommittedWorkException(new CalloutException('You have uncommitted work pending. Please commit or rollback before calling out'));
            Boolean isOtherCalloutError = AIGovernorLimits.isUncommittedWorkException(new CalloutException('Read timed out'));
            Boolean isOtherExceptionType = AIGovernorLimits.isUncommittedWorkException(new DmlException('You have uncommitted work pending.'));
        Test.stopTest();

        Assert.isTrue(isUncommittedWork, 'The platform\'s uncommitted work callout error should be recognised.');
        Assert.isFalse(isOtherCalloutError, 'A timeout is an ordinary callout failure.');
        Assert.isFalse(isOtherExceptionType, 'Only a CalloutException can be an uncommitted work callout failure.');
    }

    @IsTest static void testScenario3() {

        Test.startTest();
            Integer remainingCalloutMilliseconds = AIGovernorLimits.getRemainingCalloutMilliseconds(System.currentTimeMillis());
            Boolean isSafeToRunToolCall = AIGovernorLimits.isSafeToRunToolCall();
        Test.stopTest();

        Assert.isTrue(remainingCalloutMilliseconds <= AIAssistApplicationConstants.MAX_TRANSACTION_CALLOUT_MILLISECONDS, 'Remaining callout time can never exceed the budget.');
        Assert.isTrue(remainingCalloutMilliseconds > AIAssistApplicationConstants.MAX_TRANSACTION_CALLOUT_MILLISECONDS - 5000, 'Almost none of the budget should be used yet.');
        Assert.isTrue(isSafeToRunToolCall, 'A fresh transaction has plenty of each limit left for a tool call.');
    }
}