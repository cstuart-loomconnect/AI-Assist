/*
Class Name: AIPromptTemplateTriggerHandler

=================================================================
=================================================================

Description: Handler for managing AI Prompt Template events related to AI Assist.

=================================================================
=================================================================

Version      Date               Author                   Description
1.0          2026-09-05         Chandler Stuart          Initial development
*/

public without sharing class AIPromptTemplateTriggerHandler {

    public class AIPromptTemplateTriggerHandlerException extends Exception {}

    private static Boolean isBeforeInsertHandlerRunning = false;

    @TestVisible private static Boolean isTestCustomExceptionThrown = false;

    public static void handleBeforeInsert(List<AIPromptTemplate__c> newTemplates) {
        try {

            if (isBeforeInsertHandlerRunning) return;
            isBeforeInsertHandlerRunning = true;

            if (isTestCustomExceptionThrown) { throw new AIPromptTemplateTriggerHandlerException('Test exception for AIPromptTemplateTriggerHandler.handleBeforeInsert'); }

            AIAssistGlobalUtility.generatePublicId(newTemplates);

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIPromptTemplateTriggerHandler', 'handleBeforeInsert');
        }
    }
}