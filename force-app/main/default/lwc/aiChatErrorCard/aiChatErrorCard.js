import { LightningElement, api } from 'lwc';
import { LABELS } from 'c/aiChatUtils';

// A reply that failed (AIMessageReadyEvent__e with IsSuccess__c false) - Try again re-runs the newest message. The log reference lets the user quote the failure to an admin; debug users also see the detail.
export default class AiChatErrorCard extends LightningElement {
    @api reference;
    @api debugDetail;
    @api isRetrying = false;
    @api retryError;

    labels = LABELS;

    handleRetry() {
        this.dispatchEvent(new CustomEvent('retry'));
    }
}