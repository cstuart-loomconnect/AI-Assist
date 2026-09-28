import { LightningElement, api } from 'lwc';

const ICONS = {
    channel: 'utility:ban',
    noagent: 'utility:info',
    space: 'utility:expand_alt',
    error: 'utility:error'
};

// A centred full-window message for every state where the chat itself can't be used - app off, maintenance, channel not allowed, no Agent, not enough room, failed to load.
export default class AiChatStatePanel extends LightningElement {
    @api variant; // 'inactive' | 'maintenance' | 'channel' | 'noagent' | 'space' | 'error'
    @api heading;
    @api body;
    @api actionLabel;
    @api footer;

    get isInactive() {
        return this.variant === 'inactive';
    }

    get isMaintenance() {
        return this.variant === 'maintenance';
    }

    get iconName() {
        return ICONS[this.variant] || 'utility:info';
    }

    handleAction() {
        this.dispatchEvent(new CustomEvent('action'));
    }
}