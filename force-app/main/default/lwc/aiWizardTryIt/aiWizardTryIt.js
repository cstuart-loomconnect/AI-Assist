import { LightningElement, api } from 'lwc';
import sendTryIt from '@salesforce/apex/AIConsoleController.sendTryIt';
import getTryItUpdate from '@salesforce/apex/AIConsoleController.getTryItUpdate';
import setAgentStatus from '@salesforce/apex/AIConsoleController.setAgentStatus';
import getWizard from '@salesforce/apex/AIConsoleController.getWizard';
import { reduceError } from 'c/aiConsoleUtils';

const POLL_EVERY_MS = 2000;
const GIVE_UP_AFTER_MS = 120000;

/*
The wizard's "Try it" panel: a real test conversation with the agent on a record the admin picks.
Messages go through AIConversationMessageService exactly as the chat window's do (the console only
calls it), so the reply uses the agent's real templates, Data Sources and guardrails. Replies are
polled for; "How it answered" comes from the reply's execution steps.
*/
export default class AiWizardTryIt extends LightningElement {
    @api state;

    recordId;
    draft = '';
    conversationId;
    messages = [];
    howItAnswered = [];
    isSending = false;
    isWaiting = false;
    isEnabling = false;
    error;

    pollTimer;
    pollStartedAt;

    disconnectedCallback() {
        this.stopPolling();
    }

    get objectType() {
        return this.state && this.state.basics ? this.state.basics.objectType : null;
    }

    get pickerPlaceholder() {
        return this.objectType ? `Search ${this.objectType}…` : 'Search…';
    }

    get needsTestMode() {
        return this.state && !this.state.isActive;
    }

    get greeting() {
        return (this.state && this.state.basics && this.state.basics.greeting) || 'Hi, what do you need on this record?';
    }

    get hasHowItAnswered() {
        return this.howItAnswered.length > 0 && !this.isWaiting;
    }

    get isInputDisabled() {
        return this.needsTestMode || !this.recordId;
    }

    get isSendDisabled() {
        return this.isInputDisabled || this.isSending || this.isWaiting || !this.draft.trim();
    }

    handleRecord(event) {
        const recordId = event.detail.recordId || null;
        if (recordId === this.recordId) return;
        // A different record is a different conversation.
        this.recordId = recordId;
        this.conversationId = undefined;
        this.messages = [];
        this.howItAnswered = [];
        this.stopPolling();
        this.isWaiting = false;
    }

    handleDraft(event) {
        this.draft = event.target.value;
    }

    handleKey(event) {
        if (event.key === 'Enter' && !this.isSendDisabled) {
            event.preventDefault();
            this.handleSend();
        }
    }

    async handleSend() {
        const text = this.draft.trim();
        if (!text) return;

        this.isSending = true;
        this.error = undefined;
        try {
            const result = await sendTryIt({ agentId: this.state.agentId, recordId: this.recordId, text, conversationId: this.conversationId || null });
            this.draft = '';
            this.apply(result);
            this.isWaiting = true;
            this.startPolling();
        } catch (error) {
            this.error = reduceError(error);
        } finally {
            this.isSending = false;
        }
    }

    apply(result) {
        this.conversationId = result.conversationId;
        this.messages = result.messages.map((message) => ({
            ...message,
            bubbleClass: message.isUser ? 'aic-bubble aic-bubble_user' : message.isAgent ? 'aic-bubble agent' : 'aic-bubble system'
        }));
        this.howItAnswered = result.howItAnswered || [];
    }

    startPolling() {
        this.stopPolling();
        this.pollStartedAt = Date.now();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.pollTimer = setInterval(() => this.poll(), POLL_EVERY_MS);
    }

    stopPolling() {
        if (this.pollTimer) clearInterval(this.pollTimer);
        this.pollTimer = undefined;
    }

    async poll() {
        try {
            const result = await getTryItUpdate({ conversationId: this.conversationId });
            this.apply(result);
            const last = result.messages[result.messages.length - 1];
            const replied = last && !last.isUser && !result.isProcessing;
            if (replied) {
                this.isWaiting = false;
                this.stopPolling();
            } else if (Date.now() - this.pollStartedAt > GIVE_UP_AFTER_MS) {
                this.isWaiting = false;
                this.stopPolling();
                this.error = 'No reply yet. Check Activity › Error Log if it doesn’t arrive.';
            }
        } catch (error) {
            this.isWaiting = false;
            this.stopPolling();
            this.error = reduceError(error);
        }
    }

    async handleEnableTestMode() {
        this.isEnabling = true;
        this.error = undefined;
        try {
            await setAgentStatus({ agentId: this.state.agentId, mode: 'test' });
            const state = await getWizard({ agentId: this.state.agentId });
            this.dispatchEvent(new CustomEvent('statechange', { detail: { state } }));
        } catch (error) {
            this.error = reduceError(error);
        } finally {
            this.isEnabling = false;
        }
    }
}