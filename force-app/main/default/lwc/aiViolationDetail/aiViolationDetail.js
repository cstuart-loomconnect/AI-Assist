import { LightningElement, api } from 'lwc';
import getViolationDetail from '@salesforce/apex/AIConsoleController.getViolationDetail';
import markViolationReviewed from '@salesforce/apex/AIConsoleController.markViolationReviewed';
import { TABS, SECTIONS, VIEWS, navigate, openWizard, reduceError, toast, badgeClass } from 'c/aiConsoleUtils';

const SEVERITY_VARIANT = { High: 'err', Medium: 'warn' };

/*
The panel beside Activity › Violations. "Mark as reviewed" sets AIViolation__c.ReviewStatus__c, which
also drops the violation out of Home's Needs attention and the rail's count.
*/
export default class AiViolationDetail extends LightningElement {
    violation;
    error;
    isSaving = false;

    _recordId;
    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        if (value === this._recordId) return;
        this._recordId = value;
        this.load();
    }

    async load() {
        if (!this._recordId) return;
        this.violation = undefined;
        try {
            this.violation = await getViolationDetail({ violationId: this._recordId });
            this.error = undefined;
        } catch (error) {
            this.error = reduceError(error);
        }
    }

    get severityClass() {
        return badgeClass(SEVERITY_VARIANT[this.violation.severity]);
    }

    get requestLabel() {
        return this.violation.requestBlocked ? 'Request blocked' : 'Logged';
    }

    get subtitle() {
        return `${this.violation.name} · ${this.violation.createdLabel}`;
    }

    get agentName() {
        return this.violation.agentName || '—';
    }

    get ruleFired() {
        return this.violation.ruleFiredLabel || '—';
    }

    get isReviewed() {
        return this.violation.reviewStatus === 'Reviewed';
    }

    handleOpenRule(event) {
        event.preventDefault();
        openWizard(this, this.violation.agentId, 5);
    }

    handleOpenUser(event) {
        event.preventDefault();
        navigate(this, { tab: TABS.SETTINGS, section: SECTIONS.SETTINGS_USERS });
    }

    handleOpenConversation(event) {
        if (event && event.preventDefault) event.preventDefault();
        navigate(this, { tab: TABS.ACTIVITY, section: SECTIONS.ACTIVITY_CONVERSATIONS, view: VIEWS.RECORD, recordId: this.violation.conversationId });
    }

    async handleReviewed() {
        this.isSaving = true;
        try {
            this.violation = await markViolationReviewed({ violationId: this._recordId });
            toast(this, 'Marked as reviewed', this.violation.title);
            this.dispatchEvent(new CustomEvent('changed'));
        } catch (error) {
            toast(this, 'Couldn’t save', reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }
}