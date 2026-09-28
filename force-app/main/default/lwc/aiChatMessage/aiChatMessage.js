import { LightningElement, api } from 'lwc';
import { LABELS, copyToClipboard } from 'c/aiChatUtils';

// One item in the conversation - a user bubble (sent, sending or blocked), an AI reply with its toolbar, feedback, suggested action and debug trace, or a centred notice. Everything it can't do alone is reported to aiAssistChat as one bubbling "messageaction" event.
export default class AiChatMessage extends LightningElement {
    @api message;

    labels = LABELS;
    isWhyOpen = false;
    isCopied = false;

    get userBubbleClass() {
        if (this.message.isBlocked) return 'user-bubble user-bubble_blocked';
        if (this.message.isSending) return 'user-bubble user-bubble_sending';
        return 'user-bubble';
    }

    get helpfulClass() {
        return this.message.isHelpful ? 'aia-icon-btn aia-icon-btn_small tool tool_helpful' : 'aia-icon-btn aia-icon-btn_small tool';
    }

    get notHelpfulClass() {
        return this.message.isNotHelpful ? 'aia-icon-btn aia-icon-btn_small tool tool_not-helpful' : 'aia-icon-btn aia-icon-btn_small tool';
    }

    get helpfulPressed() {
        return this.message.isHelpful ? 'true' : 'false';
    }

    get notHelpfulPressed() {
        return this.message.isNotHelpful ? 'true' : 'false';
    }

    get helpfulFill() {
        return this.message.isHelpful ? 'currentColor' : 'none';
    }

    get notHelpfulFill() {
        return this.message.isNotHelpful ? 'currentColor' : 'none';
    }

    get copyLabel() {
        return this.isCopied ? LABELS.copied : LABELS.copy;
    }

    get copyIcon() {
        return this.isCopied ? 'utility:check' : 'utility:copy';
    }

    get whyExpanded() {
        return this.isWhyOpen ? 'true' : 'false';
    }

    toggleWhy() {
        this.isWhyOpen = !this.isWhyOpen;
    }

    async handleCopy() {
        this.isCopied = await copyToClipboard(this.message.displayText);
    }

    handleHelpful() {
        this.notify('rate', { rating: 'Helpful' });
    }

    handleNotHelpful() {
        this.notify('rate', { rating: 'Not Helpful' });
    }

    handleFeedbackSubmit(event) {
        this.notify('submitfeedback', { reason: event.detail.reason, comment: event.detail.comment });
    }

    handleFeedbackSkip() {
        this.notify('closefeedback');
    }

    handleRegenerate() {
        this.notify('regenerate');
    }

    handleRunAction(event) {
        this.notify('runaction', { inputs: event.detail.inputs });
    }

    handleDismissAction() {
        this.notify('dismissaction');
    }

    handleEditBlocked() {
        this.notify('editblocked', { text: this.message.displayText });
    }

    handleLoadTrace() {
        this.notify('loadtrace');
    }

    handleViewPiiMappings() {
        this.notify('viewpiimappings');
    }

    handleCloseTrace() {
        this.notify('closetrace');
    }

    notify(action, extra = {}) {
        this.dispatchEvent(
            new CustomEvent('messageaction', {
                bubbles: true,
                composed: true,
                detail: { action, messageId: this.message.id, ...extra }
            })
        );
    }
}