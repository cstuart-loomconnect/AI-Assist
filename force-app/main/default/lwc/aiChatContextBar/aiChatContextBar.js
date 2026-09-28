import { LightningElement, api } from 'lwc';
import { LABELS } from 'c/aiChatUtils';

// The strip under the header naming the record the conversation is about, with the PII protected badge when a synced PII Registry covers its object.
export default class AiChatContextBar extends LightningElement {
    @api objectLabel;
    @api recordName;
    @api piiProtected = false;

    labels = LABELS;

    get recordLabel() {
        return [this.objectLabel, this.recordName].filter(Boolean).join(' · ');
    }
}