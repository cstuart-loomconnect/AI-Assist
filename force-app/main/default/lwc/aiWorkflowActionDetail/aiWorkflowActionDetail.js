import { LightningElement, api } from 'lwc';
import getWorkflowAction from '@salesforce/apex/AIConsoleController.getWorkflowAction';
import AiWorkflowActionModal from 'c/aiWorkflowActionModal';
import { TABS, SECTIONS, VIEWS, navigate, reduceError, badgeClass } from 'c/aiConsoleUtils';

/*
The panel beside Library › Workflow Actions, including a preview of the confirmation card users get
in the chat window before a write action runs.
*/
export default class AiWorkflowActionDetail extends LightningElement {
    action;
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
        this.action = undefined;
        try {
            this.action = await getWorkflowAction({ actionId: this._recordId });
            this.error = undefined;
        } catch (error) {
            this.error = reduceError(error);
        }
    }

    get executionClass() {
        return badgeClass(this.action.executionType === 'Write' ? 'write' : 'ro');
    }

    get statusLabel() {
        return this.action.isActive ? 'Active' : 'Inactive';
    }

    get statusClass() {
        return badgeClass(this.action.isActive ? 'ok' : '');
    }

    get implementationLabel() {
        return this.action.actionType === 'Flow' ? 'Flow API Name' : 'Apex Class Name';
    }

    get implementationName() {
        return (this.action.actionType === 'Flow' ? this.action.flowApiName : this.action.apexClassName) || '—';
    }

    get targetObject() {
        return this.action.targetObject || '—';
    }

    get hasInputs() {
        return this.action.previewInputs && this.action.previewInputs.length > 0;
    }

    get noConfirmationText() {
        return this.action.executionType === 'Write'
            ? 'No confirmation - it runs as soon as the user clicks it. Write actions should ask first.'
            : 'Read-only - it runs as soon as the user clicks it.';
    }

    get hasUsedBy() {
        return this.action.usedBy && this.action.usedBy.length > 0;
    }

    handleOpenAgent(event) {
        event.preventDefault();
        navigate(this, { tab: TABS.AGENTS, section: SECTIONS.AGENTS_ALL, view: VIEWS.RECORD, recordId: event.currentTarget.dataset.id });
    }

    async handleEdit() {
        const saved = await AiWorkflowActionModal.open({ size: 'medium', label: 'Edit Workflow Action', recordId: this._recordId });
        if (saved && saved.id) {
            await this.load();
            this.dispatchEvent(new CustomEvent('changed'));
        }
    }
}