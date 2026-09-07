/*
Class Name: AIAgentTriggerHandler

=================================================================
=================================================================

Description: Handler for managing AI Agent events related to AI Assist. 
=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-07     Chandler Stuart          Initial development
*/

public without sharing class AIAgentTriggerHandler {

    private static Boolean isBeforeInsertHandlerRunning = false;

    @TestVisible private static Boolean isTestCustomExceptionThrown = false;

    public static void handleBeforeInsert(List<AIAgent__c> newAgents) {
        try {

            if (!isBeforeInsertHandlerRunning) {

                isBeforeInsertHandlerRunning = true;

                if (isTestCustomExceptionThrown) { throw new AIAgentTriggerHandlerException('Test exception for AIAgentTriggerHandler.handleBeforeInsert'); }

                AIAssistGlobalUtility.generatePublicId(newAgents);
                AIAssistGlobalUtility.generateDeveloperName(newAgents);

            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIAgentTriggerHandler', 'handleBeforeInsert');
        }
    }

    public class AIAgentTriggerHandlerException extends Exception {}
}