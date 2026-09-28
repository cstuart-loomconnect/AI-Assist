import { LightningElement, api } from 'lwc';
import { LABELS, formatDuration } from 'c/aiChatUtils';

// The usage-limit banner above the composer - one per AIUserSettings__c.UsageLimitReachedBehavior__c: block (messages paused), notify (dismissible warning) or conversations (finish this one only).
export default class AiChatUsageBanner extends LightningElement {
    @api variant; // 'block' | 'notify' | 'conversations'
    @api resetsInMinutes;

    labels = LABELS;

    get isBlock() {
        return this.variant === 'block';
    }

    get isNotify() {
        return this.variant === 'notify';
    }

    get bannerClass() {
        return `banner banner_${this.variant}`;
    }

    get heading() {
        if (this.isBlock) return LABELS.usageBlockHeading;
        if (this.isNotify) return LABELS.usageNotifyHeading;
        return LABELS.usageConversationsHeading;
    }

    get body() {
        if (this.isBlock) return this.resetsInMinutes ? `You can send messages again in ${formatDuration(this.resetsInMinutes)}.` : 'You can send messages again once your limit resets.';
        if (this.isNotify) return LABELS.usageNotifyBody;
        return LABELS.usageConversationsBody;
    }

    handleDismiss() {
        this.dispatchEvent(new CustomEvent('dismiss'));
    }
}