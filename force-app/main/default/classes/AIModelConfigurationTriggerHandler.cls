/*
Class Name: AIModelConfigurationTriggerHandler

=================================================================
=================================================================

Description: Handler for managing AI Model Configuration events related to AI Assist,
performing the business logic that runs on the AI Model Configuration trigger.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-09     Chandler Stuart          Initial development
*/

public without sharing class AIModelConfigurationTriggerHandler {

    private static Boolean isBeforeInsertHandlerRunning = false;

    @TestVisible private static Boolean isTestCustomExceptionThrown = false;

    public static void handleBeforeInsert(List<AIModelConfiguration__c> newConfigurations) {
        try {

            if (!isBeforeInsertHandlerRunning) {

                isBeforeInsertHandlerRunning = true;

                if (isTestCustomExceptionThrown) { throw new AIModelConfigurationTriggerHandlerException('Test exception for AIModelConfigurationTriggerHandler.handleBeforeInsert'); }

                AIAssistGlobalUtility.generatePublicId(newConfigurations);

            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIModelConfigurationTriggerHandler', 'handleBeforeInsert');
        }
    }

    public class AIModelConfigurationTriggerHandlerException extends Exception {}
}