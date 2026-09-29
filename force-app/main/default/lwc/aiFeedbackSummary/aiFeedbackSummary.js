import { LightningElement, api } from 'lwc';
import getFeedbackSummary from '@salesforce/apex/AIConsoleController.getFeedbackSummary';
import { TABS, SECTIONS, VIEWS, navigate, reduceError, formatNumber } from 'c/aiConsoleUtils';

const RANGES = [
    { value: '7', label: 'Last 7 days' },
    { value: '14', label: 'Last 14 days' },
    { value: '30', label: 'Last 30 days' },
    { value: '90', label: 'Last 90 days' }
];

/*
Activity › Feedback - thumbs up / down from the chat window (AIFeedback__c): the helpful rate, the rate
per agent (agents with 10+ ratings), and every not-helpful rating that came with a comment.
*/
export default class AiFeedbackSummary extends LightningElement {
    @api section;
    @api pageState;

    summary;
    error;
    agentId = 'All';
    days = '14';

    connectedCallback() {
        this.load();
    }

    async load() {
        try {
            this.summary = await getFeedbackSummary({ agentId: this.agentId, days: Number(this.days) });
            this.error = undefined;
        } catch (error) {
            this.error = reduceError(error);
        }
    }

    get title() {
        return this.section?.label || 'Feedback';
    }

    get agentChoices() {
        const options = this.summary ? this.summary.agentOptions : [{ label: 'All agents', value: 'All' }];
        return options.map((option) => ({ ...option, selected: option.value === this.agentId }));
    }

    get rangeChoices() {
        return RANGES.map((option) => ({ ...option, selected: option.value === this.days }));
    }

    get percentLabel() {
        return this.summary.helpfulPercent === null || this.summary.helpfulPercent === undefined ? '—' : `${this.summary.helpfulPercent}%`;
    }

    get overallNote() {
        const s = this.summary;
        if (!s.ratings) return `No ratings on ${formatNumber(s.replies)} replies yet`;
        return `${formatNumber(s.helpful)} helpful and ${formatNumber(s.notHelpful)} not helpful, from ${formatNumber(s.ratings)} ratings on ${formatNumber(s.replies)} replies`;
    }

    get splitStyle() {
        return `width: ${this.summary.helpfulPercent || 0}%`;
    }

    get hasAgentRates() {
        return this.summary.byAgent.length > 0;
    }

    get agentRates() {
        return this.summary.byAgent.map((rate) => ({ ...rate, style: `width: ${rate.percent || 0}%`, ariaLabel: `${rate.name} helpful rate` }));
    }

    get commentNote() {
        return `${this.summary.commentCount} of ${this.summary.notHelpful} left a comment`;
    }

    get noComments() {
        return this.summary.comments.length === 0;
    }

    handleAgent(event) {
        this.agentId = event.target.value;
        this.load();
    }

    handleRange(event) {
        this.days = event.target.value;
        this.load();
    }

    handleOpenConversation(event) {
        event.preventDefault();
        navigate(this, { tab: TABS.ACTIVITY, section: SECTIONS.ACTIVITY_CONVERSATIONS, view: VIEWS.RECORD, recordId: event.currentTarget.dataset.id });
    }
}