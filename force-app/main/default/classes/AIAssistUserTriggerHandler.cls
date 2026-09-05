/*
Class Name: AIAssistUserTriggerHandler

=================================================================
=================================================================

Description: Handler for managing User events related to AI Assist. Reacts to
AIAssistUserType__c: blank -> set triggers InitialiseAIAssistUserQueueable, set -> blank
triggers DeactivateAIAssistUserQueueable, and one value -> another triggers
UpdateAIAssistUserQueueable.

=================================================================
=================================================================

Version      Date            Author                   Description
1.0          2026-09-03      Chandler Stuart          Initial development
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

    public static void handleAfterInsert(Map<Id, User> newUsersById) {
        try {

            if (!isAfterInsertHandlerRunning) {

                isAfterInsertHandlerRunning = true;

                if (newUsersById == null || newUsersById.isEmpty()) return;

                Map<Id, String> userTypeByUserId = new Map<Id, String>();

                for (User u : newUsersById.values()) {
                    if (String.isNotBlank(u.AIAssistUserType__c)) {
                        userTypeByUserId.put(u.Id, u.AIAssistUserType__c);
                    }
                }

                if (!userTypeByUserId.isEmpty()) { System.enqueueJob(new InitialiseAIAssistUserQueueable(userTypeByUserId)); }

            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIAssistUserTriggerHandler', 'handleAfterInsert');
        }
    }

    public static void handleAfterUpdate(Map<Id, User> oldUsersById, Map<Id, User> newUsersById) {
        try {

            if (newUsersById == null || newUsersById.isEmpty() || oldUsersById == null) return;

            Set<Id> userIdsToDeactivate = new Set<Id>(); // Users whose AIAssistUserType__c was cleared and need to be deactivated.
            Map<Id, String> userTypeToUpdate = new Map<Id, String>(); // Users whose AIAssistUserType__c changed from one non-blank value to another and need to be updated.
            Map<Id, String> userTypeToInitialise = new Map<Id, String>(); // Users whose AIAssistUserType__c changed from blank to a non-blank value and need to be initialised.

            for (User newUser : newUsersById.values()) {
                
                User oldUser = oldUsersById.get(newUser.Id);
                if (oldUser == null) continue;
                
                String oldType = oldUser.AIAssistUserType__c;
                String newType = newUser.AIAssistUserType__c;
                
                if (oldType == newType) continue; // No change in AIAssistUserType__c, skip to next user.
                
                if (String.isBlank(oldType)) { userTypeToInitialise.put(newUser.Id, newType); } 
                else if (String.isBlank(newType)) { userIdsToDeactivate.add(newUser.Id); } 
                else { userTypeToUpdate.put(newUser.Id, newType); }

            }

            if (!userTypeToInitialise.isEmpty() && isQueueableRunnable()) { System.enqueueJob(new InitialiseAIAssistUserQueueable(userTypeToInitialise)); }
            if (!userIdsToDeactivate.isEmpty() && isQueueableRunnable()) { System.enqueueJob(new DeactivateAIAssistUserQueueable(userIdsToDeactivate)); }
            if (!userTypeToUpdate.isEmpty() && isQueueableRunnable()) { System.enqueueJob(new UpdateAIAssistUserQueueable(userTypeToUpdate));}

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIAssistUserTriggerHandler', 'handleAfterUpdate');
        }
    }

    public class InitialiseAIAssistUserQueueable implements Queueable {

        private Map<Id, String> userTypeByUserId;

        public InitialiseAIAssistUserQueueable(Map<Id, String> userTypeByUserId) {
            this.userTypeByUserId = userTypeByUserId;
        }

        public void execute(QueueableContext context) {
            try {

                if (userTypeByUserId == null || userTypeByUserId.isEmpty()) return;

                Set<Id> userIds = userTypeByUserId.keySet(); // Users whose AIAssistUserType__c changed from blank to a non-blank value and need to be initialised.
                List<AIUserSettings__c> settingsToInsert = new List<AIUserSettings__c>(); // New AIUserSettings__c records to insert for users who don't already have one.
                List<AIUserSettings__c> settingsToReactivate = new List<AIUserSettings__c>(); // Existing AIUserSettings__c records to reactivate for users who have one but are currently inactive.
                Map<Id, AIUserSettings__c> existingSettingsByUserId = new Map<Id, AIUserSettings__c>(); // Existing AIUserSettings__c records for users who already have one, keyed by User__c.

                for (AIUserSettings__c existing : [SELECT Id, User__c, IsActive__c FROM AIUserSettings__c WHERE User__c IN :userIds]) {
                    existingSettingsByUserId.put(existing.User__c, existing);
                }

                for (Id userId : userIds) {

                    AIUserSettings__c existing = existingSettingsByUserId.get(userId);

                    if (existing == null) { settingsToInsert.add(AIAssistUserDefaults.build(new User(Id = userId))); }
                    else if (!existing.IsActive__c) { existing.IsActive__c = true; settingsToReactivate.add(existing); }

                }

                if (!settingsToInsert.isEmpty()) {
                    Database.SaveResult[] insertResults = Database.insert(settingsToInsert, false);
                    AIPlatformLogManager.logExceptions( insertResults, 'AIAssistUserTriggerHandler', 'InitialiseAIAssistUserQueueable');
                }

                if (!settingsToReactivate.isEmpty()) {
                    Database.SaveResult[] updateResults = Database.update(settingsToReactivate, false);
                    AIPlatformLogManager.logExceptions( updateResults, 'AIAssistUserTriggerHandler', 'InitialiseAIAssistUserQueueable');
                }

                System.enqueueJob(new AssignAIAssistPermissionSetQueueable(userTypeByUserId));

            } catch (Exception e) {
                AIPlatformLogManager.logException(e, 'AIAssistUserTriggerHandler', 'InitialiseAIAssistUserQueueable');
            }
        }
    }

    public class AssignAIAssistPermissionSetQueueable implements Queueable {

        private Map<Id, String> userTypeByUserId;

        public AssignAIAssistPermissionSetQueueable(Map<Id, String> userTypeByUserId) {
            this.userTypeByUserId = userTypeByUserId;
        }

        public void execute(QueueableContext context) {
            try {

                if (userTypeByUserId == null || userTypeByUserId.isEmpty()) return;

                Set<Id> userIds = userTypeByUserId.keySet();
                Set<Id> existingAssignmentKeys = new Set<Id>(); // Users who already have an AI Assist Permission Set assigned and don't need a new one assigned.
                Map<String, Id> permissionSetIdByName = new Map<String, Id>(); // Permission Set API names to Ids for the three AI Assist Permission Sets.

                for (PermissionSet ps : [SELECT Id, Name FROM PermissionSet WHERE Name IN :AIAssistApplicationConstants.PERMISSION_SET_BY_USER_TYPE.values()]) {
                    permissionSetIdByName.put(ps.Name, ps.Id);
                }

                for (PermissionSetAssignment psa : [SELECT AssigneeId, PermissionSetId FROM PermissionSetAssignment WHERE AssigneeId IN :userIds AND PermissionSetId IN :permissionSetIdByName.values()]) {
                    existingAssignmentKeys.add(psa.AssigneeId);
                }

                List<PermissionSetAssignment> assignmentsToInsert = new List<PermissionSetAssignment>();

                for (Id userId : userIds) {

                    if (existingAssignmentKeys.contains(userId)) continue;

                    String permissionSetName = AIAssistApplicationConstants.PERMISSION_SET_BY_USER_TYPE.get(userTypeByUserId.get(userId));
                    Id psId = permissionSetName == null ? null : permissionSetIdByName.get(permissionSetName);

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

                Map<String, Id> permissionSetIdByName = new Map<String, Id>(); // Permission Set API names to Ids for the three AI Assist Permission Sets.

                for (PermissionSet ps : [SELECT Id, Name FROM PermissionSet WHERE Name IN :AIAssistApplicationConstants.PERMISSION_SET_BY_USER_TYPE.values()]) {
                    permissionSetIdByName.put(ps.Name, ps.Id);
                }

                List<PermissionSetAssignment> assignmentsToDelete = [SELECT Id FROM PermissionSetAssignment WHERE AssigneeId IN :userIds AND PermissionSetId IN :permissionSetIdByName.values()];

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

        private Map<Id, String> userTypeByUserId;

        public UpdateAIAssistUserQueueable(Map<Id, String> userTypeByUserId) {
            this.userTypeByUserId = userTypeByUserId;
        }

        public void execute(QueueableContext context) {
            try {

                if (userTypeByUserId == null || userTypeByUserId.isEmpty()) return;

                Set<Id> userIds = userTypeByUserId.keySet(); // Users whose AIAssistUserType__c changed from one non-blank value to another and need to be updated.
                Map<String, Id> permissionSetIdByName = new Map<String, Id>(); // Permission Set API names to Ids for the three AI Assist Permission Sets.
                Map<Id, PermissionSetAssignment> currentAssignmentByUserId = new Map<Id, PermissionSetAssignment>(); // Current Permission Set Assignments for users who already have one, keyed by AssigneeId.
                List<PermissionSetAssignment> assignmentsToDelete = new List<PermissionSetAssignment>(); // Current Permission Set Assignments for users who already have one, keyed by AssigneeId.
                List<PermissionSetAssignment> assignmentsToInsert = new List<PermissionSetAssignment>(); // New Permission Set Assignments for users who need to be assigned a new one.

                for (PermissionSet ps : [SELECT Id, Name FROM PermissionSet WHERE Name IN :AIAssistApplicationConstants.PERMISSION_SET_BY_USER_TYPE.values()]) {
                    permissionSetIdByName.put(ps.Name, ps.Id);
                }

                for (PermissionSetAssignment psa : [SELECT Id, AssigneeId, PermissionSetId FROM PermissionSetAssignment WHERE AssigneeId IN :userIds AND PermissionSetId IN :permissionSetIdByName.values()]) {
                    currentAssignmentByUserId.put(psa.AssigneeId, psa);
                }

                for (Id userId : userIds) {

                    String permissionSetName = AIAssistApplicationConstants.PERMISSION_SET_BY_USER_TYPE.get(userTypeByUserId.get(userId));
                    Id desiredPsId = permissionSetName == null ? null : permissionSetIdByName.get(permissionSetName);

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