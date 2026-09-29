/*
Class Name: AIChatFeedbackService

=================================================================
=================================================================

Description: Thumbs up / down on an AI reply (submitFeedback) and the first-run terms screen's
"Agree and continue" (acknowledgeTerms) - the two places the running user is recording their own
acknowledgement of something, rather than reading data back.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-28     Chandler Stuart          Split out of AIChatController.
*/

public with sharing class AIChatFeedbackService {

    // One rating per user per message - rating again replaces it. reason is the chip picked on "What went wrong?", kept at the front of the comment.
    public static void submitFeedback(Id messageId, String rating, String reason, String comment) {

        Set<String> validRatings = new Set<String>{ AIAssistApplicationConstants.FEEDBACK_RATING_HELPFUL, AIAssistApplicationConstants.FEEDBACK_RATING_NOT_HELPFUL };
        if (!validRatings.contains(rating)) throw new AIChatDataStructure.AIChatControllerException('Rating must be Helpful or Not Helpful.');

        AIConversationMessage__c message = AIChatConversationService.assertOwnsAgentMessage(messageId);

        String fullComment = String.isBlank(reason) ? comment : '[' + reason + '] ' + (comment == null ? '' : comment);

        List<AIFeedback__c> existingFeedback = [ SELECT Id FROM AIFeedback__c WHERE AIConversationMessage__c = :messageId AND CreatedById = :UserInfo.getUserId() ORDER BY CreatedDate DESC LIMIT 1 ];

        AIFeedback__c feedback = existingFeedback.isEmpty() ? new AIFeedback__c(AIConversationMessage__c = messageId, AIConversation__c = message.AIConversation__c) : existingFeedback[0];
        feedback.Rating__c = rating;
        feedback.Comment__c = String.isBlank(fullComment) ? null : fullComment.trim().left(255);

        upsert feedback;
    }

    // Records the current terms version (AITermsAcknowledgmentTriggerHandler copies it onto AIUserSettings__c).
    public static void acknowledgeTerms() {

        insert new AITermsAcknowledgment__c(
            User__c = UserInfo.getUserId(),
            AcknowledgedDate__c = System.now(),
            TermsVersion__c = AIChatStateService.getCurrentTermsVersion(AIAssistSettingsService.readAppSettings()),
            SignatureText__c = UserInfo.getName().left(120)
        );
    }
}