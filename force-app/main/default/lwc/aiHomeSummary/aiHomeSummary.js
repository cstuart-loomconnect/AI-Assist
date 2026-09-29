import { LightningElement, api } from 'lwc';
import getHomeSummary from '@salesforce/apex/AIConsoleController.getHomeSummary';
import { TABS, SECTIONS, VIEWS, navigate, setPageState, reduceError, formatNumber } from 'c/aiConsoleUtils';

const DEFAULT_DAYS = 14;

/*
Home › Summary tiles. Owns the page's date range: picking one reloads the tiles and shares it through
aiTabPage (setPageState) so the trend chart follows.
*/
export default class AiHomeSummary extends LightningElement {
    @api section;

    summary = {};
    error;
    days = DEFAULT_DAYS;

    rangeOptions = [
        { label: 'Last 7 days', value: '7' },
        { label: 'Last 14 days', value: '14' },
        { label: 'Last 30 days', value: '30' }
    ];

    _pageState;
    @api
    get pageState() {
        return this._pageState;
    }
    set pageState(value) {
        this._pageState = value;
        if (value && value.dateRange && value.dateRange !== this.days) {
            this.days = value.dateRange;
            this.load();
        }
    }

    connectedCallback() {
        this.load();
    }

    async load() {
        try {
            this.summary = await getHomeSummary({ days: this.days });
            this.error = undefined;
        } catch (error) {
            this.error = reduceError(error);
        }
    }

    get daysValue() {
        return String(this.days);
    }

    get greeting() {
        return this.summary.greeting || '';
    }

    get dateLabel() {
        return this.summary.dateLabel || '';
    }

    get agentsSub() {
        return `${this.summary.testModeAgents || 0} in test mode · ${this.summary.draftAgents || 0} ${this.summary.draftAgents === 1 ? 'draft' : 'drafts'}`;
    }

    get conversationsToday() {
        return formatNumber(this.summary.conversationsToday || 0);
    }

    get conversationsSub() {
        const users = this.summary.usersToday || 0;
        const records = this.summary.recordsToday || 0;
        return `${users} ${users === 1 ? 'user' : 'users'} on ${records} ${records === 1 ? 'record' : 'records'}`;
    }

    get helpfulLabel() {
        return this.summary.helpfulPercent === null || this.summary.helpfulPercent === undefined ? '—' : `${this.summary.helpfulPercent}%`;
    }

    get helpfulSub() {
        if (!this.summary.ratingCount) return `No ratings in the last ${this.days} days`;
        return `of ${formatNumber(this.summary.ratingCount)} ratings, last ${this.days} days`;
    }

    get hasHigh() {
        return this.summary.highViolations > 0;
    }

    get tokensToday() {
        return formatNumber(this.summary.tokensToday || 0);
    }

    get hasBudget() {
        return !!this.summary.tokenBudget;
    }

    get meterStyle() {
        return `width: ${Math.min(100, this.summary.tokenPercent || 0)}%`;
    }

    get budgetSub() {
        if (!this.hasBudget) return 'No daily budget set';
        return `${this.summary.tokenPercent || 0}% of the ${formatNumber(this.summary.tokenBudget)} daily budget`;
    }

    handleRangeChange(event) {
        this.days = Number(event.detail.value);
        setPageState(this, { dateRange: this.days });
        this.load();
    }

    handleNewAgent() {
        navigate(this, { tab: TABS.AGENTS, section: SECTIONS.AGENTS_ALL, view: VIEWS.NEW });
    }

    handleTile(event) {
        event.preventDefault();
        const targets = {
            agents: { tab: TABS.AGENTS, section: SECTIONS.AGENTS_ALL },
            conversations: { tab: TABS.ACTIVITY, section: SECTIONS.ACTIVITY_CONVERSATIONS },
            feedback: { tab: TABS.ACTIVITY, section: SECTIONS.ACTIVITY_FEEDBACK },
            violations: { tab: TABS.ACTIVITY, section: SECTIONS.ACTIVITY_VIOLATIONS }
        };
        navigate(this, targets[event.currentTarget.dataset.target]);
    }
}