/*
Class Name: AIConsoleNavService

=================================================================
=================================================================

Description: Reads the console's navigation from Custom Metadata. Salesforce draws the nav bar from the
AI Assist app's tab list (one Lightning App Page per tab); each page holds aiTabPage, whose one design
attribute names its AINavTab__mdt record. This service loads that record and its active
AINavTabSection__mdt rows:

- Sub Navigation rows build the left rail - one item per row, opening ComponentAPIName__c.
- Component and Related List rows stack in the page, in Display Order, sized by SectionWidth__c.
- RequiresPermissionSet__c hides a section from users without that Permission Set (and shows a lock
  on it for those who have it).
- BadgeFilterCriteria__c counts RelatedObjectAPIName__c records for the number beside a rail item.

The full list of active tabs comes back too (TabConfig.tabs), resolved to their CustomTab API names
with the org namespace, so any section can link across tabs.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-29     Chandler Stuart          Initial development
*/

public with sharing class AIConsoleNavService {

    public static AIConsoleDataStructure.TabConfig getTabConfig(String tabName) {

        if (String.isBlank(tabName)) throw new AIConsoleDataStructure.AIConsoleException('This page has no AI Nav Tab set. Edit the page and set the aiTabPage component\'s Tab Name.');

        AINavTab__mdt tab = AINavTab__mdt.getInstance(tabName.trim());
        if (tab == null) throw new AIConsoleDataStructure.AIConsoleException('No AI Nav Tab record is named "' + tabName + '". Check Setup › Custom Metadata Types › AI Nav Tab.');

        AIConsoleDataStructure.TabConfig config = new AIConsoleDataStructure.TabConfig();
        config.tabName = tab.DeveloperName;
        config.label = tab.MasterLabel;
        config.description = tab.Description__c;
        config.isActive = tab.Active__c == true;
        config.isDefaultLanding = tab.IsDefaultLandingTab__c == true;
        config.externalUrl = tab.ExternalURLOverride__c;
        config.openInNewTab = tab.OpenInNewTab__c == true;
        config.tabs = getTabLinks();

        if (!config.isActive) return config;

        for (AINavTabSection__mdt section : getSections(tab.DeveloperName)) {
            if (!AIConsoleUtility.hasPermissionSet(section.RequiresPermissionSet__c)) continue;
            config.sections.add(toSectionConfig(section));
        }

        return config;
    }

    public static List<AIConsoleDataStructure.TabLink> getTabLinks() {

        List<AINavTab__mdt> tabs = AINavTab__mdt.getAll().values();
        tabs.sort(new TabOrder());

        String namespacePrefix = AIConsoleUtility.getNamespacePrefix();
        List<AIConsoleDataStructure.TabLink> links = new List<AIConsoleDataStructure.TabLink>();

        for (AINavTab__mdt tab : tabs) {
            if (tab.Active__c != true) continue;

            AIConsoleDataStructure.TabLink link = new AIConsoleDataStructure.TabLink();
            link.tabName = tab.DeveloperName;
            link.label = tab.MasterLabel;
            link.navItemApiName = namespacePrefix + (String.isBlank(tab.TargetPage__c) ? tab.DeveloperName : tab.TargetPage__c.trim());
            link.externalUrl = tab.ExternalURLOverride__c;
            link.openInNewTab = tab.OpenInNewTab__c == true;
            links.add(link);
        }

        return links;
    }

    // Active sections of one tab, in Display Order.
    public static List<AINavTabSection__mdt> getSections(String tabDeveloperName) {

        List<AINavTabSection__mdt> sections = new List<AINavTabSection__mdt>();

        for (AINavTabSection__mdt section : [ SELECT DeveloperName, SectionLabel__c, SectionType__c, ComponentAPIName__c, RelatedObjectAPIName__c, FilterCriteria__c,
                                                     BadgeFilterCriteria__c, MaxRecordsShown__c, SectionIcon__c, SectionWidth__c, CollapsedByDefault__c, ExternalURLOverride__c,
                                                     OpenInNewTab__c, RequiresPermissionSet__c, DisplayOrder__c, Active__c, ParentTab__r.DeveloperName
                                              FROM AINavTabSection__mdt
                                              WHERE Active__c = true
                                              ORDER BY DisplayOrder__c ASC NULLS LAST, SectionLabel__c ASC ]) {

            if (section.ParentTab__r?.DeveloperName == tabDeveloperName) sections.add(section);
        }

        return sections;
    }

    // One section's row, for services that need its object, filter or row cap - the section must be active and open to the user.
    public static AINavTabSection__mdt getSection(String sectionDeveloperName) {

        AINavTabSection__mdt section = AINavTabSection__mdt.getInstance(sectionDeveloperName);
        if (section == null || section.Active__c != true) throw new AIConsoleDataStructure.AIConsoleException('This section isn\'t available.');

        AIConsoleUtility.assertSectionAccess(sectionDeveloperName);
        return section;
    }

    private static AIConsoleDataStructure.SectionConfig toSectionConfig(AINavTabSection__mdt section) {

        AIConsoleDataStructure.SectionConfig config = new AIConsoleDataStructure.SectionConfig();
        config.developerName = section.DeveloperName;
        config.label = String.isBlank(section.SectionLabel__c) ? section.DeveloperName : section.SectionLabel__c;
        config.sectionType = section.SectionType__c;
        config.componentName = String.isBlank(section.ComponentAPIName__c) ? null : section.ComponentAPIName__c.trim();
        config.objectApiName = section.RelatedObjectAPIName__c;
        config.filterCriteria = section.FilterCriteria__c;
        config.maxRecords = AIConsoleUtility.toInteger(section.MaxRecordsShown__c);
        config.icon = section.SectionIcon__c;
        config.width = String.isBlank(section.SectionWidth__c) ? 'Full' : section.SectionWidth__c;
        config.collapsedByDefault = section.CollapsedByDefault__c == true;
        config.externalUrl = section.ExternalURLOverride__c;
        config.openInNewTab = section.OpenInNewTab__c == true;
        config.requiresPermissionSet = section.RequiresPermissionSet__c;
        config.isLocked = String.isNotBlank(section.RequiresPermissionSet__c);
        config.displayOrder = AIConsoleUtility.toInteger(section.DisplayOrder__c);

        // A Related List with no component of its own renders through the generic list.
        if (config.componentName == null && config.sectionType == AIConsoleConstants.SECTION_TYPE_RELATED_LIST) config.componentName = 'aiRecordList';

        Boolean hasBadge = section.SectionType__c == AIConsoleConstants.SECTION_TYPE_SUB_NAVIGATION && String.isNotBlank(section.BadgeFilterCriteria__c) && String.isNotBlank(section.RelatedObjectAPIName__c);
        if (hasBadge) {
            config.badgeCount = countRecords(section.RelatedObjectAPIName__c, section.BadgeFilterCriteria__c);
            config.hasBadge = config.badgeCount != null;
        }

        return config;
    }

    // Criteria come from protected, developer-controlled Custom Metadata, never user input. A bad filter hides the badge rather than breaking the page.
    public static Integer countRecords(String objectApiName, String criteria) {
        try {

            String query = 'SELECT COUNT() FROM ' + String.escapeSingleQuotes(objectApiName.trim()) + (String.isBlank(criteria) ? '' : ' WHERE ' + criteria);
            return Database.countQuery(query, AccessLevel.USER_MODE);

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIConsoleNavService', 'countRecords');
            return null;
        }
    }

    private class TabOrder implements Comparator<AINavTab__mdt> {
        public Integer compare(AINavTab__mdt left, AINavTab__mdt right) {
            Decimal leftOrder = left.DisplayOrder__c == null ? 9999 : left.DisplayOrder__c;
            Decimal rightOrder = right.DisplayOrder__c == null ? 9999 : right.DisplayOrder__c;
            if (leftOrder == rightOrder) return left.MasterLabel.compareTo(right.MasterLabel);
            return leftOrder < rightOrder ? -1 : 1;
        }
    }
}