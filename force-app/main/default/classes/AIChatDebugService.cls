/*
Class Name: AIChatDebugService

=================================================================
=================================================================

Description: Debug mode's request trace for one AI reply (getDebugTrace), its execution steps,
and the "pii mappings" modal (getPiiMappings) - loaded only when asked for, since it holds the
real values. Also the "Couldn't reach the AI service" card's failure detail (getFailureDetail).

Every method here that touches a real PII value - restorePii and getRealValueByFakeValue - is
kept in this one small, easy-to-audit class, which matters for Security Review. AI replies are
saved with the conversation's fake PII values (so later turns resend only masked history to the
model); restorePii is how AIChatConversationService swaps the real values back in when a reply is
read for display or export, without needing to hold them itself.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-28     Chandler Stuart          Split out of AIChatController.
1.1          2026-09-28     Chandler Stuart          getDebugTrace also reads AIExecutionStep__c's DurationMilliseconds__c, ToolCallingIterationsUsed__c/Max__c, AttemptNumber__c, SentPreviewText__c, RequestJson__c and ResponseJson__c - written by AIExecutionStepRecorder, only present for a reply captured with debug mode on.
*/

public with sharing class AIChatDebugService {

    // Debug mode's request trace for one AI reply. Callers must already have checked AIUserSettings__c.DebugModeEnabled__c and resolved reply via AIChatConversationService.assertOwnsAgentMessage.
    public static AIChatDataStructure.DebugTrace getDebugTrace(AIConversationMessage__c reply) {

        AIChatDataStructure.DebugTrace trace = new AIChatDataStructure.DebugTrace();
        trace.conversationId = reply.AIConversation__c;
        trace.conversationName = reply.AIConversation__r.Name;
        trace.conversationPublicId = reply.AIConversation__r.PublicId__c;
        trace.replyMessageId = reply.Id;
        trace.replyTokens = reply.TokenCount__c;

        List<AIConversationMessage__c> promptMessages = [ SELECT Id, TokenCount__c, CreatedDate
                                                          FROM AIConversationMessage__c
                                                          WHERE AIConversation__c = :reply.AIConversation__c
                                                          AND Sender__c = :AIAssistApplicationConstants.SENDER_USER
                                                          AND CreatedDate <= :reply.CreatedDate
                                                          ORDER BY CreatedDate DESC, Id DESC
                                                          LIMIT 1 ];

        if (!promptMessages.isEmpty()) {
            trace.userMessageId = promptMessages[0].Id;
            trace.promptTokens = promptMessages[0].TokenCount__c;
            trace.durationMs = reply.CreatedDate.getTime() - promptMessages[0].CreatedDate.getTime();
        }

        List<AIConversation__c> conversations = [ SELECT AIAgent__r.AIModelConfiguration__r.DeveloperName__c, AIAgent__r.AIModelConfiguration__r.AIProvider__c, AIAgent__r.AIModelConfiguration__r.ModelIdentifier__c
                                                  FROM AIConversation__c WHERE Id = :reply.AIConversation__c LIMIT 1 ];

        if (!conversations.isEmpty() && conversations[0].AIAgent__r != null && conversations[0].AIAgent__r.AIModelConfiguration__r != null) {
            AIModelConfiguration__c modelConfiguration = conversations[0].AIAgent__r.AIModelConfiguration__r;
            trace.modelConfiguration = modelConfiguration.DeveloperName__c;
            trace.provider = modelConfiguration.AIProvider__c;
            trace.model = modelConfiguration.ModelIdentifier__c;
        }

        for (AIExecutionStep__c step : [ SELECT StepOrder__c, Status__c, StepDetail__c, DurationMilliseconds__c, AIDataSource__r.DeveloperName__c, AIWorkflowAction__r.ActionName__c,
                                                 ToolCallingIterationsUsed__c, ToolCallingIterationsMax__c, AttemptNumber__c, SentPreviewText__c, RequestJson__c, ResponseJson__c
                                         FROM AIExecutionStep__c WHERE AIConversationMessage__c = :reply.Id ORDER BY StepOrder__c ]) {
            trace.steps.add(AIChatConversationService.toExecutionStep(step));
            if (step.AIDataSource__c != null) trace.toolCalls++;
            if (step.Status__c == AIAssistApplicationConstants.EXECUTION_STEP_STATUS_FAILED) trace.isSuccess = false;

            // Every step of a reply carries the same iterations/attempt (AIExecutionStepRecorder sets them uniformly); only the last callout step carries the request/response detail.
            if (step.ToolCallingIterationsUsed__c != null) trace.toolCallingIterationsUsed = step.ToolCallingIterationsUsed__c.intValue();
            if (step.ToolCallingIterationsMax__c != null) trace.toolCallingIterationsMax = step.ToolCallingIterationsMax__c.intValue();
            if (step.AttemptNumber__c != null) trace.attemptNumber = step.AttemptNumber__c.intValue();
            if (String.isNotBlank(step.RequestJson__c)) trace.requestJson = step.RequestJson__c;
            if (String.isNotBlank(step.ResponseJson__c)) trace.responseJson = step.ResponseJson__c;
            if (String.isNotBlank(step.SentPreviewText__c)) trace.sentPreviewText = step.SentPreviewText__c;
        }

        trace.piiFieldsMasked = countPiiMappings(reply.AIConversation__c);

        return trace;
    }

    // Debug mode's PII masking pairs for the conversation (real value -> masked value) as pretty-printed JSON, sorted by real value. Callers must already have checked debug mode - same gate as getDebugTrace.
    public static String getPiiMappings(Id conversationId) {

        Map<String, String> maskedValueByRealValue = AIPiiMappingService.getMapping(conversationId);

        List<String> realValues = new List<String>(maskedValueByRealValue.keySet());
        realValues.sort();

        Map<String, String> sortedMappings = new Map<String, String>();
        for (String realValue : realValues) sortedMappings.put(realValue, maskedValueByRealValue.get(realValue));

        return JSON.serializePretty(sortedMappings);
    }

    // Shown on the "Couldn't reach the AI service" card - the platform log reference to quote to an admin and, when includeDebugDetail is true, the detailed failure recorded on the failed-turn System message.
    public static AIChatDataStructure.FailureDetail getFailureDetail(Id conversationId, Boolean includeDebugDetail) {

        AIChatDataStructure.FailureDetail detail = new AIChatDataStructure.FailureDetail();
        detail.reference = new SystemContext().getLatestLogReference(UserInfo.getUserId());

        if (includeDebugDetail) {
            List<AIConversationMessage__c> failedTurns = [ SELECT MessageBody__c FROM AIConversationMessage__c
                                                           WHERE AIConversation__c = :conversationId AND Sender__c = :AIAssistApplicationConstants.SENDER_SYSTEM
                                                           ORDER BY CreatedDate DESC, Id DESC LIMIT 1 ];
            if (!failedTurns.isEmpty()) detail.debugDetail = failedTurns[0].MessageBody__c;
        }

        return detail;
    }

    private static Integer countPiiMappings(Id conversationId) {

        Integer mappedValues = 0;

        for (AIPIIMapping__c mapping : [ SELECT MappingJson__c FROM AIPIIMapping__c WHERE AIConversation__c = :conversationId ]) {
            if (String.isBlank(mapping.MappingJson__c)) continue;
            try {
                Object parsed = JSON.deserializeUntyped(mapping.MappingJson__c);
                if (parsed instanceof Map<String, Object>) mappedValues += ((Map<String, Object>) parsed).size();
                else if (parsed instanceof List<Object>) mappedValues += ((List<Object>) parsed).size();
            } catch (Exception malformedMapping) {
                continue;
            }
        }

        return mappedValues;
    }

    // Fake value -> real value from the conversation's AIPIIMapping__c. Blank when nothing was masked.
    public static Map<String, String> getRealValueByFakeValue(Id conversationId) {

        Map<String, String> realValueByFakeValue = new Map<String, String>();
        Map<String, String> fakeValueByRealValue = AIPiiMappingService.getMapping(conversationId);

        for (String realValue : fakeValueByRealValue.keySet()) realValueByFakeValue.put(fakeValueByRealValue.get(realValue), realValue);

        return realValueByFakeValue;
    }

    // Swaps each fake value in an AI reply back to its real value. Longest first, so a fake value that contains another ("Morgan Reyes" / "Morgan") is replaced whole.
    public static String restorePii(String text, Map<String, String> realValueByFakeValue) {

        if (String.isBlank(text) || realValueByFakeValue == null || realValueByFakeValue.isEmpty()) return text;

        List<String> fakeValues = new List<String>(realValueByFakeValue.keySet());
        fakeValues.sort(new LongestFirst());

        String restoredText = text;
        for (String fakeValue : fakeValues) {
            if (String.isNotBlank(fakeValue)) restoredText = restoredText.replace(fakeValue, realValueByFakeValue.get(fakeValue));
        }

        return restoredText;
    }

    private class LongestFirst implements Comparator<String> {
        public Integer compare(String first, String second) {
            return second.length() - first.length();
        }
    }

    // AIPlatformLog__c rows are created by the platform event trigger, so the user usually can't see them through sharing - only the reference is read, for the user's own most recent log.
    private without sharing class SystemContext {

        public String getLatestLogReference(Id userId) {

            Datetime since = System.now().addMinutes(-15);

            List<AIPlatformLog__c> logs = [ SELECT Name FROM AIPlatformLog__c WHERE User__c = :userId AND CreatedDate >= :since ORDER BY CreatedDate DESC LIMIT 1 ];
            return logs.isEmpty() ? null : logs[0].Name;
        }
    }
}