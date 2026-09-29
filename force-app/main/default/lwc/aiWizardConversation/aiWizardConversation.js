import { LightningElement, api } from 'lwc';
import saveConversationRules from '@salesforce/apex/AIConsoleController.saveConversationRules';
import { TABS, SECTIONS, navigate, parseNumber, formatNumber } from 'c/aiConsoleUtils';

const LOAD_OPTIONS = [
    { value: 'On Page Load', label: 'On Page Load', description: 'The open conversation loads with the record page.' },
    { value: 'On Chat Window Open', label: 'On Chat Window Open', description: 'Loads when the user opens the chat. Lighter on busy pages.' },
    { value: 'Manual Only', label: 'Manual Only', description: 'Always starts fresh. Past conversations stay in history.' }
];
const VISIBILITY_OPTIONS = [
    { value: 'Private', label: 'Private', description: 'Only the person who started it, plus admins.' },
    { value: 'Global', label: 'Global', description: 'Anyone who can see the record can read it.' }
];
const TRACKING_OPTIONS = [
    { value: 'Estimate Token Usage', label: 'Estimate Token Usage', description: 'Counts characters. Fast, roughly right.' },
    { value: 'Track Token Usage', label: 'Track Token Usage', description: 'Uses the real count the provider returns after each turn.' },
    { value: 'Pre-Request Usage Check', label: 'Pre-Request Usage Check', description: 'Checks before sending, so a turn never goes over.' }
];
const TRIGGERS = ['Conversation Closed Date', 'Conversation Created Date', 'Last Message Date'];
const TRIGGER_VERBS = { 'Conversation Closed Date': 'closed', 'Conversation Created Date': 'started', 'Last Message Date': 'last used' };

/*
Wizard step 6 - Conversation Rules: how conversations load, who sees them, when they end and how long
they're kept. Saved when the wizard moves on (save). New agents start with the design's defaults.
*/
export default class AiWizardConversation extends LightningElement {
    rules = {};

    _state;
    @api
    get state() {
        return this._state;
    }
    set state(value) {
        this._state = value;
        const saved = (value && value.conversationRules) || {};
        this.rules = {
            ...saved,
            loadTrigger: saved.loadTrigger || 'On Chat Window Open',
            visibility: saved.visibility || 'Private',
            tokenTracking: saved.tokenTracking || 'Track Token Usage',
            retentionTrigger: saved.retentionTrigger || 'Conversation Closed Date'
        };
    }

    @api
    async save(nextStep) {
        return saveConversationRules({ agentId: this._state.agentId, rulesJson: JSON.stringify(this.rules), nextStep });
    }

    toOptions(options, current) {
        return options.map((option) => ({ ...option, checked: option.value === current }));
    }

    get loadOptions() {
        return this.toOptions(LOAD_OPTIONS, this.rules.loadTrigger);
    }

    get visibilityOptions() {
        return this.toOptions(VISIBILITY_OPTIONS, this.rules.visibility);
    }

    get trackingOptions() {
        return this.toOptions(TRACKING_OPTIONS, this.rules.tokenTracking);
    }

    get triggerOptions() {
        return TRIGGERS.map((value) => ({ value, selected: value === this.rules.retentionTrigger }));
    }

    get singleChecked() {
        return String(!!this.rules.singleActive);
    }

    get resumeChecked() {
        return String(!!this.rules.allowResume);
    }

    get maxTokensLabel() {
        return this.rules.maxTokens === null || this.rules.maxTokens === undefined ? '' : formatNumber(this.rules.maxTokens);
    }

    get budgetLabel() {
        return this.rules.globalBudget ? `${formatNumber(this.rules.globalBudget)} tokens a day` : 'none set';
    }

    get hasRetention() {
        return !!this.rules.retentionDays;
    }

    get retentionVerb() {
        return TRIGGER_VERBS[this.rules.retentionTrigger] || 'closed';
    }

    get exampleStart() {
        return this.formatDate(new Date());
    }

    get exampleEnd() {
        return this.formatDate(new Date(Date.now() + this.rules.retentionDays * 86400000));
    }

    formatDate(date) {
        return date.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
    }

    handleInput(event) {
        this.rules = { ...this.rules, [event.target.dataset.field]: event.target.value };
    }

    // Whole numbers only - these are counts of messages, minutes and days.
    handleNumber(event) {
        const value = parseNumber(event.target.value);
        this.rules = { ...this.rules, [event.target.dataset.field]: value === null ? null : Math.round(value) };
    }

    handleTokens(event) {
        const value = parseNumber(event.target.value);
        this.rules = { ...this.rules, maxTokens: value === null ? null : Math.round(value) };
    }

    handleToggle(event) {
        const field = event.currentTarget.dataset.field;
        this.rules = { ...this.rules, [field]: !this.rules[field] };
    }

    handleOpenApp(event) {
        event.preventDefault();
        navigate(this, { tab: TABS.SETTINGS, section: SECTIONS.SETTINGS_APP });
    }

    handleOpenUsers(event) {
        event.preventDefault();
        navigate(this, { tab: TABS.SETTINGS, section: SECTIONS.SETTINGS_USERS });
    }
}