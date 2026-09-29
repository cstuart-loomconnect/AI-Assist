import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import getTabConfig from '@salesforce/apex/AIConsoleController.getTabConfig';
import { TABS, reduceError, toast } from 'c/aiConsoleUtils';

const SUB_NAVIGATION = 'Sub Navigation';
const WIDTH_CLASS = { Full: 'cell_full', 'Two Thirds': 'cell_two', 'One Third': 'cell_one' };

/*
One AI Assist console tab. Each console tab is a Lightning Component tab showing this component, so
Salesforce draws no page title bar above it; the tab's API name (AI_Home, AI_Agents...) is the
AINavTab__mdt Developer Name it reads. On an App Page the tabName property names the record instead.
It loads that record (through AIConsoleController.getTabConfig) and lays the page out from its
AINavTabSection__mdt rows:

- Sub Navigation rows become the left rail (aiSubNav). The picked one's ComponentAPIName__c is loaded
  with a dynamic import and fills the page.
- Component and Related List rows stack in the page, three columns wide, sized by SectionWidth__c.

Where the user is lives in the URL (c__section, c__view, c__recordId, c__step), so every screen can
be linked to and Back works. Sections never navigate themselves - they fire consolenavigate (see
aiConsoleUtils.navigate) and this component turns it into a navItemPage / recordPage navigation.
*/
export default class AiTabPage extends NavigationMixin(LightningElement) {
    @api tabName; // Only on an App Page - a component tab uses its own API name.

    config;
    error;
    isLoading = true;

    pageRef;
    urlState = {};
    extraState = {}; // Shared page state that isn't in the URL, e.g. Home's date range.
    pageState = {}; // Handed to every section - rebuilt only when the URL or shared state changes.
    fullWidth = false;

    activeCtor;
    activeLoadError;
    loadedActiveName;
    stacked = [];
    expandedKeys = new Set();

    componentCache = new Map();

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        this.pageRef = pageRef;
        this.urlState = pageRef && pageRef.state ? { ...pageRef.state } : {};
        this.refreshPageState();
        if (!this.config && !this.isConfigRequested) this.loadConfig();
        this.loadActiveComponent();
    }

    isConfigRequested = false;

    // The tab's API name, without the package namespace - e.g. ns__AI_Agents -> AI_Agents.
    get resolvedTabName() {
        if (this.tabName) return this.tabName;
        const apiName = this.pageRef?.attributes?.apiName || '';
        return apiName.includes('__') ? apiName.substring(apiName.indexOf('__') + 2) : apiName;
    }

    async loadConfig() {
        this.isConfigRequested = true;
        try {
            this.config = await getTabConfig({ tabName: this.resolvedTabName });
            this.error = undefined;
            this.refreshPageState();
            this.buildStacked();
            this.loadActiveComponent();
        } catch (error) {
            this.error = reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // =============================================================
    // Sections
    // =============================================================

    get railSections() {
        return (this.config?.sections || []).filter((section) => section.sectionType === SUB_NAVIGATION);
    }

    get activeSectionName() {
        const requested = this.urlState.c__section;
        const rail = this.railSections;
        if (requested && rail.some((section) => section.developerName === requested)) return requested;
        return rail.length ? rail[0].developerName : null;
    }

    get activeSection() {
        return this.railSections.find((section) => section.developerName === this.activeSectionName);
    }

    refreshPageState() {
        this.pageState = {
            section: this.activeSectionName,
            view: this.urlState.c__view || null,
            recordId: this.urlState.c__recordId || null,
            step: this.urlState.c__step ? Number(this.urlState.c__step) : null,
            ...this.extraState
        };
    }

    get railItems() {
        return this.railSections.map((section) => ({
            name: section.developerName,
            label: section.label,
            count: section.hasBadge ? section.badgeCount : null,
            isLocked: section.isLocked,
            externalUrl: section.externalUrl,
            openInNewTab: section.openInNewTab
        }));
    }

    get railHeading() {
        const label = this.config?.label || '';
        return label.replace(/^AI\s+/i, '');
    }

    get showRail() {
        return this.railSections.length > 0 && !this.fullWidth;
    }

    get hasStacked() {
        return this.stacked.length > 0;
    }

    get isInactive() {
        return this.config && !this.config.isActive;
    }

    get isEmpty() {
        return !this.activeSection && !this.hasStacked;
    }

    get mainClass() {
        return this.fullWidth ? 'main main_flush' : 'main';
    }

    get externalTarget() {
        return this.config?.openInNewTab ? '_blank' : '_self';
    }

    async loadActiveComponent() {
        const section = this.activeSection;
        if (!section || this.loadedActiveName === section.developerName) return;

        this.loadedActiveName = section.developerName;
        this.fullWidth = false; // A new section starts with the rail; it can ask for full width itself.
        this.activeCtor = undefined;
        this.activeLoadError = undefined;

        try {
            this.activeCtor = await this.loadComponent(section.componentName);
        } catch (error) {
            this.activeLoadError = `The component "${section.componentName}" for ${section.label} couldn't be loaded.`;
        }
    }

    buildStacked() {
        const sections = (this.config?.sections || []).filter((section) => section.sectionType !== SUB_NAVIGATION);

        this.stacked = sections.map((section) => ({
            key: section.developerName,
            section,
            ctor: undefined,
            loadError: undefined,
            isCollapsed: section.collapsedByDefault && !this.expandedKeys.has(section.developerName),
            cellClass: WIDTH_CLASS[section.width] || 'cell_full'
        }));

        this.stacked.forEach((item) => this.loadStackedComponent(item.key));
    }

    async loadStackedComponent(key) {
        const item = this.stacked.find((entry) => entry.key === key);
        if (!item || item.isCollapsed || item.ctor) return;

        let ctor;
        let loadError;
        try {
            ctor = await this.loadComponent(item.section.componentName);
        } catch (error) {
            loadError = `The component "${item.section.componentName}" for ${item.section.label} couldn't be loaded.`;
        }

        this.stacked = this.stacked.map((entry) => (entry.key === key ? { ...entry, ctor, loadError } : entry));
    }

    // ComponentAPIName__c comes from protected, developer-controlled metadata - only this package's own components.
    async loadComponent(componentName) {
        if (!componentName) throw new Error('No component set');
        if (this.componentCache.has(componentName)) return this.componentCache.get(componentName);

        const module = await import(`c/${componentName}`);
        this.componentCache.set(componentName, module.default);
        return module.default;
    }

    // =============================================================
    // Events from sections
    // =============================================================

    handleRailSelect(event) {
        const item = this.railItems.find((entry) => entry.name === event.detail.name);
        if (item && item.externalUrl) {
            this.openUrl(item.externalUrl, item.openInNewTab);
            return;
        }
        this.goTo({ section: event.detail.name });
    }

    handleNavigate(event) {
        event.stopPropagation();
        this.goTo(event.detail || {});
    }

    handlePageState(event) {
        event.stopPropagation();
        this.extraState = { ...this.extraState, ...event.detail };
        this.refreshPageState();
    }

    handleLayout(event) {
        event.stopPropagation();
        this.fullWidth = event.detail && event.detail.fullWidth === true;
    }

    handleRefresh(event) {
        event.stopPropagation();
        this.refreshBadges();
    }

    handleExpand(event) {
        const key = event.currentTarget.dataset.key;
        this.expandedKeys.add(key);
        this.stacked = this.stacked.map((entry) => (entry.key === key ? { ...entry, isCollapsed: false } : entry));
        this.loadStackedComponent(key);
    }

    // Reloads the tab's config so rail counts are current, without reloading any section.
    async refreshBadges() {
        try {
            const fresh = await getTabConfig({ tabName: this.resolvedTabName });
            this.config = { ...this.config, sections: fresh.sections };
        } catch (error) {
            // Counts are a nicety - a failed refresh leaves the old ones.
        }
    }

    // { tab, section, view, recordId, step, replace }
    goTo(target) {
        if (target.tab === TABS.RECORD) {
            this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: target.recordId, actionName: 'view' } });
            return;
        }

        const tabName = target.tab || this.resolvedTabName;
        const isThisTab = tabName === this.resolvedTabName;
        const link = (this.config?.tabs || []).find((tab) => tab.tabName === tabName);

        if (!link && !isThisTab) {
            toast(this, 'Not available', 'That part of AI Assist isn’t turned on for you.', 'warning');
            return;
        }
        if (link && link.externalUrl) {
            this.openUrl(link.externalUrl, link.openInNewTab);
            return;
        }

        const state = {};
        const section = target.section || (isThisTab && (target.view || target.recordId) ? this.activeSectionName : null);
        if (section) state.c__section = section;
        if (target.view) state.c__view = target.view;
        if (target.recordId) state.c__recordId = target.recordId;
        if (target.step) state.c__step = String(target.step);

        const apiName = link ? link.navItemApiName : this.pageRef?.attributes?.apiName;
        this[NavigationMixin.Navigate]({ type: 'standard__navItemPage', attributes: { apiName }, state }, target.replace === true);
    }

    openUrl(url, newTab) {
        if (newTab) {
            window.open(url, '_blank', 'noopener');
            return;
        }
        this[NavigationMixin.Navigate]({ type: 'standard__webPage', attributes: { url } });
    }
}
