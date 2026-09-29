import { LightningElement, api } from 'lwc';
import LightningConfirm from 'lightning/confirm';
import getTerms from '@salesforce/apex/AIConsoleController.getTerms';
import savePolicyUrl from '@salesforce/apex/AIConsoleController.savePolicyUrl';
import publishTermsVersion from '@salesforce/apex/AIConsoleController.publishTermsVersion';
import { TABS, SECTIONS, navigate, refreshNav, reduceError, toast, downloadCsv } from 'c/aiConsoleUtils';

/*
Settings › Usage Terms. Publishing a new version bumps AIAssistSettings__c.CurrentTermsVersion__c; the
chat window then asks everyone to sign again. Signed AITermsAcknowledgment__c records are read-only.
*/
export default class AiUsageTerms extends LightningElement {
    @api section;
    @api pageState;

    terms;
    policyUrl = '';
    isLoading = true;
    isBusy = false;
    error;

    connectedCallback() {
        this.load();
    }

    async load() {
        try {
            this.apply(await getTerms());
            this.error = undefined;
        } catch (error) {
            this.error = reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    apply(terms) {
        this.terms = terms;
        this.policyUrl = terms.policyUrl || '';
    }

    get title() {
        return this.section?.label || 'Usage Terms';
    }

    get urlChanged() {
        return (this.policyUrl || '') !== (this.terms.policyUrl || '');
    }

    get meterStyle() {
        return `width: ${this.terms.percent || 0}%`;
    }

    get hasOlder() {
        return this.terms.olderCount > 0;
    }

    get olderText() {
        return `${this.terms.olderCount} still on an older version: ${this.terms.olderUsersLabel}.`;
    }

    get noAcknowledgments() {
        return this.terms.acknowledgments.length === 0;
    }

    handleUrl(event) {
        this.policyUrl = event.target.value;
    }

    async handleSaveUrl() {
        await this.run(() => savePolicyUrl({ policyUrl: this.policyUrl }), 'Policy URL saved');
    }

    async handlePublish() {
        const confirmed = await LightningConfirm.open({
            message: `Everyone with AI Assist signs version ${this.terms.nextVersion} before their next message.`,
            label: `Publish version ${this.terms.nextVersion}?`,
            theme: 'warning'
        });
        if (!confirmed) return;
        await this.run(() => publishTermsVersion(), `Version ${this.terms.nextVersion} published`);
        refreshNav(this);
    }

    async run(call, successTitle) {
        this.isBusy = true;
        this.error = undefined;
        try {
            this.apply(await call());
            toast(this, successTitle, '');
        } catch (error) {
            this.error = reduceError(error);
        } finally {
            this.isBusy = false;
        }
    }

    handleSeeUsers(event) {
        event.preventDefault();
        navigate(this, { tab: TABS.SETTINGS, section: SECTIONS.SETTINGS_USERS });
    }

    handleOpenRecord(event) {
        event.preventDefault();
        navigate(this, { tab: TABS.RECORD, recordId: event.currentTarget.dataset.id });
    }

    handleExport() {
        const rows = this.terms.acknowledgments.map((row) => [row.userName, row.version, row.signature, row.acknowledgedLabel, row.loginHistoryId]);
        downloadCsv(`Terms_Acknowledgments_${new Date().toISOString().slice(0, 10)}.csv`, ['User', 'Terms Version', 'Signature', 'Acknowledged', 'Login session'], rows);
    }
}