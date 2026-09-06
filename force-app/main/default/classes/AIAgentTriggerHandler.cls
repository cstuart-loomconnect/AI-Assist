/*
Class Name: AIAgentTriggerHandler

=================================================================
=================================================================

Description: Handler for managing AI Agent events related to AI Assist. 
=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIAgentTriggerHandler {

    private static Boolean isBeforeInsertHandlerRunning = false;

    public static void handleBeforeInsert(List<AIAgent__c> newAgents) {
        try {

            if (!isBeforeInsertHandlerRunning) {

                isBeforeInsertHandlerRunning = true;

                AIAssistGlobalUtility.generatePublicId(newAgents);
                AIAssistGlobalUtility.generateDeveloperName(newAgents);

            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIAgentTriggerHandler', 'handleBeforeInsert');
        }
    }
}