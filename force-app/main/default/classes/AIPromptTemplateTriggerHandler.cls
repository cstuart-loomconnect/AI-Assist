/*
Class Name: AIPromptTemplateTriggerHandler

=================================================================
=================================================================

Description: Handler for managing AI Prompt Template events related to AI Assist.
Generates PublicId__c when blank on insert and update.

=================================================================
=================================================================

Version      Date            Author                   Description
1.0          2026-09-05      Chandler Stuart          Initial development
*/

public without sharing class AIPromptTemplateTriggerHandler {

    private static Boolean isBeforeInsertHandlerRunning = false;
    private static Boolean isBeforeUpdateHandlerRunning = false;

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