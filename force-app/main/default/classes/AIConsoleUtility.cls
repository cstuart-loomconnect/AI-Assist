/*
Class Name: AIConsoleUtility

=================================================================
=================================================================

Description: Small helpers every AI Assist console service shares - who may open the console (and each
section of it), the date and number labels the design uses ("Today, 14:31", "40 min ago", "24 Sep 2026"),
the org namespace (so App Page tabs can be navigated to in a packaged org) and badge variants for
statuses that appear on several screens.

Access model: the console is for users holding AIAssistAdminUser or AIAssistSuperUser (or Modify All
Data). A section with AINavTabSection__mdt.RequiresPermissionSet__c additionally needs that Permission
Set - the same rule aiTabPage uses to hide it, enforced again here for every Apex call behind it.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-29     Chandler Stuart          Initial development
*/

public with sharing class AIConsoleUtility {

    private static Set<String> assignedPermissionSets;
    private static Boolean hasModifyAllData;

    // =============================================================
    // Access
    // =============================================================

    public static Set<String> getAssignedPermissionSets() {

        if (assignedPermissionSets != null) return assignedPermissionSets;

        assignedPermissionSets = new Set<String>();
        for (PermissionSetAssignment assignment : [ SELECT PermissionSet.Name FROM PermissionSetAssignment WHERE AssigneeId = :UserInfo.getUserId() ]) {
            assignedPermissionSets.add(assignment.PermissionSet.Name);
        }

        return assignedPermissionSets;
    }

    public static Boolean hasPermissionSet(String permissionSetName) {
        if (String.isBlank(permissionSetName)) return true;
        return getAssignedPermissionSets().contains(permissionSetName.trim()) || isModifyAllDataUser();
    }

    public static Boolean isModifyAllDataUser() {

        if (hasModifyAllData != null) return hasModifyAllData;

        List<Profile> profiles = [ SELECT PermissionsModifyAllData FROM Profile WHERE Id = :UserInfo.getProfileId() LIMIT 1 ];
        hasModifyAllData = !profiles.isEmpty() && profiles[0].PermissionsModifyAllData == true;
        return hasModifyAllData;
    }

    public static Boolean hasConsoleAccess() {
        Set<String> assigned = getAssignedPermissionSets();
        return assigned.contains(AIAssistApplicationConstants.PERMISSION_SET_ADMIN_USER) || assigned.contains(AIAssistApplicationConstants.PERMISSION_SET_SUPER_USER) || isModifyAllDataUser();
    }

    public static void assertConsoleAccess() {
        if (!hasConsoleAccess()) throw new AIConsoleDataStructure.AIConsoleException('The AI Assist console needs the AI Assist Admin User or Super User permission set.');
    }

    // Every Apex call behind a locked section goes through here, so hiding the section in aiTabPage isn't the only thing stopping it.
    public static void assertSectionAccess(String sectionDeveloperName) {

        assertConsoleAccess();

        AINavTabSection__mdt section = AINavTabSection__mdt.getInstance(sectionDeveloperName);
        if (section == null || String.isBlank(section.RequiresPermissionSet__c)) return;

        if (!hasPermissionSet(section.RequiresPermissionSet__c)) throw new AIConsoleDataStructure.AIConsoleException('You need the ' + section.RequiresPermissionSet__c + ' permission set to use ' + section.SectionLabel__c + '.');
    }

    // =============================================================
    // Namespace
    // =============================================================

    public static String getNamespacePrefix() {
        String className = AIConsoleUtility.class.getName();
        return className.contains('.') ? className.substringBefore('.') + '__' : '';
    }

    // =============================================================
    // Labels
    // =============================================================

    // "Today, 14:31" / "Yesterday, 16:20" / "24 Sep 2026"
    public static String dateTimeLabel(Datetime value) {
        if (value == null) return null;
        String dayPart = relativeDay(value.date());
        return dayPart != null ? dayPart + ', ' + value.format('HH:mm') : value.format('d MMM yyyy');
    }

    // "Today, 13:02" / "Yesterday, 16:20" / "24 Sep, 09:10"
    public static String shortDateTimeLabel(Datetime value) {
        if (value == null) return null;
        String dayPart = relativeDay(value.date());
        return (dayPart != null ? dayPart : value.format('d MMM')) + ', ' + value.format('HH:mm');
    }

    // "40 min ago" / "2 h ago" / "Yesterday" / "24 Sep"
    public static String relativeLabel(Datetime value) {

        if (value == null) return null;

        Long minutes = (System.now().getTime() - value.getTime()) / 60000;
        if (minutes < 1) return 'Just now';
        if (minutes < 60) return minutes + ' min ago';
        if (value.date() == System.today()) return (minutes / 60) + ' h ago';
        if (value.date() == System.today().addDays(-1)) return 'Yesterday';
        return value.format('d MMM');
    }

    // "Today" / "Yesterday" / "24 Sep"
    public static String dayLabel(Datetime value) {
        if (value == null) return null;
        String dayPart = relativeDay(value.date());
        return dayPart != null ? dayPart : value.format('d MMM');
    }

    public static String dateLabel(Date value) {
        if (value == null) return null;
        return Datetime.newInstance(value, Time.newInstance(12, 0, 0, 0)).format('d MMM yyyy');
    }

    private static String relativeDay(Date value) {
        if (value == System.today()) return 'Today';
        if (value == System.today().addDays(-1)) return 'Yesterday';
        return null;
    }

    public static String formatNumber(Decimal value) {
        if (value == null) return '—';
        return value.setScale(0, RoundingMode.HALF_UP).format();
    }

    // "16.9k" / "128.4k" / "1.2M" - the compact form the agent record's stats use.
    public static String compactNumber(Decimal value) {
        if (value == null) return '0';
        if (value >= 1000000) return (value / 1000000).setScale(1).stripTrailingZeros().toPlainString() + 'M';
        if (value >= 1000) return (value / 1000).setScale(1).stripTrailingZeros().toPlainString() + 'k';
        return value.setScale(0).format();
    }

    public static Integer percent(Decimal part, Decimal whole) {
        if (whole == null || whole == 0 || part == null) return null;
        return Integer.valueOf((part * 100 / whole).setScale(0, RoundingMode.HALF_UP));
    }

    public static String initials(String fullName) {

        if (String.isBlank(fullName)) return '';

        List<String> parts = fullName.trim().split('\\s+');
        String first = parts[0].left(1);
        String last = parts.size() > 1 ? parts[parts.size() - 1].left(1) : '';
        return (first + last).toUpperCase();
    }

    public static String objectLabel(String objectApiName) {

        if (String.isBlank(objectApiName)) return objectApiName;

        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        return objectType == null ? objectApiName : objectType.getDescribe().getLabel();
    }

    // AIDataSource__c.Name and AIWorkflowAction__c.Name are auto-numbers - the readable name is Source Name / Action Name, falling back to the Developer Name.
    public static String dataSourceName(AIDataSource__c source) {
        if (source == null) return null;
        if (String.isNotBlank(source.SourceName__c)) return source.SourceName__c;
        return String.isNotBlank(source.DeveloperName__c) ? source.DeveloperName__c : source.Name;
    }

    public static String workflowActionName(AIWorkflowAction__c action) {
        if (action == null) return null;
        if (String.isNotBlank(action.ActionName__c)) return action.ActionName__c;
        return String.isNotBlank(action.DeveloperName__c) ? action.DeveloperName__c : action.Name;
    }

    public static Integer toInteger(Decimal value) {
        return value == null ? null : value.intValue();
    }

    // =============================================================
    // Agent status (shared by Home, the Agents list and the agent record)
    // =============================================================

    public static String agentStatusLabel(AIAgent__c agent) {
        if (agent.IsActive__c == true && agent.IsTestModeEnabled__c == true) return 'Test mode';
        return agent.IsActive__c == true ? 'Active' : 'Inactive';
    }

    public static String agentStatusVariant(AIAgent__c agent) {
        if (agent.IsActive__c == true && agent.IsTestModeEnabled__c == true) return 'test';
        return agent.IsActive__c == true ? 'ok' : '';
    }

    public static Boolean isSetupComplete(AIAgent__c agent) {
        return agent.SetupStatus__c == AIConsoleConstants.SETUP_STATUS_COMPLETE;
    }

    public static Integer setupStep(AIAgent__c agent) {
        Integer step = agent.SetupCurrentStep__c == null ? 1 : agent.SetupCurrentStep__c.intValue();
        return Math.max(1, Math.min(AIConsoleConstants.WIZARD_STEP_COUNT, step));
    }
}
