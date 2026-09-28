import { LightningElement, api } from 'lwc';
import { LABELS } from 'c/aiChatUtils';

// First-run terms. The checkbox must be ticked before "Agree and continue" - the parent records the acknowledgment.
export default class AiChatTerms extends LightningElement {
    @api policyUrl;
    @api isSaving = false;
    @api errorMessage;

    labels = LABELS;
    isAgreed = false;

    get isAgreeDisabled() {
        return !this.isAgreed || this.isSaving;
    }

    handleAgreeChange(event) {
        this.isAgreed = event.target.checked;
    }

    handleAgree() {
        if (this.isAgreed) this.dispatchEvent(new CustomEvent('agree'));
    }
}