/*
Class Name: AIPromptTemplateTriggerHandler

=================================================================
=================================================================

Description: Handler for managing AI Prompt Template events related to AI Assist.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPromptTemplateTriggerHandler {

    private static Boolean isBeforeInsertHandlerRunning = false;

    public static void handleBeforeInsert(List<AIPromptTemplate__c> newTemplates) {
        try {

            if (!isBeforeInsertHandlerRunning) {

                isBeforeInsertHandlerRunning = true;

                AIAssistGlobalUtility.generatePublicId(newTemplates);

            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIPromptTemplateTriggerHandler', 'handleBeforeInsert');
        }
    }
}