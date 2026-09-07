/*
Class Name: AIAssistUserTriggerHandler

=================================================================
=================================================================

Description: Handler for managing User events related to AI Assist, performing the
business logic that runs on the User trigger.

=================================================================
=================================================================

Version      Date               Author                   Description
1.0          2026-09-06         Chandler Stuart          Initial development
*/

public without sharing class AIAssistUserTriggerHandler {

    private static Boolean isBeforeInsertHandlerRunning = false;
    private static Boolean isAfterInsertHandlerRunning = false;
    private static Boolean isAfterUpdateHandlerRunning = false;

    public static void handleBeforeInsert(List<User> newUsers) {
        try {

            if (!isBeforeInsertHandlerRunning) {

                isBeforeInsertHandlerRunning = true;

                AIAssistGlobalUtility.generatePublicId(newUsers);
                AIAssistGlobalUtility.generateDeveloperName(newUsers);

            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIAssistUserTriggerHandler', 'handleBeforeInsert');
        }
    }

    public static void handleAfterInsert(Map<Id, User> userIdByNewUsers) {
        try {

            if (!isAfterInsertHandlerRunning) {

                isAfterInsertHandlerRunning = true;

                if (userIdByNewUsers == null || userIdByNewUsers.isEmpty()) return;

                Map<Id, String> userIdByUserType = new Map<Id, String>();

                for (User u : userIdByNewUsers.values()) {
                    if (String.isNotBlank(u.AIAssistUserType__c)) userIdByUserType.put(u.Id, u.AIAssistUserType__c);
                }

                if (!userIdByUserType.isEmpty()) { System.enqueueJob(new InitialiseAIAssistUserQueueable(userIdByUserType)); }

            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIAssistUserTriggerHandler', 'handleAfterInsert');
        }
    }

    public static void handleAfterUpdate(Map<Id, User> oldUsersById, Map<Id, User> newUsersById) {
        try {

            if (newUsersById == null || newUsersById.isEmpty() || oldUsersById == null || oldUsersById.isEmpty()) return;

            Set<Id> userIdsToDeactivate = new Set<Id>(); // Users whose AIAssistUserType__c was cleared and need to be deactivated.
            Map<Id, String> userIdToUserType = new Map<Id, String>(); // Users whose AIAssistUserType__c changed from blank to a non-blank value and need to be initialised.
            Map<Id, String> userIdByUserTypeToUpdate = new Map<Id, String>(); // Users whose AIAssistUserType__c changed from one non-blank value to another and need to be updated.

            for (User newUser : newUsersById.values()) {
                
                User oldUser = oldUsersById.get(newUser.Id);
                if (oldUser == null) continue;
                
                if (oldUser.AIAssistUserType__c == newUser.AIAssistUserType__c) continue; // No change in AIAssistUserType__c, skip to next user.

                if ( String.isBlank(oldUser.AIAssistUserType__c) ) { // NEW USER
                    userIdToUserType.put(newUser.Id, newUser.AIAssistUserType__c); 
                } else if ( String.isNotBlank(oldUser.AIAssistUserType__c) && String.isBlank(newUser.AIAssistUserType__c) ) { // DEACTIVE USER
                    userIdsToDeactivate.add(newUser.Id); 
                } else { // AI ASSIST USER TYPE CHANGE
                    userIdByUserTypeToUpdate.put(newUser.Id, newUser.AIAssistUserType__c); 
                }

            }

            if (!userIdsToDeactivate.isEmpty() && isQueueableRunnable()) { System.enqueueJob(new DeactivateAIAssistUserQueueable(userIdsToDeactivate)); }
            if (!userIdToUserType.isEmpty() && isQueueableRunnable()) { System.enqueueJob(new InitialiseAIAssistUserQueueable(userIdToUserType)); }
            if (!userIdByUserTypeToUpdate.isEmpty() && isQueueableRunnable()) { System.enqueueJob(new UpdateAIAssistUserQueueable(userIdByUserTypeToUpdate));}

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIAssistUserTriggerHandler', 'handleAfterUpdate');
        }
    }

    public class InitialiseAIAssistUserQueueable implements Queueable {

        private Map<Id, String> userIdByUserType;

        public InitialiseAIAssistUserQueueable(Map<Id, String> userIdByUserType) {
            this.userIdByUserType = userIdByUserType;
        }

        public void execute(QueueableContext context) {
            try {

                if (userIdByUserType == null || userIdByUserType.isEmpty()) return;

                Set<Id> userIds = userIdByUserType.keySet(); // Users whose AIAssistUserType__c changed from blank to a non-blank value and need to be initialised.
                List<AIUserSettings__c> settingsToInsert = new List<AIUserSettings__c>(); // New AIUserSettings__c records to insert for users who don't already have one.
                List<AIUserSettings__c> settingsToReactivate = new List<AIUserSettings__c>(); // Existing AIUserSettings__c records to reactivate for users who have one but are currently inactive.
                Map<Id, AIUserSettings__c> userIdByExistingSettings = new Map<Id, AIUserSettings__c>(); // Existing AIUserSettings__c records for users who already have one, keyed by User__c.

                for (AIUserSettings__c existing : [SELECT Id, User__c, IsActive__c FROM AIUserSettings__c WHERE User__c IN :userIds]) {
                    userIdByExistingSettings.put(existing.User__c, existing);
                }

                for (Id userId : userIds) {

                    AIUserSettings__c existing = userIdByExistingSettings.get(userId);

                    if (existing == null) { 
                        settingsToInsert.add( AIAssistUserDefaults.build( new User(Id = userId) ) ); 
                    }
                    else if (!existing.IsActive__c) { 
                        existing.IsActive__c = true; 
                        settingsToReactivate.add(existing); 
                    }

                }

                if (!settingsToInsert.isEmpty()) {
                    Database.SaveResult[] insertResults = Database.insert(settingsToInsert, false);
                    AIPlatformLogManager.logExceptions( insertResults, 'AIAssistUserTriggerHandler', 'InitialiseAIAssistUserQueueable');
                }

                if (!settingsToReactivate.isEmpty()) {
                    Database.SaveResult[] updateResults = Database.update(settingsToReactivate, false);
                    AIPlatformLogManager.logExceptions( updateResults, 'AIAssistUserTriggerHandler', 'InitialiseAIAssistUserQueueable');
                }

                System.enqueueJob(new AssignAIAssistPermissionSetQueueable(userIdByUserType));

            } catch (Exception e) {
                AIPlatformLogManager.logException(e, 'AIAssistUserTriggerHandler', 'InitialiseAIAssistUserQueueable');
            }
        }
    }

    public class AssignAIAssistPermissionSetQueueable implements Queueable {

        private Map<Id, String> userIdByUserType;

        public AssignAIAssistPermissionSetQueueable(Map<Id, String> userIdByUserType) {
            this.userIdByUserType = userIdByUserType;
        }

        public void execute(QueueableContext context) {
            try {

                if (userIdByUserType == null || userIdByUserType.isEmpty()) return;

                Set<Id> userIds = userIdByUserType.keySet(); // Users who require permission set assignments
                Set<Id> existingAssignmentKeys = new Set<Id>(); // Users who already have an AI Assist Permission Set assigned and don't need a new one assigned.
                Map<String, Id> permissionsSetNameById = new Map<String, Id>(); // Permission Set API names to Ids for the three AI Assist Permission Sets.
                List<PermissionSetAssignment> assignmentsToInsert = new List<PermissionSetAssignment>(); // List of Permission Set Assignments to insert for a given user (Or given set of users)

                for (PermissionSet ps : [SELECT Id, Name FROM PermissionSet WHERE Name IN :AIAssistApplicationConstants.PERMISSION_SET_BY_USER_TYPE.values()]) {
                    permissionsSetNameById.put(ps.Name, ps.Id);
                }

                for (PermissionSetAssignment psa : [SELECT AssigneeId, PermissionSetId FROM PermissionSetAssignment WHERE AssigneeId IN :userIds AND PermissionSetId IN :permissionsSetNameById.values()]) {
                    existingAssignmentKeys.add(psa.AssigneeId);
                }

                for (Id userId : userIds) {

                    if (existingAssignmentKeys.contains(userId)) continue;

                    String permissionSetName = AIAssistApplicationConstants.PERMISSION_SET_BY_USER_TYPE.get(userIdByUserType.get(userId));
                    Id psId = permissionSetName == null ? null : permissionsSetNameById.get(permissionSetName);

                    if (psId == null) continue;

                    assignmentsToInsert.add(new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = psId));
                }

                if (!assignmentsToInsert.isEmpty()) {
                    Database.SaveResult[] assignmentResults = Database.insert(assignmentsToInsert, false);
                    AIPlatformLogManager.logExceptions( assignmentResults, 'AIAssistUserTriggerHandler', 'AssignAIAssistPermissionSetQueueable');
                }

            } catch (Exception e) {
                AIPlatformLogManager.logException(e, 'AIAssistUserTriggerHandler', 'AssignAIAssistPermissionSetQueueable');
            }
        }
    }

    public class DeactivateAIAssistUserQueueable implements Queueable {

        private Set<Id> userIds;

        public DeactivateAIAssistUserQueueable(Set<Id> userIds) {
            this.userIds = userIds;
        }

        public void execute(QueueableContext context) {
            try {

                if (userIds == null || userIds.isEmpty()) return;

                List<AIUserSettings__c> settingsToDeactivate = [SELECT Id, IsActive__c FROM AIUserSettings__c WHERE User__c IN :userIds AND IsActive__c = true];

                for (AIUserSettings__c settings : settingsToDeactivate) {
                    settings.IsActive__c = false;
                }

                if (!settingsToDeactivate.isEmpty()) {
                    Database.SaveResult[] updateResults = Database.update(settingsToDeactivate, false);
                    AIPlatformLogManager.logExceptions( updateResults, 'AIAssistUserTriggerHandler', 'DeactivateAIAssistUserQueueable');
                }

                System.enqueueJob(new RevokeAIAssistPermissionSetQueueable(userIds));

            } catch (Exception e) {
                AIPlatformLogManager.logException(e, 'AIAssistUserTriggerHandler', 'DeactivateAIAssistUserQueueable');
            }
        }
    }

    public class RevokeAIAssistPermissionSetQueueable implements Queueable {

        private Set<Id> userIds;

        public RevokeAIAssistPermissionSetQueueable(Set<Id> userIds) {
            this.userIds = userIds;
        }

        public void execute(QueueableContext context) {
            try {

                if (userIds == null || userIds.isEmpty()) return;

                Map<String, Id> permissionsSetNameById = new Map<String, Id>(); // Permission Set API names to Ids for the three AI Assist Permission Sets.

                for (PermissionSet ps : [SELECT Id, Name FROM PermissionSet WHERE Name IN :AIAssistApplicationConstants.PERMISSION_SET_BY_USER_TYPE.values()]) {
                    permissionsSetNameById.put(ps.Name, ps.Id);
                }

                List<PermissionSetAssignment> assignmentsToDelete = [SELECT Id FROM PermissionSetAssignment WHERE AssigneeId IN :userIds AND PermissionSetId IN :permissionsSetNameById.values()];

                if (!assignmentsToDelete.isEmpty()) {
                    Database.DeleteResult[] deleteResults = Database.delete(assignmentsToDelete, false);
                    AIPlatformLogManager.logExceptions( deleteResults, 'AIAssistUserTriggerHandler', 'RevokeAIAssistPermissionSetQueueable');
                }

            } catch (Exception e) {
                AIPlatformLogManager.logException(e, 'AIAssistUserTriggerHandler', 'RevokeAIAssistPermissionSetQueueable');
            }
        }
    }

    public class UpdateAIAssistUserQueueable implements Queueable {

        private Map<Id, String> userIdByUserType;

        public UpdateAIAssistUserQueueable(Map<Id, String> userIdByUserType) {
            this.userIdByUserType = userIdByUserType;
        }

        public void execute(QueueableContext context) {
            try {

                if (userIdByUserType == null || userIdByUserType.isEmpty()) return;

                Set<Id> userIds = userIdByUserType.keySet(); // Users whose AIAssistUserType__c changed from one non-blank value to another and need to be updated.
                Map<String, Id> permissionsSetNameById = new Map<String, Id>(); // Permission Set API names to Ids for the three AI Assist Permission Sets.
                Map<Id, PermissionSetAssignment> currentAssignmentByUserId = new Map<Id, PermissionSetAssignment>(); // Current Permission Set Assignments for users who already have one, keyed by AssigneeId.
                List<PermissionSetAssignment> assignmentsToDelete = new List<PermissionSetAssignment>(); // Current Permission Set Assignments for users who already have one, keyed by AssigneeId.
                List<PermissionSetAssignment> assignmentsToInsert = new List<PermissionSetAssignment>(); // New Permission Set Assignments for users who need to be assigned a new one.

                for (PermissionSet ps : [SELECT Id, Name FROM PermissionSet WHERE Name IN :AIAssistApplicationConstants.PERMISSION_SET_BY_USER_TYPE.values()]) {
                    permissionsSetNameById.put(ps.Name, ps.Id);
                }

                for (PermissionSetAssignment psa : [SELECT Id, AssigneeId, PermissionSetId FROM PermissionSetAssignment WHERE AssigneeId IN :userIds AND PermissionSetId IN :permissionsSetNameById.values()]) {
                    currentAssignmentByUserId.put(psa.AssigneeId, psa);
                }

                for (Id userId : userIds) {

                    String permissionSetName = AIAssistApplicationConstants.PERMISSION_SET_BY_USER_TYPE.get(userIdByUserType.get(userId));
                    Id desiredPsId = permissionSetName == null ? null : permissionsSetNameById.get(permissionSetName);

                    PermissionSetAssignment current = currentAssignmentByUserId.get(userId);

                    if (current != null && current.PermissionSetId == desiredPsId) continue; // Already correctly assigned

                    if (current != null) {  assignmentsToDelete.add(current); } // Remove current assignment if it exists

                    if (desiredPsId != null) { assignmentsToInsert.add(new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = desiredPsId)); } // Add new assignment if desired
                
                }

                if (!assignmentsToDelete.isEmpty()) {
                    Database.DeleteResult[] deleteResults = Database.delete(assignmentsToDelete, false);
                    AIPlatformLogManager.logExceptions( deleteResults, 'AIAssistUserTriggerHandler', 'UpdateAIAssistUserQueueable');
                }

                if (!assignmentsToInsert.isEmpty()) {
                    Database.SaveResult[] assignmentResults = Database.insert(assignmentsToInsert, false);
                    AIPlatformLogManager.logExceptions( assignmentResults, 'AIAssistUserTriggerHandler', 'UpdateAIAssistUserQueueable');
                }

            } catch (Exception e) {
                AIPlatformLogManager.logException(e, 'AIAssistUserTriggerHandler', 'UpdateAIAssistUserQueueable');
            }
        }
    }

    private static Boolean isQueueableRunnable() {
        try {

            if (System.isFuture()) { return false; }

            Integer queueableJobsUsed = Limits.getQueueableJobs();

            // Chaining from Batch or Queueable context is capped at 1 job total,  regardless of the org's normal queueable ceiling.
            if (System.isBatch() || System.isQueueable()) {
                Integer maxChainedQueueableJobs = 1;
                return queueableJobsUsed < maxChainedQueueableJobs;
            }

            // Scheduled Apex and ordinary synchronous execution use the standard ceiling.
            return queueableJobsUsed < Limits.getLimitQueueableJobs();

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIAssistUserTriggerHandler', 'isQueueableRunnable');
            return false;
        }
    }
}