import { LightningElement, api } from 'lwc';
import LightningConfirm from 'lightning/confirm';
import getConversationDetail from '@salesforce/apex/AIConsoleController.getConversationDetail';
import closeConversation from '@salesforce/apex/AIConsoleController.closeConversation';
import AiConsolePiiMappingsModal from 'c/aiConsolePiiMappingsModal';
import { TABS, SECTIONS, VIEWS, navigate, reduceError, toast, badgeClass, formatNumber } from 'c/aiConsoleUtils';

/*
Activity › Conversations › one conversation. The transcript is shown as the user saw it (PII restored
server-side); picking "Steps" on a reply shows what happened behind it - template, masking, each Data
Source call, the provider callout and any suggested action.
*/
export default class AiConversationDetail extends LightningElement {
    detail;
    error;
    isClosing = false;
    isLoadingSteps = false;

    _recordId;
    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        if (value === this._recordId) return;
        this._recordId = value;
        this.load(null);
    }

    async load(stepsForMessageId) {
        if (!this._recordId) return;
        try {
            this.detail = await getConversationDetail({ conversationId: this._recordId, stepsForMessageId });
            this.error = undefined;
        } catch (error) {
            this.error = reduceError(error);
        }
    }

    get statusClass() {
        return badgeClass(this.detail.statusVariant);
    }

    get templateName() {
        return this.detail.templateName || '—';
    }

    get channel() {
        return this.detail.channel || '—';
    }

    get transcriptNote() {
        const count = this.detail.messageCount;
        return `${count} ${count === 1 ? 'message' : 'messages'} · as the user saw them, with PII restored`;
    }

    get noMessages() {
        return !this.detail.messages.length;
    }

    get messages() {
        return this.detail.messages.map((message) => {
            const isSelected = message.id === this.detail.stepsForMessageId;
            const meta = [message.timeLabel];
            if (message.isAgent && message.tokens) meta.push(`${formatNumber(message.tokens)} tokens`);

            let bubbleClass = 'bubble';
            if (message.isUser) bubbleClass += ' bubble_user';
            if (!message.isUser && !message.isAgent) bubbleClass += ' bubble_system';
            if (isSelected) bubbleClass += ' bubble_selected';

            return {
                ...message,
                metaLabel: meta.join(' · '),
                wrapperClass: message.isUser ? 'msg msg_user' : message.suggestedAction ? 'msg msg_wide' : 'msg',
                bubbleClass,
                isHelpful: message.rating === 'Helpful',
                isNotHelpful: message.rating === 'Not Helpful',
                canShowSteps: message.isAgent && message.hasSteps && !isSelected,
                actionStatus: message.suggestedActionRun ? 'Run' : 'Not run'
            };
        });
    }

    get hasSteps() {
        return this.detail.steps && this.detail.steps.length > 0;
    }

    get steps() {
        return this.detail.steps.map((step) => ({
            ...step,
            numberClass: step.isSuccess ? 'num' : 'num num_failed',
            detailClass: step.isMono ? 'step__detail step__detail_mono' : 'step__detail'
        }));
    }

    async handleShowSteps(event) {
        this.isLoadingSteps = true;
        await this.load(event.currentTarget.dataset.id);
        this.isLoadingSteps = false;
    }

    handleBack(event) {
        event.preventDefault();
        this.dispatchEvent(new CustomEvent('back'));
    }

    handleOpenUser(event) {
        event.preventDefault();
        navigate(this, { tab: TABS.SETTINGS, section: SECTIONS.SETTINGS_USERS });
    }

    handleOpenAgent(event) {
        event.preventDefault();
        navigate(this, { tab: TABS.AGENTS, section: SECTIONS.AGENTS_ALL, view: VIEWS.RECORD, recordId: this.detail.agentId });
    }

    handleOpenRecord(event) {
        event.preventDefault();
        navigate(this, { tab: TABS.RECORD, recordId: this.detail.recordId });
    }

    async handlePiiMappings() {
        await AiConsolePiiMappingsModal.open({ size: 'small', label: 'PII mappings', conversationId: this._recordId, conversationName: this.detail.name });
    }

    async handleClose() {
        const confirmed = await LightningConfirm.open({
            message: `${this.detail.userName} won’t be able to add to ${this.detail.name} after it’s closed.`,
            label: 'Close this conversation?',
            theme: 'warning'
        });
        if (!confirmed) return;

        this.isClosing = true;
        try {
            await closeConversation({ conversationId: this._recordId });
            toast(this, 'Conversation closed', this.detail.name);
            await this.load(this.detail.stepsForMessageId);
        } catch (error) {
            toast(this, 'Couldn’t close the conversation', reduceError(error), 'error');
        } finally {
            this.isClosing = false;
        }
    }
}
