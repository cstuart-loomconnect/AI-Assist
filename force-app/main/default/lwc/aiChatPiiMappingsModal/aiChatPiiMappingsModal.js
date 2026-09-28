import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import { LABELS, copyToClipboard } from 'c/aiChatUtils';

// Debug mode's PII masking pairs for one conversation (real value -> masked value), opened from aiChatDebugTrace's "pii mappings" button by aiAssistChat.
export default class AiChatPiiMappingsModal extends LightningModal {
    @api mappingJson;
    @api conversationName;

    labels = LABELS;
    copyLabel = LABELS.copyJson;

    get hasMappings() {
        return Object.keys(JSON.parse(this.mappingJson || '{}')).length > 0;
    }

    async handleCopy() {
        const copied = await copyToClipboard(this.mappingJson);
        this.copyLabel = copied ? LABELS.copied : LABELS.copyJson;
    }

    handleClose() {
        this.close();
    }
}