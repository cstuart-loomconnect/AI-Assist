import { LightningElement, api } from 'lwc';
import getPlatformLogDetail from '@salesforce/apex/AIConsoleController.getPlatformLogDetail';
import { TABS, SECTIONS, VIEWS, navigate, reduceError } from 'c/aiConsoleUtils';

/*
The panel beside Activity › Error Log - one AIPlatformLog__c entry with its stack trace, and a hint
when it matches a known setting (e.g. the callout timeout).
*/
export default class AiPlatformLogDetail extends LightningElement {
    log;
    error;

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
        this.log = undefined;
        try {
            this.log = await getPlatformLogDetail({ logId: this._recordId });
            this.error = undefined;
        } catch (error) {
            this.error = reduceError(error);
        }
    }

    get subtitle() {
        return `${this.log.name} · ${this.log.occurredLabel}`;
    }

    get message() {
        return this.log.message || '—';
    }

    get className() {
        return this.log.className || '—';
    }

    get methodName() {
        return this.log.methodName || '—';
    }

    get userName() {
        return this.log.userName || '—';
    }

    handleOpenRelated(event) {
        event.preventDefault();
        if (this.log.relatedIsConversation) {
            navigate(this, { tab: TABS.ACTIVITY, section: SECTIONS.ACTIVITY_CONVERSATIONS, view: VIEWS.RECORD, recordId: this.log.relatedRecordId });
            return;
        }
        navigate(this, { tab: TABS.RECORD, recordId: this.log.relatedRecordId });
    }
}
