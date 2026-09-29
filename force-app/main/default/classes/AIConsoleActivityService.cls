/*
Class Name: AIConsoleActivityService

=================================================================
=================================================================

Description: The AI Activity tab's detail views - a conversation's transcript and execution steps
(aiConversationDetail), a violation's detail panel and "Mark as reviewed" (aiViolationDetail), the
Feedback summary (aiFeedbackSummary) and an error log entry (aiPlatformLogDetail). The lists
themselves come from AIConsoleListService.

PII: replies are saved with a conversation's fake PII values, so the transcript swaps the real values
back in for display (as the user saw them) - restorePii and getRealValueByFakeValue are the only
places the console handles a real PII value, kept here so they're easy to audit. The raw masking
pairs ("PII mappings") are only shown to users who may open Settings › PII Registry.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-29     Chandler Stuart          Initial development
*/

public with sharing class AIConsoleActivityService {

    // =============================================================
    // Conversation detail
    // =============================================================

    // stepsForMessageId picks whose execution steps to show - blank shows the first reply that has any.
    public static AIConsoleDataStructure.ConversationDetail getConversationDetail(Id conversationId, Id stepsForMessageId) {

        List<AIConversation__c> conversations = [ SELECT Id, Name, Status__c, OwnerId, Owner.Name, AIAgent__c, AIAgent__r.Name, AIAgent__r.MaxTokensPerConversation__c, AIAgent__r.ObjectType__c,
                                                         AIAgent__r.AIModelConfiguration__r.ModelIdentifier__c, AIPromptTemplate__c, AIPromptTemplate__r.Name, AIPromptTemplate__r.ActivationCriteria__c,
                                                         RelatedRecordId__c, RelatedObjectAPIName__c, Channel__c, ConversationTokenUsage__c, RetentionExpiryDate__c, MessageCount__c
                                                  FROM AIConversation__c WHERE Id = :conversationId LIMIT 1 ];
        if (conversations.isEmpty()) throw new AIConsoleDataStructure.AIConsoleException('That conversation no longer exists, or you can\'t see it.');

        AIConversation__c conversation = conversations[0];
        AIConsoleDataStructure.ConversationDetail detail = new AIConsoleDataStructure.ConversationDetail();
        detail.id = conversation.Id;
        detail.name = conversation.Name;
        detail.status = conversation.Status__c;
        detail.statusVariant = conversation.Status__c == AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE ? 'ok' : '';
        detail.userId = conversation.OwnerId;
        detail.userName = conversation.Owner.Name;
        detail.agentId = conversation.AIAgent__c;
        detail.agentName = conversation.AIAgent__r?.Name;
        detail.recordId = conversation.RelatedRecordId__c;
        detail.templateName = conversation.AIPromptTemplate__r?.Name;
        detail.channel = conversation.Channel__c;
        detail.canClose = conversation.Status__c == AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE;
        detail.canViewPii = canViewPiiMappings();

        Decimal cap = conversation.AIAgent__r?.MaxTokensPerConversation__c;
        detail.tokensLabel = AIConsoleUtility.formatNumber(conversation.ConversationTokenUsage__c == null ? 0 : conversation.ConversationTokenUsage__c) + (cap == null ? '' : ' of ' + AIConsoleUtility.formatNumber(cap));
        detail.retentionLabel = conversation.RetentionExpiryDate__c == null ? 'Set when closed' : AIConsoleUtility.dateLabel(conversation.RetentionExpiryDate__c);

        if (String.isNotBlank(conversation.RelatedRecordId__c)) {
            String label = AIConsoleListService.getRecordLabels(new Set<String>{ conversation.RelatedRecordId__c }).get(conversation.RelatedRecordId__c);
            String objectLabel = AIConsoleUtility.objectLabel(conversation.RelatedObjectAPIName__c);
            detail.recordLabel = (String.isBlank(objectLabel) ? '' : objectLabel + ' · ') + (label == null ? conversation.RelatedRecordId__c : label);
        }

        List<AIConversationMessage__c> messages = [ SELECT Id, Sender__c, MessageBody__c, TokenCount__c, CreatedDate, SuggestedWorkflowActionId__c
                                                    FROM AIConversationMessage__c WHERE AIConversation__c = :conversationId ORDER BY CreatedDate ASC, Id ASC LIMIT 500 ];
        Set<Id> messageIds = new Map<Id, AIConversationMessage__c>(messages).keySet();

        Map<Id, String> ratingByMessage = new Map<Id, String>();
        Integer helpful = 0;
        Integer notHelpful = 0;
        for (AIFeedback__c feedback : [ SELECT AIConversationMessage__c, Rating__c FROM AIFeedback__c WHERE AIConversation__c = :conversationId ORDER BY CreatedDate ASC ]) {
            ratingByMessage.put(feedback.AIConversationMessage__c, feedback.Rating__c);
            if (feedback.Rating__c == AIConsoleConstants.RATING_HELPFUL) helpful++; else notHelpful++;
        }

        Map<Id, List<AIExecutionStep__c>> stepsByMessage = new Map<Id, List<AIExecutionStep__c>>();
        Set<Id> actionsRun = new Set<Id>();
        for (AIExecutionStep__c step : [ SELECT AIConversationMessage__c, StepOrder__c, Status__c, DurationMilliseconds__c, AIDataSource__c, AIDataSource__r.SourceName__c, AIDataSource__r.DeveloperName__c, AIDataSource__r.Name, AIWorkflowAction__c, StepDetail__c
                                         FROM AIExecutionStep__c WHERE AIConversationMessage__c IN :messageIds ORDER BY StepOrder__c ASC ]) {
            if (!stepsByMessage.containsKey(step.AIConversationMessage__c)) stepsByMessage.put(step.AIConversationMessage__c, new List<AIExecutionStep__c>());
            stepsByMessage.get(step.AIConversationMessage__c).add(step);
            if (step.AIWorkflowAction__c != null) actionsRun.add(step.AIConversationMessage__c);
        }

        Set<Id> actionIds = new Set<Id>();
        for (AIConversationMessage__c message : messages) {
            if (String.isNotBlank(message.SuggestedWorkflowActionId__c)) actionIds.add(Id.valueOf(message.SuggestedWorkflowActionId__c));
        }
        Map<Id, AIWorkflowAction__c> actions = new Map<Id, AIWorkflowAction__c>([ SELECT Id, Name, ActionName__c, DeveloperName__c FROM AIWorkflowAction__c WHERE Id IN :actionIds ]);

        Map<String, String> realByFake = getRealValueByFakeValue(conversationId);
        AIConversationMessage__c stepsMessage;

        for (AIConversationMessage__c message : messages) {

            AIConsoleDataStructure.TranscriptMessage view = toTranscriptMessage(message, conversation.Owner.Name, realByFake);
            view.rating = ratingByMessage.get(message.Id);
            view.hasSteps = stepsByMessage.containsKey(message.Id);
            view.suggestedActionRun = actionsRun.contains(message.Id);

            if (String.isNotBlank(message.SuggestedWorkflowActionId__c)) {
                AIWorkflowAction__c action = actions.get(Id.valueOf(message.SuggestedWorkflowActionId__c));
                view.suggestedAction = action == null ? 'A workflow action that no longer exists' : AIConsoleUtility.workflowActionName(action);
            }

            detail.messages.add(view);

            Boolean isRequested = stepsForMessageId != null && message.Id == stepsForMessageId;
            Boolean isDefault = stepsForMessageId == null && stepsMessage == null && view.isAgent && view.hasSteps;
            if (isRequested || isDefault) stepsMessage = message;
        }

        detail.messageCount = messages.size();
        detail.feedbackSummary = helpful + notHelpful == 0 ? 'none' : joinCounts(helpful, 'helpful', notHelpful, 'not helpful');

        Integer violations = [ SELECT COUNT() FROM AIViolation__c WHERE AIConversation__c = :conversationId ];
        detail.violationSummary = violations == 0 ? 'none' : String.valueOf(violations);

        if (stepsMessage != null) {
            detail.stepsForMessageId = stepsMessage.Id;
            detail.stepsForLabel = 'Reply at ' + stepsMessage.CreatedDate.format('HH:mm');
            detail.steps = buildSteps(conversation, stepsMessage, stepsByMessage.get(stepsMessage.Id), actions, realByFake.size());
        }

        return detail;
    }

    private static List<AIConsoleDataStructure.StepView> buildSteps(AIConversation__c conversation, AIConversationMessage__c reply, List<AIExecutionStep__c> steps, Map<Id, AIWorkflowAction__c> actions, Integer maskedValues) {

        List<AIConsoleDataStructure.StepView> views = new List<AIConsoleDataStructure.StepView>();

        if (conversation.AIPromptTemplate__c != null) {
            AIConsoleDataStructure.ActivationCriteria criteria = AIConsoleWizardService.parseCriteria(conversation.AIPromptTemplate__r.ActivationCriteria__c);
            String why = criteria.conditions.isEmpty() ? 'No criteria · the everyday template' : AIConsoleWizardService.criteriaSummary(criteria, conversation.AIAgent__r?.ObjectType__c);
            views.add(stepView('Template selected', conversation.AIPromptTemplate__r.Name + ' · ' + why, true, false));
        }

        if (maskedValues > 0) views.add(stepView('PII masked', maskedValues + (maskedValues == 1 ? ' value replaced' : ' values replaced') + ' before sending', true, false));

        if (steps != null) {
            for (AIExecutionStep__c step : steps) {
                Boolean ok = step.Status__c != AIAssistApplicationConstants.EXECUTION_STEP_STATUS_FAILED;
                String duration = step.DurationMilliseconds__c == null ? null : AIConsoleUtility.formatNumber(step.DurationMilliseconds__c) + ' ms';

                if (step.AIWorkflowAction__c != null) {
                    AIWorkflowAction__c action = actions.get(step.AIWorkflowAction__c);
                    views.add(stepView('Workflow action run', (action == null ? 'Workflow action' : AIConsoleUtility.workflowActionName(action)) + (ok ? '' : ' · failed'), ok, false));
                } else if (step.AIDataSource__c != null) {
                    views.add(stepView('Data source · ' + AIConsoleUtility.dataSourceName(step.AIDataSource__r), (ok ? '' : 'Failed · ') + (duration == null ? 'Called' : duration), ok, false));
                } else {
                    String seconds = step.DurationMilliseconds__c == null ? null : (step.DurationMilliseconds__c / 1000).setScale(2) + ' s';
                    String model = conversation.AIAgent__r?.AIModelConfiguration__r?.ModelIdentifier__c;
                    views.add(stepView('Provider callout', joinParts(new List<String>{ model, seconds, ok ? null : 'failed' }), ok, true));
                }
            }
        }

        if (String.isNotBlank(reply.SuggestedWorkflowActionId__c)) {
            AIWorkflowAction__c action = actions.get(Id.valueOf(reply.SuggestedWorkflowActionId__c));
            views.add(stepView('Workflow action suggested', action == null ? '—' : AIConsoleUtility.workflowActionName(action), true, false));
        }

        for (Integer index = 0; index < views.size(); index++) views[index].stepOrder = index + 1;
        return views;
    }

    public static AIConsoleDataStructure.TranscriptMessage toTranscriptMessage(AIConversationMessage__c message, String userName, Map<String, String> realByFake) {

        AIConsoleDataStructure.TranscriptMessage view = new AIConsoleDataStructure.TranscriptMessage();
        view.id = message.Id;
        view.isUser = message.Sender__c == AIAssistApplicationConstants.SENDER_USER;
        view.isAgent = message.Sender__c == AIAssistApplicationConstants.SENDER_AI_AGENT;
        view.author = view.isUser ? userName : (view.isAgent ? 'AI Agent' : 'System');
        view.timeLabel = message.CreatedDate.date() == System.today() ? message.CreatedDate.format('HH:mm') : message.CreatedDate.format('d MMM, HH:mm');
        view.tokens = view.isAgent ? message.TokenCount__c : null;

        String body = message.MessageBody__c == null ? '' : message.MessageBody__c;
        if (view.isUser && body.contains(AIAssistApplicationConstants.CHAT_COMMAND_PROMPT_SEPARATOR)) body = body.substringBefore(AIAssistApplicationConstants.CHAT_COMMAND_PROMPT_SEPARATOR);
        view.text = view.isAgent ? restorePii(body, realByFake) : body;

        return view;
    }

    public static void closeConversation(Id conversationId) {
        List<AIConversation__c> conversations = [ SELECT Id, Status__c FROM AIConversation__c WHERE Id = :conversationId LIMIT 1 ];
        if (conversations.isEmpty()) throw new AIConsoleDataStructure.AIConsoleException('That conversation no longer exists.');
        if (conversations[0].Status__c != AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE) throw new AIConsoleDataStructure.AIConsoleException('That conversation is already closed.');
        AIConversationMessageService.closeConversation(conversationId, AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_SYSTEM_OVERRIDE);
    }

    // =============================================================
    // PII
    // =============================================================

    // Same permission as Settings › PII Registry, read from its section row.
    public static Boolean canViewPiiMappings() {
        AINavTabSection__mdt section = AINavTabSection__mdt.getInstance(AIConsoleConstants.SECTION_SETTINGS_PII);
        String required = section == null || String.isBlank(section.RequiresPermissionSet__c) ? AIAssistApplicationConstants.PERMISSION_SET_SUPER_USER : section.RequiresPermissionSet__c;
        return AIConsoleUtility.hasPermissionSet(required);
    }

    public static List<AIConsoleDataStructure.PiiMapping> getPiiMappings(Id conversationId) {

        if (!canViewPiiMappings()) throw new AIConsoleDataStructure.AIConsoleException('Seeing PII mappings needs the same permission set as the PII Registry.');

        List<AIConsoleDataStructure.PiiMapping> mappings = new List<AIConsoleDataStructure.PiiMapping>();
        Map<String, String> realToFake = AIPiiMappingService.getMapping(conversationId);
        for (String realValue : realToFake.keySet()) {
            AIConsoleDataStructure.PiiMapping mapping = new AIConsoleDataStructure.PiiMapping();
            mapping.realValue = realValue;
            mapping.fakeValue = realToFake.get(realValue);
            mappings.add(mapping);
        }
        return mappings;
    }

    public static Map<String, String> getRealValueByFakeValue(Id conversationId) {
        Map<String, String> realByFake = new Map<String, String>();
        Map<String, String> realToFake = AIPiiMappingService.getMapping(conversationId);
        for (String realValue : realToFake.keySet()) {
            String fakeValue = realToFake.get(realValue);
            if (String.isNotBlank(fakeValue)) realByFake.put(fakeValue, realValue);
        }
        return realByFake;
    }

    // Longest fake value first, so "Jordan Blake" is restored before "Jordan".
    public static String restorePii(String text, Map<String, String> realByFake) {

        if (String.isBlank(text) || realByFake == null || realByFake.isEmpty()) return text;

        List<String> fakeValues = new List<String>(realByFake.keySet());
        fakeValues.sort(new LongestFirst());

        String restored = text;
        for (String fakeValue : fakeValues) restored = restored.replace(fakeValue, realByFake.get(fakeValue));
        return restored;
    }

    private class LongestFirst implements Comparator<String> {
        public Integer compare(String left, String right) {
            return right.length() - left.length();
        }
    }

    // =============================================================
    // Violations
    // =============================================================

    public static AIConsoleDataStructure.ViolationDetail getViolationDetail(Id violationId) {

        List<AIViolation__c> violations = [ SELECT Id, Name, Severity__c, RequestBlocked__c, CreatedDate, Detail__c, ViolationType__c, ReviewStatus__c, User__c, User__r.Name,
                                                   AIConversation__c, AIConversation__r.Name, AIConversation__r.AIAgent__c, AIConversation__r.AIAgent__r.Name,
                                                   AIViolationRule__c, AIViolationRule__r.RuleName__c, AIViolationRule__r.Agent__c, AIViolationRule__r.TriggerCount__c, AIViolationRule__r.LastTriggeredDate__c
                                            FROM AIViolation__c WHERE Id = :violationId LIMIT 1 ];
        if (violations.isEmpty()) throw new AIConsoleDataStructure.AIConsoleException('That violation no longer exists.');

        AIViolation__c violation = violations[0];
        AIConsoleDataStructure.ViolationDetail detail = new AIConsoleDataStructure.ViolationDetail();
        detail.id = violation.Id;
        detail.name = violation.Name;
        detail.severity = violation.Severity__c;
        detail.requestBlocked = violation.RequestBlocked__c == true;
        detail.title = violation.AIViolationRule__r?.RuleName__c != null ? violation.AIViolationRule__r.RuleName__c : violation.ViolationType__c;
        detail.createdLabel = AIConsoleUtility.dateTimeLabel(violation.CreatedDate);
        detail.detail = violation.Detail__c;
        detail.violationType = violation.ViolationType__c;
        detail.ruleId = violation.AIViolationRule__c;
        detail.ruleName = violation.AIViolationRule__r?.RuleName__c;
        detail.agentId = violation.AIViolationRule__r?.Agent__c != null ? violation.AIViolationRule__r.Agent__c : violation.AIConversation__r?.AIAgent__c;
        detail.agentName = violation.AIConversation__r?.AIAgent__r?.Name;
        detail.userId = violation.User__c;
        detail.userName = violation.User__r?.Name;
        detail.conversationId = violation.AIConversation__c;
        detail.conversationName = violation.AIConversation__r?.Name;
        detail.reviewStatus = String.isBlank(violation.ReviewStatus__c) ? AIConsoleConstants.REVIEW_STATUS_NEW : violation.ReviewStatus__c;

        if (violation.AIViolationRule__c != null) {
            Decimal fired = violation.AIViolationRule__r.TriggerCount__c;
            Date last = violation.AIViolationRule__r.LastTriggeredDate__c;
            detail.ruleFiredLabel = AIConsoleUtility.formatNumber(fired == null ? 0 : fired) + (fired == 1 ? ' time' : ' times') + (last == null ? '' : ' · last ' + (last == System.today() ? 'today' : AIConsoleUtility.dateLabel(last)));
        }

        return detail;
    }

    public static AIConsoleDataStructure.ViolationDetail markViolationReviewed(Id violationId) {
        update new AIViolation__c(Id = violationId, ReviewStatus__c = AIConsoleConstants.REVIEW_STATUS_REVIEWED);
        return getViolationDetail(violationId);
    }

    // =============================================================
    // Feedback
    // =============================================================

    public static AIConsoleDataStructure.FeedbackSummary getFeedbackSummary(String agentId, Integer days) {

        Integer rangeDays = AIConsoleHomeService.normaliseDays(days);
        Datetime rangeStart = Datetime.newInstance(System.today().addDays(1 - rangeDays), Time.newInstance(0, 0, 0, 0));
        Id agentFilter = String.isBlank(agentId) || agentId == 'All' ? null : Id.valueOf(agentId);

        AIConsoleDataStructure.FeedbackSummary summary = new AIConsoleDataStructure.FeedbackSummary();
        summary.agentOptions.add(new AIConsoleDataStructure.Option('All agents', 'All'));
        for (AIAgent__c agent : [ SELECT Id, Name FROM AIAgent__c ORDER BY Name LIMIT 200 ]) summary.agentOptions.add(new AIConsoleDataStructure.Option(agent.Name, agent.Id));

        Map<Id, String> agentNames = new Map<Id, String>();
        Map<Id, Integer> helpfulByAgent = new Map<Id, Integer>();
        Map<Id, Integer> ratingsByAgent = new Map<Id, Integer>();

        for (AggregateResult row : [ SELECT AIConversation__r.AIAgent__c agentId, AIConversation__r.AIAgent__r.Name agentName, Rating__c rating, COUNT(Id) total
                                     FROM AIFeedback__c
                                     WHERE CreatedDate >= :rangeStart
                                     GROUP BY AIConversation__r.AIAgent__c, AIConversation__r.AIAgent__r.Name, Rating__c ]) {
            Id rowAgent = (Id) row.get('agentId');
            if (agentFilter != null && rowAgent != agentFilter) continue;

            Integer total = (Integer) row.get('total');
            agentNames.put(rowAgent, (String) row.get('agentName'));
            ratingsByAgent.put(rowAgent, (ratingsByAgent.containsKey(rowAgent) ? ratingsByAgent.get(rowAgent) : 0) + total);
            summary.ratings += total;

            if ((String) row.get('rating') == AIConsoleConstants.RATING_HELPFUL) {
                summary.helpful += total;
                helpfulByAgent.put(rowAgent, (helpfulByAgent.containsKey(rowAgent) ? helpfulByAgent.get(rowAgent) : 0) + total);
            } else {
                summary.notHelpful += total;
            }
        }

        summary.helpfulPercent = AIConsoleUtility.percent(summary.helpful, summary.ratings);
        summary.replies = agentFilter == null
            ? [ SELECT COUNT() FROM AIConversationMessage__c WHERE Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT AND CreatedDate >= :rangeStart ]
            : [ SELECT COUNT() FROM AIConversationMessage__c WHERE Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT AND CreatedDate >= :rangeStart AND AIConversation__r.AIAgent__c = :agentFilter ];

        for (Id rowAgent : ratingsByAgent.keySet()) {
            if (ratingsByAgent.get(rowAgent) < 10) continue;
            AIConsoleDataStructure.AgentRate rate = new AIConsoleDataStructure.AgentRate();
            rate.name = agentNames.get(rowAgent);
            rate.ratings = ratingsByAgent.get(rowAgent);
            rate.percent = AIConsoleUtility.percent(helpfulByAgent.containsKey(rowAgent) ? helpfulByAgent.get(rowAgent) : 0, rate.ratings);
            summary.byAgent.add(rate);
        }
        summary.byAgent.sort(new RateOrder());

        for (AIFeedback__c feedback : [ SELECT Id, Comment__c, CreatedDate, CreatedBy.Name, AIConversation__c, AIConversation__r.Name, AIConversation__r.AIAgent__c, AIConversation__r.AIAgent__r.Name
                                        FROM AIFeedback__c
                                        WHERE Rating__c = :AIConsoleConstants.RATING_NOT_HELPFUL AND CreatedDate >= :rangeStart
                                        ORDER BY CreatedDate DESC LIMIT 1000 ]) {
            if (agentFilter != null && feedback.AIConversation__r?.AIAgent__c != agentFilter) continue;
            if (String.isBlank(feedback.Comment__c)) continue;

            summary.commentCount++;
            if (summary.comments.size() >= 50) continue;

            AIConsoleDataStructure.FeedbackComment comment = new AIConsoleDataStructure.FeedbackComment();
            comment.id = feedback.Id;
            comment.comment = feedback.Comment__c;
            comment.agentName = feedback.AIConversation__r?.AIAgent__r?.Name;
            comment.userName = feedback.CreatedBy.Name;
            comment.conversationId = feedback.AIConversation__c;
            comment.conversationName = feedback.AIConversation__r?.Name;
            comment.whenLabel = AIConsoleUtility.dayLabel(feedback.CreatedDate);
            summary.comments.add(comment);
        }

        return summary;
    }

    private class RateOrder implements Comparator<AIConsoleDataStructure.AgentRate> {
        public Integer compare(AIConsoleDataStructure.AgentRate left, AIConsoleDataStructure.AgentRate right) {
            return (right.percent == null ? 0 : right.percent) - (left.percent == null ? 0 : left.percent);
        }
    }

    // =============================================================
    // Error log
    // =============================================================

    public static AIConsoleDataStructure.PlatformLogDetail getPlatformLogDetail(Id logId) {

        List<AIPlatformLog__c> logs = [ SELECT Id, Name, ExceptionType__c, ExceptionMessage__c, ClassName__c, MethodName__c, OccurredAt__c, CreatedDate, User__c, User__r.Name, CreatedById, CreatedBy.Name,
                                               RelatedRecordId__c, StackTrace__c, ExceptionLogDetail__c
                                        FROM AIPlatformLog__c WHERE Id = :logId LIMIT 1 ];
        if (logs.isEmpty()) throw new AIConsoleDataStructure.AIConsoleException('That log entry no longer exists.');

        AIPlatformLog__c log = logs[0];
        Datetime occurred = log.OccurredAt__c == null ? log.CreatedDate : log.OccurredAt__c;

        AIConsoleDataStructure.PlatformLogDetail detail = new AIConsoleDataStructure.PlatformLogDetail();
        detail.id = log.Id;
        detail.name = log.Name;
        detail.exceptionType = String.isBlank(log.ExceptionType__c) ? 'Log entry' : log.ExceptionType__c;
        detail.occurredLabel = AIConsoleUtility.dayLabel(occurred) + ', ' + occurred.format('HH:mm:ss');
        detail.message = String.isBlank(log.ExceptionMessage__c) ? log.ExceptionLogDetail__c : log.ExceptionMessage__c;
        detail.className = log.ClassName__c;
        detail.methodName = log.MethodName__c;
        detail.userId = log.User__c != null ? log.User__c : log.CreatedById;
        detail.userName = log.User__c != null ? log.User__r.Name : log.CreatedBy.Name;
        detail.relatedRecordId = log.RelatedRecordId__c;
        try {
            detail.relatedIsConversation = String.isNotBlank(log.RelatedRecordId__c) && Id.valueOf(log.RelatedRecordId__c).getSobjectType() == AIConversation__c.SObjectType;
        } catch (Exception ex) {
            detail.relatedIsConversation = false; // Not an Id - shown as text.
        }
        detail.stackTrace = log.StackTrace__c;
        detail.hintText = buildLogHint(log, occurred);
        return detail;
    }

    private static String buildLogHint(AIPlatformLog__c log, Datetime occurred) {

        Datetime windowStart = occurred.addMinutes(-30);
        Datetime windowEnd = occurred.addMinutes(30);
        Integer similar = [ SELECT COUNT() FROM AIPlatformLog__c WHERE ExceptionType__c = :log.ExceptionType__c AND ClassName__c = :log.ClassName__c AND CreatedDate >= :windowStart AND CreatedDate <= :windowEnd ];

        Boolean isTimeout = log.ExceptionType__c == 'System.CalloutException' && log.ExceptionMessage__c != null && log.ExceptionMessage__c.containsIgnoreCase('timed out');
        String timeoutHint = isTimeout ? 'Matches App Settings › Callout Timeout (' + AIConsoleUtility.formatNumber(AIAssistSettingsService.getCalloutTimeoutMilliseconds()) + ' ms).' : null;
        String similarHint = similar > 1 ? similar + ' like this within half an hour either side.' : null;

        return timeoutHint == null && similarHint == null ? null : joinParts(new List<String>{ timeoutHint, similarHint }).replace(' · ', ' ');
    }

    // =============================================================
    // Helpers
    // =============================================================

    private static AIConsoleDataStructure.StepView stepView(String label, String detail, Boolean isSuccess, Boolean isMono) {
        AIConsoleDataStructure.StepView view = new AIConsoleDataStructure.StepView();
        view.label = label;
        view.detail = detail;
        view.isSuccess = isSuccess;
        view.isMono = isMono;
        return view;
    }

    private static String joinCounts(Integer first, String firstLabel, Integer second, String secondLabel) {
        List<String> parts = new List<String>();
        if (first > 0) parts.add(first + ' ' + firstLabel);
        if (second > 0) parts.add(second + ' ' + secondLabel);
        return String.join(parts, ', ');
    }

    private static String joinParts(List<String> parts) {
        List<String> present = new List<String>();
        for (String part : parts) if (String.isNotBlank(part)) present.add(part);
        return String.join(present, ' · ');
    }
}