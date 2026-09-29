/*
Class Name: AIConsoleHomeService

=================================================================
=================================================================

Description: The three Component sections on the AI Home tab - the summary tiles (aiHomeSummary),
"Conversations, last 14 days" (aiHomeTrend) and "Needs attention" (aiHomeAttention). Agent health and
Recent violations are Related List sections and come from AIConsoleListService.

Days is the page's date range (7, 14 or 30), picked in the summary header and shared with the trend.
"Today" numbers always mean today in the running user's time zone.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-29     Chandler Stuart          Initial development
*/

public with sharing class AIConsoleHomeService {

    private static final Integer MAX_ATTENTION_ITEMS = 5;

    public static AIConsoleDataStructure.HomeSummary getSummary(Integer days) {

        Integer rangeDays = normaliseDays(days);
        Datetime rangeStart = Datetime.newInstance(System.today().addDays(1 - rangeDays), Time.newInstance(0, 0, 0, 0));
        Datetime todayStart = Datetime.newInstance(System.today(), Time.newInstance(0, 0, 0, 0));

        AIConsoleDataStructure.HomeSummary summary = new AIConsoleDataStructure.HomeSummary();
        summary.days = rangeDays;
        summary.firstName = UserInfo.getFirstName();
        summary.greeting = greetingFor(Integer.valueOf(System.now().format('H'))) + (String.isBlank(summary.firstName) ? '' : ', ' + summary.firstName);
        summary.dateLabel = 'AI Assist across the org · ' + System.now().format('EEEE d MMMM');

        summary.activeAgents = [ SELECT COUNT() FROM AIAgent__c WHERE IsActive__c = true ];
        summary.testModeAgents = [ SELECT COUNT() FROM AIAgent__c WHERE IsActive__c = true AND IsTestModeEnabled__c = true ];
        summary.draftAgents = [ SELECT COUNT() FROM AIAgent__c WHERE SetupStatus__c != :AIConsoleConstants.SETUP_STATUS_COMPLETE ];

        summary.conversationsToday = [ SELECT COUNT() FROM AIConversation__c WHERE CreatedDate >= :todayStart ];
        summary.usersToday = [ SELECT OwnerId FROM AIConversation__c WHERE CreatedDate >= :todayStart GROUP BY OwnerId ].size();
        summary.recordsToday = [ SELECT RelatedRecordId__c FROM AIConversation__c WHERE CreatedDate >= :todayStart AND RelatedRecordId__c != null GROUP BY RelatedRecordId__c ].size();

        Integer helpfulCount = 0;
        for (AggregateResult result : [ SELECT Rating__c rating, COUNT(Id) total FROM AIFeedback__c WHERE CreatedDate >= :rangeStart GROUP BY Rating__c ]) {
            Integer total = (Integer) result.get('total');
            summary.ratingCount += total;
            if ((String) result.get('rating') == AIConsoleConstants.RATING_HELPFUL) helpfulCount = total;
        }
        summary.helpfulPercent = AIConsoleUtility.percent(helpfulCount, summary.ratingCount);

        Datetime sevenDaysAgo = Datetime.newInstance(System.today().addDays(-6), Time.newInstance(0, 0, 0, 0));
        summary.violationsLast7Days = [ SELECT COUNT() FROM AIViolation__c WHERE CreatedDate >= :sevenDaysAgo ];
        summary.highViolations = [ SELECT COUNT() FROM AIViolation__c WHERE CreatedDate >= :sevenDaysAgo AND Severity__c = :AIConsoleConstants.SEVERITY_HIGH ];
        summary.blockedViolations = [ SELECT COUNT() FROM AIViolation__c WHERE CreatedDate >= :sevenDaysAgo AND RequestBlocked__c = true ];

        summary.tokensToday = AITokenUsageService.getGlobalUsage(System.today(), System.today());
        summary.tokenBudget = AIAssistSettings__c.getOrgDefaults().GlobalTokenBudgetPerDay__c;
        summary.tokenPercent = AIConsoleUtility.percent(summary.tokensToday, summary.tokenBudget);

        return summary;
    }

    public static AIConsoleDataStructure.ConversationTrend getTrend(Integer days) {

        Integer rangeDays = normaliseDays(days);
        Date firstDay = System.today().addDays(1 - rangeDays);
        Datetime rangeStart = Datetime.newInstance(firstDay, Time.newInstance(0, 0, 0, 0));

        Map<Date, Integer> countByDay = new Map<Date, Integer>();
        for (AggregateResult result : [ SELECT DAY_ONLY(convertTimezone(CreatedDate)) day, COUNT(Id) total
                                        FROM AIConversation__c
                                        WHERE CreatedDate >= :rangeStart
                                        GROUP BY DAY_ONLY(convertTimezone(CreatedDate)) ]) {
            countByDay.put((Date) result.get('day'), (Integer) result.get('total'));
        }

        AIConsoleDataStructure.ConversationTrend trend = new AIConsoleDataStructure.ConversationTrend();

        for (Integer offset = 0; offset < rangeDays; offset++) {
            Date day = firstDay.addDays(offset);

            AIConsoleDataStructure.TrendPoint point = new AIConsoleDataStructure.TrendPoint();
            point.day = day;
            point.isToday = day == System.today();
            point.count = countByDay.containsKey(day) ? countByDay.get(day) : 0;
            point.label = point.isToday ? 'Today' : Datetime.newInstance(day, Time.newInstance(12, 0, 0, 0)).format('EEE d MMM');

            trend.points.add(point);
            trend.total += point.count;
            trend.maxValue = Math.max(trend.maxValue, point.count);
        }

        // Round the axis up to the next 10 (47 -> 50), with a floor of 10 so an empty chart still has a scale.
        trend.scaleMax = Math.max(10, (Integer) Math.ceil(trend.maxValue / 10.0) * 10);
        return trend;
    }

    public static List<AIConsoleDataStructure.AttentionItem> getAttentionItems() {

        List<AIConsoleDataStructure.AttentionItem> items = new List<AIConsoleDataStructure.AttentionItem>();

        addHighViolation(items);
        addPiiSyncFailure(items);
        addErrorsToday(items);
        addOldTerms(items);
        addUnfinishedAgents(items);

        while (items.size() > MAX_ATTENTION_ITEMS) items.remove(items.size() - 1);
        return items;
    }

    // =============================================================
    // Needs attention - one item per kind, only when there's something to look at and the user can open where it links
    // =============================================================

    private static void addHighViolation(List<AIConsoleDataStructure.AttentionItem> items) {

        if (!canOpen(AIConsoleConstants.SECTION_ACTIVITY_VIOLATIONS)) return;

        Datetime sevenDaysAgo = System.now().addDays(-7);
        List<AIViolation__c> violations = [ SELECT Id, CreatedDate, ViolationType__c, AIViolationRule__r.RuleName__c, User__r.Name
                                            FROM AIViolation__c
                                            WHERE Severity__c = :AIConsoleConstants.SEVERITY_HIGH AND CreatedDate >= :sevenDaysAgo AND ReviewStatus__c != :AIConsoleConstants.REVIEW_STATUS_REVIEWED
                                            ORDER BY CreatedDate DESC
                                            LIMIT 1 ];
        if (violations.isEmpty()) return;

        AIViolation__c violation = violations[0];
        String what = String.isNotBlank(violation.AIViolationRule__r?.RuleName__c) ? violation.AIViolationRule__r.RuleName__c : violation.ViolationType__c;

        items.add(newItem('violation', 'High-severity violation', joinParts(new List<String>{ what, violation.User__r?.Name, AIConsoleUtility.relativeLabel(violation.CreatedDate) }),
                          new AIConsoleDataStructure.NavTarget(AIConsoleConstants.TAB_ACTIVITY, AIConsoleConstants.SECTION_ACTIVITY_VIOLATIONS, AIConsoleConstants.VIEW_RECORD, violation.Id)));
    }

    private static void addPiiSyncFailure(List<AIConsoleDataStructure.AttentionItem> items) {

        if (!canOpen(AIConsoleConstants.SECTION_SETTINGS_PII)) return;

        List<AIPIIRegistry__c> failed = [ SELECT Id, ObjectAPIName__c FROM AIPIIRegistry__c WHERE SyncStatus__c = :AIAssistApplicationConstants.PII_SYNC_STATUS_FAILED AND Active__c = true ORDER BY LastModifiedDate DESC ];
        if (failed.isEmpty()) return;

        String title = failed.size() == 1 ? 'PII sync failed for ' + failed[0].ObjectAPIName__c : 'PII sync failed for ' + failed.size() + ' objects';
        String cause = latestPiiSyncError();

        items.add(newItem('pii', title, joinParts(new List<String>{ cause, 'using the last good sync' }),
                          new AIConsoleDataStructure.NavTarget(AIConsoleConstants.TAB_SETTINGS, AIConsoleConstants.SECTION_SETTINGS_PII, null, null)));
    }

    private static void addErrorsToday(List<AIConsoleDataStructure.AttentionItem> items) {

        if (!canOpen(AIConsoleConstants.SECTION_ACTIVITY_ERROR_LOG)) return;

        Datetime todayStart = Datetime.newInstance(System.today(), Time.newInstance(0, 0, 0, 0));
        List<AIPlatformLog__c> logs = [ SELECT ExceptionType__c, ExceptionMessage__c FROM AIPlatformLog__c WHERE CreatedDate >= :todayStart ORDER BY CreatedDate DESC LIMIT 200 ];
        if (logs.isEmpty()) return;

        Integer calloutErrors = 0;
        for (AIPlatformLog__c log : logs) {
            if (log.ExceptionType__c == 'System.CalloutException') calloutErrors++;
        }

        Boolean allCallouts = calloutErrors == logs.size();
        String noun = allCallouts ? (logs.size() == 1 ? 'callout error' : 'callout errors') : (logs.size() == 1 ? 'error' : 'errors');

        items.add(newItem('error', logs.size() + ' ' + noun + ' today', 'Latest: ' + (String.isBlank(logs[0].ExceptionMessage__c) ? logs[0].ExceptionType__c : logs[0].ExceptionMessage__c),
                          new AIConsoleDataStructure.NavTarget(AIConsoleConstants.TAB_ACTIVITY, AIConsoleConstants.SECTION_ACTIVITY_ERROR_LOG, null, null)));
    }

    private static void addOldTerms(List<AIConsoleDataStructure.AttentionItem> items) {

        if (!canOpen(AIConsoleConstants.SECTION_SETTINGS_TERMS)) return;

        String currentVersion = AIConsoleSettingsService.getCurrentTermsVersion();
        Integer outOfDate = [ SELECT COUNT() FROM AIUserSettings__c WHERE IsActive__c = true AND (TermsVersionAcknowledged__c != :currentVersion OR TermsVersionAcknowledged__c = null) ];
        if (outOfDate == 0) return;

        items.add(newItem('terms', outOfDate + (outOfDate == 1 ? ' user on old terms' : ' users on old terms'), 'They’ll be asked to sign version ' + currentVersion + ' next time',
                          new AIConsoleDataStructure.NavTarget(AIConsoleConstants.TAB_SETTINGS, AIConsoleConstants.SECTION_SETTINGS_TERMS, null, null)));
    }

    private static void addUnfinishedAgents(List<AIConsoleDataStructure.AttentionItem> items) {

        List<AIAgent__c> drafts = [ SELECT Id, Name, SetupCurrentStep__c FROM AIAgent__c WHERE SetupStatus__c != :AIConsoleConstants.SETUP_STATUS_COMPLETE ORDER BY SetupLastEdited__c DESC NULLS LAST, LastModifiedDate DESC ];
        if (drafts.isEmpty()) return;

        String title = drafts.size() + (drafts.size() == 1 ? ' agent unfinished' : ' agents unfinished');
        String detail = drafts[0].Name + ' is on step ' + AIConsoleUtility.setupStep(drafts[0]) + ' of ' + AIConsoleConstants.WIZARD_STEP_COUNT;

        items.add(newItem('draft', title, detail, new AIConsoleDataStructure.NavTarget(AIConsoleConstants.TAB_AGENTS, AIConsoleConstants.SECTION_AGENTS_DRAFTS, null, null)));
    }

    // =============================================================
    // Helpers
    // =============================================================

    private static String latestPiiSyncError() {
        List<AIPlatformLog__c> logs = [ SELECT ExceptionMessage__c FROM AIPlatformLog__c WHERE ClassName__c LIKE 'AIPiiRegistry%' ORDER BY CreatedDate DESC LIMIT 1 ];
        return logs.isEmpty() || String.isBlank(logs[0].ExceptionMessage__c) ? null : logs[0].ExceptionMessage__c.left(80);
    }

    private static Boolean canOpen(String sectionDeveloperName) {
        AINavTabSection__mdt section = AINavTabSection__mdt.getInstance(sectionDeveloperName);
        return section != null && section.Active__c == true && AIConsoleUtility.hasPermissionSet(section.RequiresPermissionSet__c);
    }

    private static AIConsoleDataStructure.AttentionItem newItem(String kind, String title, String detail, AIConsoleDataStructure.NavTarget target) {
        AIConsoleDataStructure.AttentionItem item = new AIConsoleDataStructure.AttentionItem();
        item.kind = kind;
        item.title = title;
        item.detail = detail;
        item.target = target;
        return item;
    }

    private static String joinParts(List<String> parts) {
        List<String> present = new List<String>();
        for (String part : parts) {
            if (String.isNotBlank(part)) present.add(part);
        }
        return String.join(present, ' · ');
    }

    private static String greetingFor(Integer hour) {
        if (hour < 12) return 'Good morning';
        if (hour < 18) return 'Good afternoon';
        return 'Good evening';
    }

    public static Integer normaliseDays(Integer days) {
        if (days == null || days < 1) return AIConsoleConstants.HOME_TREND_DEFAULT_DAYS;
        return Math.min(days, 90);
    }
}