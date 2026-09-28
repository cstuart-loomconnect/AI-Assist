import { LightningElement, api } from 'lwc';
import { LABELS, formatTime } from 'c/aiChatUtils';

// Shown instead of a new conversation while AIAssistUISettings__c.DisableUserInitiatedChat__c is on - offers the Active conversation on this record, if there is one.
export default class AiChatNewChatsPaused extends LightningElement {
    @api openConversation;

    labels = LABELS;

    get metaLabel() {
        const conversation = this.openConversation;
        if (!conversation) return '';
        return `${LABELS.lastMessage} ${formatTime(conversation.lastActivity)} · ${conversation.messageCount} messages`;
    }

    handleContinue() {
        this.dispatchEvent(new CustomEvent('continue', { detail: { conversationId: this.openConversation.id } }));
    }
}