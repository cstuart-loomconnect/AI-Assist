/*
Class Name: AIModelConfigurationTriggerHandler

=================================================================
=================================================================

Description: Handler for managing AI Model Configuration events related to AI Assist,
performing the business logic that runs on the AI Model Configuration trigger.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIModelConfigurationTriggerHandler {

    private static Boolean isBeforeInsertHandlerRunning = false;
    private static Boolean isBeforeUpdateHandlerRunning = false;

    public static void handleBeforeInsert(List<AIModelConfiguration__c> newConfigurations) {
        try {

            if (!isBeforeInsertHandlerRunning) {

                isBeforeInsertHandlerRunning = true;

                AIAssistGlobalUtility.generatePublicId(newConfigurations);

            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIModelConfigurationTriggerHandler', 'handleBeforeInsert');
        }
    }

    public static void handleBeforeUpdate(List<AIModelConfiguration__c> newConfigurations) {
        try {

            if (!isBeforeUpdateHandlerRunning) {

                isBeforeUpdateHandlerRunning = true;

                AIAssistGlobalUtility.generatePublicId(newConfigurations);

            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIModelConfigurationTriggerHandler', 'handleBeforeUpdate');
        }
    }
}