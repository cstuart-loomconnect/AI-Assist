import { LightningElement, api } from 'lwc';
import { LABELS } from 'c/aiChatUtils';

// The scrolling conversation - "Show earlier messages", each message (with day separators), the working indicator and the failed-reply card. aiAssistChat drives its scroll position through the @api methods.
export default class AiChatMessageList extends LightningElement {
    @api items = [];
    @api hasMore = false;
    @api isLoadingEarlier = false;
    @api working;
    @api errorTurn;
    @api dimmed = false;

    labels = LABELS;
    savedDistanceFromBottom = null;
    isNearBottom = true;

    get scrollClass() {
        return this.dimmed ? 'scroll scroll_dimmed' : 'scroll';
    }

    get scroller() {
        return this.template.querySelector('.scroll');
    }

    // Jumps to the newest message. force = false only scrolls if the user was already near the bottom, so reading older messages isn't interrupted.
    @api
    scrollToBottom(force = true) {
        const scroller = this.scroller;
        if (scroller && (force || this.isNearBottom)) scroller.scrollTop = scroller.scrollHeight;
    }

    // Called before older messages are prepended, then restoreScrollPosition after they render - keeps the same message in view.
    @api
    captureScrollPosition() {
        const scroller = this.scroller;
        this.savedDistanceFromBottom = scroller ? scroller.scrollHeight - scroller.scrollTop : null;
    }

    @api
    restoreScrollPosition() {
        const scroller = this.scroller;
        if (scroller && this.savedDistanceFromBottom !== null) scroller.scrollTop = scroller.scrollHeight - this.savedDistanceFromBottom;
        this.savedDistanceFromBottom = null;
    }

    handleScroll() {
        const scroller = this.scroller;
        if (scroller) this.isNearBottom = scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight < 80;
    }

    handleLoadEarlier() {
        this.dispatchEvent(new CustomEvent('loadearlier'));
    }

    handleRetry() {
        this.dispatchEvent(new CustomEvent('retry'));
    }
}