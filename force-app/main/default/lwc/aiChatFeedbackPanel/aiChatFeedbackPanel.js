import { LightningElement, api } from 'lwc';
import { LABELS, FEEDBACK_REASONS } from 'c/aiChatUtils';

// "What went wrong?" after a thumbs down - a reason chip and an optional comment. The rating itself is already saved; this only adds the detail.
export default class AiChatFeedbackPanel extends LightningElement {
    @api isSubmitting = false;

    labels = LABELS;
    selectedReason = FEEDBACK_REASONS[0];
    comment = '';

    get reasonViews() {
        return FEEDBACK_REASONS.map((value) => ({ value, pressed: value === this.selectedReason ? 'true' : 'false' }));
    }

    handleReason(event) {
        this.selectedReason = event.currentTarget.dataset.value;
    }

    handleComment(event) {
        this.comment = event.target.value;
    }

    handleSkip() {
        this.dispatchEvent(new CustomEvent('skip'));
    }

    handleSubmit() {
        this.dispatchEvent(new CustomEvent('submit', { detail: { reason: this.selectedReason, comment: this.comment } }));
    }
}