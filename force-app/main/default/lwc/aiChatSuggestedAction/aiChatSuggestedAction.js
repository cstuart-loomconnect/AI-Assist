import { LightningElement, api } from 'lwc';
import { LABELS, ACTIONS_DISPLAY_INLINE_BUTTONS } from 'c/aiChatUtils';

// A Workflow Action the AI suggested on its reply. The AI can only suggest - the user runs it here (optionally editing its inputs first, and confirming when the action requires it). Running is done by aiAssistChat via AIChatController.runSuggestedAction; this component only collects the inputs and shows the outcome it's handed in state.
export default class AiChatSuggestedAction extends LightningElement {
    @api action;
    @api display = 'Cards';
    @api state = { status: 'idle' }; // status: 'idle' | 'running' | 'done' | 'failed' | 'dismissed'

    labels = LABELS;
    mode = 'buttons'; // 'buttons' | 'editing' | 'confirming'
    values = {};
    pendingInputs = null;

    get status() {
        if (this.action && this.action.hasRun && (!this.state || this.state.status === 'idle')) return 'done';
        return (this.state && this.state.status) || 'idle';
    }

    get isVisible() {
        return this.action && this.status !== 'dismissed';
    }

    get isCard() {
        return this.display !== ACTIONS_DISPLAY_INLINE_BUTTONS;
    }

    get isInline() {
        return !this.isCard;
    }

    get containerClass() {
        return this.isCard ? 'card' : 'inline';
    }

    get isRunning() {
        return this.status === 'running';
    }

    get isDone() {
        return this.status === 'done';
    }

    get isFailed() {
        return this.status === 'failed';
    }

    get isEditing() {
        return this.mode === 'editing';
    }

    get isConfirming() {
        return this.mode === 'confirming';
    }

    get hasInputs() {
        return this.action && this.action.inputFields && this.action.inputFields.length > 0;
    }

    get resultMessage() {
        return (this.state && this.state.message) || LABELS.actionDone;
    }

    get confirmationText() {
        return this.action.confirmationMessage || `${this.action.name}?`;
    }

    get fieldViews() {
        return (this.action.inputFields || []).map((field) => ({
            ...field,
            value: this.values[field.name],
            isTextarea: field.inputType === 'textarea',
            isCheckbox: field.inputType === 'checkbox'
        }));
    }

    handleRun() {
        this.startRun({});
    }

    handleEdit() {
        this.mode = 'editing';
    }

    handleFieldChange(event) {
        const name = event.target.dataset.field;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.detail.value;
        this.values = { ...this.values, [name]: value };
    }

    handleRunEdited() {
        const inputs = [...this.template.querySelectorAll('lightning-input, lightning-textarea')];
        const isValid = inputs.reduce((valid, input) => input.reportValidity() && valid, true);
        if (isValid) this.startRun({ ...this.values });
    }

    handleConfirm() {
        this.dispatchRun(this.pendingInputs || {});
    }

    handleCancel() {
        this.mode = 'buttons';
        this.pendingInputs = null;
    }

    handleDismiss() {
        this.dispatchEvent(new CustomEvent('dismiss'));
    }

    // Actions flagged RequiresConfirmation__c stop at a confirmation step first.
    startRun(inputs) {
        if (this.action.requiresConfirmation && this.mode !== 'confirming') {
            this.pendingInputs = inputs;
            this.mode = 'confirming';
            return;
        }
        this.dispatchRun(inputs);
    }

    dispatchRun(inputs) {
        this.mode = 'buttons';
        this.pendingInputs = null;
        this.dispatchEvent(new CustomEvent('run', { detail: { inputs } }));
    }
}