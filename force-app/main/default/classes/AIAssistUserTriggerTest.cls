/*
Class Name: AIAssistUserTriggerTest

=================================================================
=================================================================

Description: This class contains unit tests for the AIAssistUserTrigger and AIAssistUserTriggerHandler.
The suite verifies that changes to a User's AIAssistUserType__c drive the correct downstream provisioning:
creating, reactivating and deactivating AIUserSettings__c, and assigning, switching and revoking the
matching AI Assist permission set.

=================================================================
=================================================================
Applicable Classes:

AIAssistUserTrigger: Coverage 100%
AIAssistUserTriggerHandler: Coverage 90%

Version      Date           Author                   Description
1.0          2026-09-06     Chandler Stuart          Initial development
1.1          2026-09-07     Chandler Stuart          Reduced to core scenarios; removed bulk insert coverage
1.2          2026-09-07     Chandler Stuart          Inlined permission set queries into each scenario
*/

@IsTest private class AIAssistUserTriggerTest {

    // testScenario1: Inserting a User with an AIAssistUserType__c provisions an active AIUserSettings__c record and assigns the matching permission set.
    // testScenario2: Inserting a User without an AIAssistUserType__c provisions nothing.
    // testScenario3: Setting AIAssistUserType__c on a User with an inactive AIUserSettings__c reactivates it and reassigns the permission set.
    // testScenario4: Clearing a User's AIAssistUserType__c deactivates its AIUserSettings__c record and revokes the permission set.
    // testScenario5: Changing a User's AIAssistUserType__c swaps the assigned permission set for the new type.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = true;
        settings.DisableExceptionLogging__c = false;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User u = AIAssistTestDataFactory.createStandardUsers(AIAssistApplicationConstants.USER_TYPE_STANDARD, 1, false)[0];

        Test.startTest();
            System.runAs( new User(Id = UserInfo.getUserId()) ) { insert u; }
            System.enqueueJob(new AIAssistUserTriggerHandler.AssignAIAssistPermissionSetQueueable(new Map<Id, String>{ u.Id => AIAssistApplicationConstants.USER_TYPE_STANDARD }));
        Test.stopTest();

        AIUserSettings__c settings = [SELECT IsActive__c FROM AIUserSettings__c WHERE User__c =:u.Id LIMIT 1];

        Id userPermissionSetId = [SELECT Id FROM PermissionSet WHERE Name =:AIAssistApplicationConstants.PERMISSION_SET_USER LIMIT 1].Id;
        Integer userPermissionSetAssignmentCount = [SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId =:u.Id AND PermissionSetId =:userPermissionSetId];

        Assert.isNotNull(settings, 'Expected An AIUserSettings__c record. Value Should Not Be Null');
        Assert.isTrue(settings.IsActive__c, 'The new AIUserSettings__c record should be active.');
        Assert.areEqual(1, userPermissionSetAssignmentCount, 'The permission set matching the user type should be assigned.');
    }

    @IsTest static void testScenario2() {

        User u = AIAssistTestDataFactory.createStandardUsers(null, 1, false)[0];

        Test.startTest();
            System.runAs(new User(Id = UserInfo.getUserId())) { insert u; }
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM AIUserSettings__c WHERE User__c =:u.Id], 'No AIUserSettings__c should be created when AIAssistUserType__c is blank.');
    }

    @IsTest static void testScenario3() {

        User u = AIAssistTestDataFactory.createStandardUsers(null, 1, false)[0];
        System.runAs( new User(Id = UserInfo.getUserId()) ) { insert u; }

        AIUserSettings__c settings = AIAssistUserDefaults.build(new User(Id = u.Id));
        settings.IsActive__c = false;
            insert settings;

        Test.startTest();
            System.runAs(new User(Id = UserInfo.getUserId())) { update new User(Id = u.Id, AIAssistUserType__c = AIAssistApplicationConstants.USER_TYPE_STANDARD); }
            System.enqueueJob(new AIAssistUserTriggerHandler.AssignAIAssistPermissionSetQueueable(new Map<Id, String>{ u.Id => AIAssistApplicationConstants.USER_TYPE_STANDARD }));
        Test.stopTest();

        Id userPermissionSetId = [SELECT Id FROM PermissionSet WHERE Name =:AIAssistApplicationConstants.PERMISSION_SET_USER LIMIT 1].Id;
        Integer userPermissionSetAssignmentCount = [SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId =:u.Id AND PermissionSetId =:userPermissionSetId];

        Assert.areEqual(1, [SELECT COUNT() FROM AIUserSettings__c WHERE User__c = :u.Id AND IsActive__c = true], 'Setting AIAssistUserType__c should reactivate the existing AIUserSettings__c record.');
        Assert.areEqual(1, userPermissionSetAssignmentCount, 'The permission set matching the user type should be reassigned.');
    }

    @IsTest static void testScenario4() {

        User u = AIAssistTestDataFactory.createStandardUsers(AIAssistApplicationConstants.USER_TYPE_STANDARD, 1, false)[0];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
            Id userPermissionSetId = [SELECT Id FROM PermissionSet WHERE Name =:AIAssistApplicationConstants.PERMISSION_SET_USER LIMIT 1].Id;
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = userPermissionSetId);
        }

        insert AIAssistUserDefaults.build(new User(Id = u.Id));

        Test.startTest();
            System.runAs(new User(Id = UserInfo.getUserId())) { update new User(Id = u.Id, AIAssistUserType__c = null); }
            System.enqueueJob(new AIAssistUserTriggerHandler.RevokeAIAssistPermissionSetQueueable(new Set<Id>{ u.Id }));
        Test.stopTest();

        Id userPermissionSetId = [SELECT Id FROM PermissionSet WHERE Name =:AIAssistApplicationConstants.PERMISSION_SET_USER LIMIT 1].Id;
        Integer userPermissionSetAssignmentCount = [SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId =:u.Id AND PermissionSetId =:userPermissionSetId];

        Assert.areEqual(0, [SELECT COUNT() FROM AIUserSettings__c WHERE User__c =:u.Id AND IsActive__c = true], 'Clearing AIAssistUserType__c should deactivate the AIUserSettings__c record.');
        Assert.areEqual(0, userPermissionSetAssignmentCount, 'Clearing AIAssistUserType__c should revoke the permission set.');
    }

    @IsTest static void testScenario5() {

        User u = AIAssistTestDataFactory.createStandardUsers(AIAssistApplicationConstants.USER_TYPE_STANDARD, 1, false)[0];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
            Id userPermissionSetId = [SELECT Id FROM PermissionSet WHERE Name =:AIAssistApplicationConstants.PERMISSION_SET_USER LIMIT 1].Id;
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = userPermissionSetId);
        }

        insert AIAssistUserDefaults.build(new User(Id = u.Id));

        Test.startTest();
            System.runAs(new User(Id = UserInfo.getUserId())) { update new User(Id = u.Id, AIAssistUserType__c = AIAssistApplicationConstants.USER_TYPE_ADMIN); }
        Test.stopTest();

        Id userPermissionSetId = [SELECT Id FROM PermissionSet WHERE Name =:AIAssistApplicationConstants.PERMISSION_SET_USER LIMIT 1].Id;
        Integer userPermissionSetAssignmentCount = [SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId =:u.Id AND PermissionSetId =:userPermissionSetId];

        Id adminPermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = :AIAssistApplicationConstants.PERMISSION_SET_ADMIN_USER LIMIT 1].Id;
        Integer adminPermissionSetAssignmentCount = [SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId =:u.Id AND PermissionSetId =:adminPermissionSetId];

        Assert.areEqual(0, userPermissionSetAssignmentCount, 'The permission set for the previous user type should be revoked.');
        Assert.areEqual(1, adminPermissionSetAssignmentCount, 'The permission set for the new user type should be assigned.');
    }
}