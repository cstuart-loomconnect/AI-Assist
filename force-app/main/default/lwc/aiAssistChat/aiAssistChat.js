import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { subscribe, unsubscribe, onError, isEmpEnabled } from 'lightning/empApi';
import { EnclosingUtilityId, setUtilityHighlighted } from 'lightning/platformUtilityBarApi';

import getChatContext from '@salesforce/apex/AIChatController.getChatContext';
import getEarlierMessages from '@salesforce/apex/AIChatController.getEarlierMessages';
import getConversationUpdate from '@salesforce/apex/AIChatController.getConversationUpdate';
import sendMessage from '@salesforce/apex/AIChatController.sendMessage';
import retryLatestMessage from '@salesforce/apex/AIChatController.retryLatestMessage';
import closeConversation from '@salesforce/apex/AIChatController.closeConversation';
import openConversation from '@salesforce/apex/AIChatController.openConversation';
import resumeConversation from '@salesforce/apex/AIChatController.resumeConversation';
import getConversationHistory from '@salesforce/apex/AIChatController.getConversationHistory';
import submitFeedback from '@salesforce/apex/AIChatController.submitFeedback';
import acknowledgeTerms from '@salesforce/apex/AIChatController.acknowledgeTerms';
import runSuggestedAction from '@salesforce/apex/AIChatController.runSuggestedAction';
import getDebugTrace from '@salesforce/apex/AIChatController.getDebugTrace';
import getPiiMappings from '@salesforce/apex/AIChatController.getPiiMappings';
import AiChatPiiMappingsModal from 'c/aiChatPiiMappingsModal';
import getFailureDetail from '@salesforce/apex/AIChatController.getFailureDetail';
import exportConversation from '@salesforce/apex/AIChatController.exportConversation';

import {
    CHAT_STATE,
    SEND_STATUS,
    CHANNEL,
    LABELS,
    FEEDBACK_RATING,
    MESSAGE_READY_CHANNEL,
    AGENT_PROGRESS_CHANNEL,
    MIN_CHAT_WIDTH_PX,
    formatUsage,
    formatTime,
    formatDaySeparator,
    formatTokenCount,
    formatElapsed,
    getDayDifference,
    markdownToHtml,
    reduceError,
    isSameId,
    downloadTextFile,
    toTranscriptFileName,
    nextLocalId
} from 'c/aiChatUtils';

const DEFAULT_ACCENT = '#3040C4';
const WAIT_TICK_MS = 1000;
const POLL_AFTER_SECONDS = 20; // Event missed? Start polling after this long.
const POLL_EVERY_SECONDS = 5;
const PROCESSING_GRACE_SECONDS = 8; // Unlocked with no reply for this long = the turn failed.
const GIVE_UP_AFTER_SECONDS = 300;
const MENU_END = 'end';
const MENU_EXPORT = 'export';

// Apex ChatMessage -> the shape the children render from. bodyHtml is built once here, not on every render.
const normalizeMessage = (message) => ({
    ...message,
    isServer: true,
    status: 'sent',
    bodyHtml: message.sender === 'agent' ? markdownToHtml(message.displayText) : null
});

/*
The AI Assist chat window. Lives in the utility bar or on a record page, and is the only component
that talks to Apex (AIChatController) - every child is presentational and reports clicks back as
events. Replies arrive through the AIMessageReadyEvent__e platform event (empApi), with polling as
a fallback when the event channel isn't available or an event is missed.
*/
export default class AiAssistChat extends LightningElement {
    @api recordId;
    @api objectApiName;
    @api channel = CHANNEL.RECORD_PAGE;
    @api agentKey;
    @api height = 680;
    @api accentColor = DEFAULT_ACCENT;

    labels = LABELS;

    context;
    isLoading = true;
    loadError;
    view = 'chat'; // 'chat' | 'history'

    conversation = null;
    messages = [];
    hasMoreMessages = false;
    isLoadingEarlier = false;
    usage;

    waiting = null; // { startedAt, elapsedSeconds, lastPollSecond, userMessageId }
    liveSteps = []; // Step labels received over AIAgentProgressEvent__e for the turn currently in waiting.
    errorTurn = null; // { reference, debugDetail, isRetrying, retryError }
    isSending = false;
    composerError;
    isCommandMenuOpen = false;
    isNotifyDismissed = false;

    isAcknowledging = false;
    termsError;

    history = [];
    historyFilter = 'record';
    isHistoryLoading = false;
    historyError;

    feedbackStates = {}; // messageId -> { open, submitting, thanks }
    actionStates = {}; // messageId -> { status, message }
    debugTraces = {}; // messageId -> { trace, error }

    isTooNarrow = false;
    selectedAgentKey;
    pageRecordId;
    pageObjectApiName;

    subscription;
    progressSubscription;
    usePolling = false;
    waitTimer;
    resizeObserver;
    isRefreshing = false;
    isUtilityHighlighted = false;
    hasConnected = false;
    scrollRequest = null; // 'bottom' | 'soft' | 'restore'
    loadSequence = 0;

    @wire(EnclosingUtilityId) utilityId;

    // In the utility bar the record comes from the page the user is on, and follows them as they navigate.
    @wire(CurrentPageReference)
    handlePageReference(pageReference) {
        if (!this.isUtilityBar) return;

        const isRecordPage = pageReference && pageReference.type === 'standard__recordPage';
        const attributes = (pageReference && pageReference.attributes) || {};
        const recordId = isRecordPage ? attributes.recordId : null;

        if (recordId === this.pageRecordId && this.context) return;

        this.pageRecordId = recordId;
        this.pageObjectApiName = isRecordPage ? attributes.objectApiName : null;
        if (this.hasConnected) this.loadContext();
    }

    connectedCallback() {
        this.hasConnected = true;
        this.loadContext();
    }

    disconnectedCallback() {
        this.stopWaiting();
        if (this.subscription) unsubscribe(this.subscription, () => {});
        this.subscription = null;
        if (this.progressSubscription) unsubscribe(this.progressSubscription, () => {});
        this.progressSubscription = null;
        if (this.resizeObserver) this.resizeObserver.disconnect();
        this.resizeObserver = null;
    }

    renderedCallback() {
        this.observeWidth();

        if (!this.scrollRequest) return;
        const list = this.template.querySelector('c-ai-chat-message-list');
        if (!list) return;

        if (this.scrollRequest === 'restore') list.restoreScrollPosition();
        else list.scrollToBottom(this.scrollRequest === 'bottom');
        this.scrollRequest = null;
    }

    // =========================================================
    // Derived context
    // =========================================================

    get isUtilityBar() {
        return this.channel === CHANNEL.UTILITY_BAR;
    }

    get effectiveRecordId() {
        return this.isUtilityBar ? this.pageRecordId : this.recordId;
    }

    get effectiveObjectApiName() {
        return this.isUtilityBar ? this.pageObjectApiName : this.objectApiName;
    }

    get shellStyle() {
        const accent = /^#[0-9a-fA-F]{3,8}$/.test(this.accentColor || '') ? this.accentColor : DEFAULT_ACCENT;
        const height = this.isUtilityBar ? '100%' : `${Number(this.height) || 680}px`;
        return `--aia-accent: ${accent}; height: ${height};`;
    }

    get state() {
        return this.context ? this.context.state : null;
    }

    get ui() {
        return (this.context && this.context.ui) || {};
    }

    get user() {
        return (this.context && this.context.user) || {};
    }

    get record() {
        return (this.context && this.context.record) || {};
    }

    get agent() {
        return this.context ? this.context.agent : null;
    }

    get currentConversationId() {
        return this.conversation ? this.conversation.id : null;
    }

    get termsPolicyUrl() {
        return this.context && this.context.terms ? this.context.terms.policyUrl : null;
    }

    get agentGreeting() {
        return this.agent ? this.agent.greeting : null;
    }

    get hasRecord() {
        return !!this.record.recordId;
    }

    get isReady() {
        return this.state === CHAT_STATE.READY;
    }

    get isInactive() {
        return this.state === CHAT_STATE.INACTIVE;
    }

    get isMaintenance() {
        return this.state === CHAT_STATE.MAINTENANCE;
    }

    get isChannelDisabled() {
        return this.state === CHAT_STATE.CHANNEL_DISABLED;
    }

    get isTerms() {
        return this.state === CHAT_STATE.TERMS;
    }

    get isNoAgent() {
        return this.state === CHAT_STATE.NO_AGENT;
    }

    get isHistoryView() {
        return this.isReady && this.view === 'history';
    }

    // =========================================================
    // Header
    // =========================================================

    get headerBadge() {
        if (this.isInactive) return 'off';
        if (this.isMaintenance) return 'maintenance';
        if (this.isReady && this.user.debugMode) return 'debug';
        return null;
    }

    get agentName() {
        return this.agent ? this.agent.name : null;
    }

    get agentId() {
        return this.agent ? this.agent.id : null;
    }

    get agents() {
        return (this.context && this.context.agents) || [];
    }

    get hasConversation() {
        return !!this.conversation;
    }

    get isNewDisabled() {
        return !!(this.ui.newChatsDisabled || (this.usage && this.usage.blockNewConversations) || this.waiting || this.isSending);
    }

    get headerMenuItems() {
        if (!this.isReady || !this.conversation) return [];
        const items = [];
        if (this.user.exportEnabled) items.push({ value: MENU_EXPORT, label: LABELS.exportConversation, iconName: 'utility:download' });
        if (this.conversation.isActive) items.push({ value: MENU_END, label: LABELS.closeConversation, iconName: 'utility:close' });
        return items;
    }

    // =========================================================
    // Body
    // =========================================================

    get showContextBar() {
        return !!(this.record.recordId && this.hasConversation);
    }

    get showNewChatsPaused() {
        return !!(this.ui.newChatsDisabled && !this.conversation && this.messages.length === 0);
    }

    get showEmptyState() {
        return !this.conversation && this.messages.length === 0 && !this.showNewChatsPaused;
    }

    get showEndedBar() {
        return !!(this.conversation && !this.conversation.isActive);
    }

    get showComposer() {
        return !this.showNewChatsPaused && !this.showEndedBar;
    }

    get canResumeConversation() {
        return !!(this.conversation && this.conversation.canResume);
    }

    get isStartNewDisabled() {
        return !!(this.ui.newChatsDisabled || (this.usage && this.usage.blockNewConversations));
    }

    get commands() {
        return (this.context && this.context.commands) || [];
    }

    get openConversationSummary() {
        return this.context ? this.context.openConversation : null;
    }

    get isNewConversationBlocked() {
        const conversationIsOpen = this.conversation && this.conversation.isActive;
        return !conversationIsOpen && !!(this.usage && this.usage.blockNewConversations);
    }

    get isComposerDisabled() {
        return !!((this.usage && this.usage.blockMessages) || this.isNewConversationBlocked || this.isSending);
    }

    get composerPlaceholder() {
        if (this.usage && this.usage.blockMessages) return LABELS.composerPlaceholderBlocked;
        if (this.isNewConversationBlocked) return LABELS.composerPlaceholderNoNewChats;
        return this.record.recordId ? LABELS.composerPlaceholder : LABELS.composerPlaceholderNoRecord;
    }

    get composerFooter() {
        return this.user.debugMode ? LABELS.debugFooter : LABELS.disclaimer;
    }

    get usageLabel() {
        return formatUsage(this.usage);
    }

    get isUsageOver() {
        return !!(this.usage && this.usage.limitReached);
    }

    get usageBannerVariant() {
        const usage = this.usage;
        if (!usage || !this.isReady) return null;
        if (usage.blockMessages) return 'block';
        if (usage.blockNewConversations) return 'conversations';
        if (usage.notifyOnly && !this.isNotifyDismissed) return 'notify';
        return null;
    }

    get usageResetsInMinutes() {
        return this.usage ? this.usage.resetsInMinutes : null;
    }

    get isWorking() {
        return !!this.waiting;
    }

    // Steps mode shows AIAgentProgressEvent__e's labels as they arrive, oldest first - every one but the latest is done, the latest is active. Before the first arrives (or if live progress isn't reaching this session), a generic placeholder holds that spot instead. "Write the answer" is always shown last and pending - every turn ends by writing the reply, whatever led up to it.
    get working() {
        if (!this.waiting) return null;
        const recordName = this.record.recordName;
        if (this.ui.showExecutionTrace) {
            const steps = this.liveSteps.map((label) => ({ label, state: 'done' }));
            if (steps.length) steps[steps.length - 1].state = 'active';
            else steps.push({ label: recordName ? `Reading ${recordName} and thinking` : LABELS.stepReading, state: 'active' });
            steps.push({ label: LABELS.stepWriting, state: 'pending' });

            return { mode: 'steps', elapsedLabel: formatElapsed(this.waiting.elapsedSeconds), steps };
        }
        if (this.ui.typingIndicatorEnabled) {
            return { mode: 'typing', label: recordName ? `Working on ${recordName}…` : `${LABELS.workingHeading}…` };
        }
        return null;
    }

    // The view models aiChatMessageList renders - every per-message flag is decided here so the children stay simple.
    get messageItems() {
        const ui = this.ui;
        const debugMode = !!this.user.debugMode;
        const conversationActive = !!(this.conversation && this.conversation.isActive);
        const agentName = (this.conversation && this.conversation.agentName) || this.agentName || LABELS.appName;
        const lastAgentIndex = this.findLastIndex((message) => message.sender === 'agent' && message.isServer);
        const firstRealIndex = this.messages.findIndex((message) => !message.isNotice);

        let previousDate = null;
        let agentHeaderShown = false;

        return this.messages.map((message, index) => {
            if (message.isNotice) return { id: message.id, isNotice: true, noticeText: message.noticeText };

            const createdDate = new Date(message.createdDate);
            let separatorLabel = null;
            if ((index === firstRealIndex && !this.hasMoreMessages) || (previousDate && getDayDifference(previousDate, createdDate) !== 0)) {
                separatorLabel = formatDaySeparator(createdDate);
            }
            previousDate = createdDate;

            const base = {
                id: message.id,
                separatorLabel,
                displayText: message.displayText,
                timeLabel: formatTime(message.createdDate),
                showTimestamp: !!ui.showTimestamps && message.status === 'sent'
            };

            if (message.sender === 'user') {
                return {
                    ...base,
                    isUser: true,
                    isCommand: !!message.isCommand,
                    commandName: message.commandName,
                    commandRest: message.isCommand ? message.displayText.slice(message.commandName.length).trim() : null,
                    isSending: message.status === 'sending',
                    isBlocked: message.status === 'blocked',
                    blockedReason: message.blockedReason
                };
            }

            const showAgentHeader = !agentHeaderShown;
            agentHeaderShown = true;
            const feedback = this.feedbackStates[message.id] || {};
            const trace = this.debugTraces[message.id];
            const sources = message.sources || [];

            return {
                ...base,
                isAgent: true,
                bodyHtml: message.bodyHtml,
                showAgentHeader,
                agentName,
                hasSources: sources.length > 0,
                sources: sources.map((label, sourceIndex) => ({ key: `${sourceIndex}`, label })),
                showFeedback: !!ui.feedbackEnabled,
                isHelpful: message.feedbackRating === FEEDBACK_RATING.HELPFUL,
                isNotHelpful: message.feedbackRating === FEEDBACK_RATING.NOT_HELPFUL,
                feedbackOpen: !!feedback.open,
                feedbackSubmitting: !!feedback.submitting,
                feedbackThanks: !!feedback.thanks,
                canRegenerate: index === lastAgentIndex && conversationActive && !this.waiting && !this.errorTurn,
                tokenLabel: message.tokenCount ? formatTokenCount(message.tokenCount) : null,
                suggestedAction: message.suggestedAction,
                actionsDisplay: ui.suggestedActionsDisplay,
                actionState: this.actionStates[message.id] || { status: 'idle' },
                showTrace: debugMode && !!trace,
                trace: trace ? trace.trace : null,
                traceError: trace ? trace.error : null,
                showTraceLink: debugMode && !trace
            };
        });
    }

    // =========================================================
    // Loading
    // =========================================================

    async loadContext() {
        const sequence = ++this.loadSequence;
        this.isLoading = true;
        this.loadError = null;
        this.stopWaiting();

        try {
            const context = await getChatContext({
                recordId: this.effectiveRecordId || null,
                objectApiName: this.effectiveObjectApiName || null,
                channel: this.channel,
                agentKey: this.selectedAgentKey || this.agentKey || null
            });
            if (sequence !== this.loadSequence) return; // A newer load (navigation, agent switch) replaced this one.

            this.context = context;
            this.usage = context.usage;
            this.isNotifyDismissed = false;
            this.view = 'chat';
            this.applyConversation(context.conversation);

            if (context.state === CHAT_STATE.READY) {
                this.subscribeToReplies();
                this.subscribeToProgress();
            }
        } catch (error) {
            if (sequence === this.loadSequence) this.loadError = reduceError(error);
        } finally {
            if (sequence === this.loadSequence) this.isLoading = false;
        }
    }

    // Shows a conversation (or none - a new one) and resets everything tied to the previous one.
    applyConversation(view) {
        this.stopWaiting();
        this.feedbackStates = {};
        this.actionStates = {};
        this.debugTraces = {};
        this.errorTurn = null;
        this.composerError = null;

        if (!view) {
            this.conversation = null;
            this.messages = [];
            this.hasMoreMessages = false;
            return;
        }

        this.conversation = {
            id: view.id,
            name: view.name,
            title: view.title,
            status: view.status,
            isActive: view.isActive,
            canResume: view.canResume,
            agentName: view.agentName
        };
        this.messages = (view.messages || []).map(normalizeMessage);
        this.hasMoreMessages = view.hasMoreMessages;
        this.scrollRequest = 'bottom';

        if (view.isProcessing && view.isActive) this.startWaiting();
        this.loadLatestTrace();
    }

    async handleLoadEarlier() {
        const oldest = this.messages.find((message) => message.isServer);
        if (!oldest || this.isLoadingEarlier) return;

        const list = this.template.querySelector('c-ai-chat-message-list');
        if (list) list.captureScrollPosition();
        this.isLoadingEarlier = true;

        try {
            const page = await getEarlierMessages({ conversationId: this.conversation.id, beforeMessageId: oldest.id });
            this.messages = [...page.messages.map(normalizeMessage), ...this.messages];
            this.hasMoreMessages = page.hasMore;
            this.scrollRequest = 'restore';
        } catch (error) {
            this.toastError(error);
        } finally {
            this.isLoadingEarlier = false;
        }
    }

    // =========================================================
    // Sending and waiting for the reply
    // =========================================================

    async handleSend(event) {
        const text = event.detail.text;
        if (this.isSending || !this.agent) return;

        this.isSending = true;
        this.composerError = null;
        this.errorTurn = null;

        const localId = nextLocalId();
        const commandMatch = text.match(/^\/[A-Za-z0-9_-]+/);
        this.messages = [
            ...this.messages,
            { id: localId, sender: 'user', displayText: text, isCommand: !!commandMatch, commandName: commandMatch ? commandMatch[0] : null, createdDate: new Date().toISOString(), status: 'sending' }
        ];
        this.callComposer('clear');
        this.scrollRequest = 'bottom';

        const openConversationId = this.conversation && this.conversation.isActive ? this.conversation.id : null;

        try {
            const result = await sendMessage({
                requestJson: JSON.stringify({
                    conversationId: openConversationId,
                    agentId: this.agent.id,
                    text,
                    channel: this.channel,
                    recordId: this.record.recordId || null,
                    objectApiName: this.record.objectApiName || null
                })
            });

            if (result.usage) this.usage = result.usage;

            if (result.status === SEND_STATUS.SENT) {
                this.handleSent(result, localId, text, openConversationId);
            } else if (result.status === SEND_STATUS.BLOCKED || result.status === SEND_STATUS.LIMIT) {
                this.updateMessage(localId, { status: 'blocked', blockedReason: result.message });
            } else {
                this.restoreUnsent(localId, text, result.message);
            }
        } catch (error) {
            this.restoreUnsent(localId, text, reduceError(error));
        } finally {
            this.isSending = false;
        }
    }

    handleSent(result, localId, text, openConversationId) {
        const sentMessage = normalizeMessage(result.userMessage);

        // The open conversation hit its Agent's message/token cap, so the service closed it and started a new one.
        if (result.isNewConversation && openConversationId) {
            this.feedbackStates = {};
            this.actionStates = {};
            this.debugTraces = {};
            this.hasMoreMessages = false;
            this.messages = [{ id: nextLocalId('notice'), isNotice: true, noticeText: LABELS.newConversationStarted }, sentMessage];
        } else {
            this.messages = this.messages.map((message) => (message.id === localId ? sentMessage : message));
        }

        if (result.isNewConversation || !this.conversation) {
            this.conversation = {
                id: result.conversationId,
                title: text.slice(0, 60),
                status: 'Active',
                isActive: true,
                canResume: false,
                agentName: this.agentName
            };
            this.context = { ...this.context, openConversation: null };
        }

        this.scrollRequest = 'bottom';
        this.startWaiting();
    }

    restoreUnsent(localId, text, message) {
        this.messages = this.messages.filter((item) => item.id !== localId);
        this.callComposer('setText', text);
        this.composerError = message;
    }

    startWaiting() {
        this.stopWaiting();
        const pendingUserMessage = this.findLast((message) => message.sender === 'user' && message.isServer);
        this.liveSteps = [];
        this.waiting = { startedAt: Date.now(), elapsedSeconds: 0, lastPollSecond: 0, userMessageId: pendingUserMessage ? pendingUserMessage.id : null };
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.waitTimer = setInterval(() => this.tickWaiting(), WAIT_TICK_MS);
    }

    stopWaiting() {
        if (this.waitTimer) clearInterval(this.waitTimer);
        this.waitTimer = null;
        this.waiting = null;
    }

    // Once a second: the elapsed clock, the polling fallback, and giving up eventually.
    tickWaiting() {
        if (!this.waiting) return;

        const elapsedSeconds = Math.floor((Date.now() - this.waiting.startedAt) / 1000);
        if (elapsedSeconds >= GIVE_UP_AFTER_SECONDS) {
            this.handleReplyFailed();
            return;
        }

        const shouldPoll = (this.usePolling || elapsedSeconds >= POLL_AFTER_SECONDS) && elapsedSeconds - this.waiting.lastPollSecond >= POLL_EVERY_SECONDS;
        this.waiting = { ...this.waiting, elapsedSeconds, lastPollSecond: shouldPoll ? elapsedSeconds : this.waiting.lastPollSecond };

        if (shouldPoll) this.refreshConversation();
    }

    // Stop only stops waiting here - the reply is still generated and saved, and appears if it arrives.
    handleStop() {
        this.stopWaiting();
        this.messages = [...this.messages, { id: nextLocalId('notice'), isNotice: true, noticeText: LABELS.stoppedWaiting }];
        this.scrollRequest = 'bottom';
    }

    // Pulls in everything newer than the last saved message. Done waiting once the newest message is a reply; failed if the lock is gone and no reply came.
    async refreshConversation() {
        if (!this.conversation || this.isRefreshing) return;
        this.isRefreshing = true;

        try {
            const lastSaved = this.findLast((message) => message.isServer);
            const update = await getConversationUpdate({ conversationId: this.conversation.id, afterMessageId: lastSaved ? lastSaved.id : null });

            if (update.usage) this.usage = update.usage;

            const knownIds = new Set(this.messages.map((message) => message.id));
            const freshMessages = update.messages.filter((message) => !knownIds.has(message.id)).map(normalizeMessage);

            if (freshMessages.length) {
                this.messages = [...this.messages, ...freshMessages];
                this.scrollRequest = 'soft';
            }

            this.conversation = { ...this.conversation, status: update.status, isActive: update.status === 'Active' };

            const newest = this.findLast((message) => message.isServer);
            const isAnswered = newest && newest.sender === 'agent';

            if (isAnswered && freshMessages.some((message) => message.sender === 'agent')) {
                this.highlightUtility();
                this.loadLatestTrace();
            }

            if (this.waiting) {
                if (isAnswered) this.stopWaiting();
                else if (!update.isProcessing && this.waiting.elapsedSeconds >= PROCESSING_GRACE_SECONDS) this.handleReplyFailed();
            }
        } catch (error) {
            // Left waiting - the next poll tries again.
        } finally {
            this.isRefreshing = false;
        }
    }

    async handleReplyFailed() {
        this.stopWaiting();
        this.errorTurn = { reference: null, debugDetail: null, isRetrying: false, retryError: null };
        this.scrollRequest = 'bottom';

        if (!this.conversation) return;
        try {
            const detail = await getFailureDetail({ conversationId: this.conversation.id });
            if (this.errorTurn) this.errorTurn = { ...this.errorTurn, reference: detail.reference, debugDetail: detail.debugDetail };
        } catch (error) {
            // The card still works without a reference.
        }
    }

    // Try again (failed reply) and Regenerate (newest reply) both re-run the newest user message.
    async handleRetry() {
        if (!this.conversation) return;
        if (this.errorTurn) this.errorTurn = { ...this.errorTurn, isRetrying: true, retryError: null };

        try {
            await retryLatestMessage({ conversationId: this.conversation.id });
            this.errorTurn = null;
            this.startWaiting();
            this.scrollRequest = 'bottom';
        } catch (error) {
            if (this.errorTurn) this.errorTurn = { ...this.errorTurn, isRetrying: false, retryError: reduceError(error) };
            else this.toastError(error);
        }
    }

    // =========================================================
    // Real-time replies
    // =========================================================

    async subscribeToReplies() {
        if (this.subscription) return;
        try {
            const isEnabled = await isEmpEnabled();
            if (!isEnabled) {
                this.usePolling = true;
                return;
            }
            onError(() => {
                this.usePolling = true;
            });
            this.subscription = await subscribe(MESSAGE_READY_CHANNEL, -1, (event) => this.handleMessageReady(event));
        } catch (error) {
            this.usePolling = true;
        }
    }

    // Best-effort only - if empApi isn't available (usePolling), the working card just falls back to its generic placeholder for that step. Never widens usePolling itself: a subscribe here failing says nothing about whether AIMessageReadyEvent__e will arrive.
    async subscribeToProgress() {
        if (this.progressSubscription) return;
        try {
            const isEnabled = await isEmpEnabled();
            if (!isEnabled) return;
            this.progressSubscription = await subscribe(AGENT_PROGRESS_CHANNEL, -1, (event) => this.handleProgressEvent(event));
        } catch (error) {
            // No live steps this session - the working card's placeholder covers it.
        }
    }

    handleProgressEvent(event) {
        const payload = (event && event.data && event.data.payload) || {};
        if (!this.waiting || !this.conversation) return;
        if (!isSameId(payload.AIConversationId__c, this.conversation.id)) return;
        if (!isSameId(payload.UserMessageId__c, this.waiting.userMessageId)) return;

        if (payload.StepLabel__c) this.liveSteps = [...this.liveSteps, payload.StepLabel__c];
    }

    handleMessageReady(event) {
        const payload = (event && event.data && event.data.payload) || {};
        if (!this.conversation || !isSameId(payload.AIConversationId__c, this.conversation.id)) return;

        if (payload.IsSuccess__c === false) this.handleReplyFailed();
        else this.refreshConversation();
    }

    highlightUtility() {
        if (!this.utilityId || !this.isUtilityBar) return;
        this.isUtilityHighlighted = true;
        setUtilityHighlighted(this.utilityId, { highlighted: true }).catch(() => {});
    }

    handleShellClick() {
        if (!this.isUtilityHighlighted || !this.utilityId) return;
        this.isUtilityHighlighted = false;
        setUtilityHighlighted(this.utilityId, { highlighted: false }).catch(() => {});
    }

    // =========================================================
    // Message actions (from aiChatMessage, bubbled through the list)
    // =========================================================

    handleMessageAction(event) {
        event.stopPropagation();
        const { action, messageId } = event.detail;

        if (action === 'rate') this.rateMessage(messageId, event.detail.rating);
        else if (action === 'submitfeedback') this.sendFeedbackDetail(messageId, event.detail.reason, event.detail.comment);
        else if (action === 'closefeedback') this.setFeedbackState(messageId, { open: false });
        else if (action === 'regenerate') this.handleRetry();
        else if (action === 'runaction') this.runAction(messageId, event.detail.inputs);
        else if (action === 'dismissaction') this.setActionState(messageId, { status: 'dismissed' });
        else if (action === 'editblocked') this.editBlockedMessage(messageId, event.detail.text);
        else if (action === 'loadtrace') this.loadTrace(messageId);
        else if (action === 'closetrace') this.closeTrace(messageId);
        else if (action === 'viewpiimappings') this.showPiiMappings(messageId);
    }

    // The rating saves straight away; thumbs down also opens "What went wrong?" for the optional detail.
    async rateMessage(messageId, rating) {
        const message = this.messages.find((item) => item.id === messageId);
        const previousRating = message ? message.feedbackRating : null;

        this.updateMessage(messageId, { feedbackRating: rating });
        this.setFeedbackState(messageId, { open: rating === FEEDBACK_RATING.NOT_HELPFUL, thanks: false });

        try {
            await submitFeedback({ messageId, rating, reason: null, comment: null });
        } catch (error) {
            this.updateMessage(messageId, { feedbackRating: previousRating });
            this.setFeedbackState(messageId, { open: false });
            this.toastError(error);
        }
    }

    async sendFeedbackDetail(messageId, reason, comment) {
        this.setFeedbackState(messageId, { submitting: true });
        try {
            await submitFeedback({ messageId, rating: FEEDBACK_RATING.NOT_HELPFUL, reason, comment });
            this.setFeedbackState(messageId, { open: false, submitting: false, thanks: true });
        } catch (error) {
            this.setFeedbackState(messageId, { submitting: false });
            this.toastError(error);
        }
    }

    async runAction(messageId, inputs) {
        this.setActionState(messageId, { status: 'running' });
        try {
            const result = await runSuggestedAction({ messageId, inputsJson: JSON.stringify(inputs || {}) });
            this.setActionState(messageId, { status: result.isSuccess ? 'done' : 'failed', message: result.message });
        } catch (error) {
            this.setActionState(messageId, { status: 'failed', message: reduceError(error) });
        }
    }

    editBlockedMessage(messageId, text) {
        this.messages = this.messages.filter((message) => message.id !== messageId);
        this.callComposer('setText', text);
    }

    async loadTrace(messageId) {
        if (!messageId || this.debugTraces[messageId]) return;
        this.debugTraces = { ...this.debugTraces, [messageId]: { trace: null, error: null } };
        try {
            const trace = await getDebugTrace({ messageId });
            this.debugTraces = { ...this.debugTraces, [messageId]: { trace, error: null } };
        } catch (error) {
            this.debugTraces = { ...this.debugTraces, [messageId]: { trace: null, error: reduceError(error) } };
        }
    }

    // Dropping the loaded trace puts the "Show request trace" link back - opening it again reloads it fresh.
    closeTrace(messageId) {
        const remaining = { ...this.debugTraces };
        delete remaining[messageId];
        this.debugTraces = remaining;
    }

    // Loaded only when asked for, since it holds the real values the AI provider never saw.
    async showPiiMappings(messageId) {
        try {
            const mappingJson = await getPiiMappings({ messageId });
            const loaded = this.debugTraces[messageId];
            await AiChatPiiMappingsModal.open({
                size: 'medium',
                label: LABELS.piiMappingsHeading,
                mappingJson,
                conversationName: loaded && loaded.trace ? loaded.trace.conversationName : ''
            });
        } catch (error) {
            this.toastError(error);
        }
    }

    // Debug mode opens the trace for the newest reply automatically; older ones load on request.
    loadLatestTrace() {
        if (!this.user.debugMode) return;
        const latestReply = this.findLast((message) => message.sender === 'agent' && message.isServer);
        if (latestReply) this.loadTrace(latestReply.id);
    }

    // =========================================================
    // Header, history and conversation lifecycle
    // =========================================================

    handleAgentSelect(event) {
        this.selectedAgentKey = event.detail.agentId;
        this.loadContext();
    }

    // Ends the open conversation (so single-conversation Agents and concurrency limits stay correct) and shows a fresh one.
    async handleNewConversation() {
        this.view = 'chat';
        const hasSavedMessages = this.messages.some((message) => message.isServer);

        if (this.conversation && this.conversation.isActive && hasSavedMessages) {
            try {
                await closeConversation({ conversationId: this.conversation.id });
            } catch (error) {
                this.toastError(error);
                return;
            }
        }

        this.applyConversation(null);
        this.context = { ...this.context, openConversation: null };
        this.callComposer('focus');
    }

    async handleMenuSelect(event) {
        const value = event.detail.value;
        if (!this.conversation) return;

        if (value === MENU_END) {
            try {
                await closeConversation({ conversationId: this.conversation.id });
                this.stopWaiting();
                this.conversation = { ...this.conversation, isActive: false, status: 'Closed', canResume: !!(this.agent && this.agent.allowResume) };
            } catch (error) {
                this.toastError(error);
            }
        } else if (value === MENU_EXPORT) {
            try {
                const transcript = await exportConversation({ conversationId: this.conversation.id });
                downloadTextFile(toTranscriptFileName(this.conversation.name), transcript);
            } catch (error) {
                this.toastError(error);
            }
        }
    }

    async handleResume() {
        try {
            const view = await resumeConversation({ conversationId: this.conversation.id });
            this.applyConversation(view);
        } catch (error) {
            this.toastError(error);
        }
    }

    handleStartNew() {
        this.applyConversation(null);
        this.context = { ...this.context, openConversation: null };
    }

    handleOpenHistory() {
        this.view = 'history';
        this.historyFilter = this.record.recordId ? 'record' : 'all';
        this.loadHistory();
    }

    handleHistoryBack() {
        this.view = 'chat';
        this.scrollRequest = 'bottom';
    }

    handleHistoryFilter(event) {
        this.historyFilter = event.detail.filter;
        this.loadHistory();
    }

    async loadHistory() {
        this.isHistoryLoading = true;
        this.historyError = null;
        try {
            this.history = await getConversationHistory({ recordId: this.record.recordId || null, onlyThisRecord: this.historyFilter === 'record' });
        } catch (error) {
            this.historyError = reduceError(error);
        } finally {
            this.isHistoryLoading = false;
        }
    }

    async handleOpenConversation(event) {
        const conversationId = event.detail.conversationId;
        try {
            const view = await openConversation({ conversationId });
            this.applyConversation(view);
            this.view = 'chat';
        } catch (error) {
            this.toastError(error);
        }
    }

    async handleAgreeTerms() {
        this.isAcknowledging = true;
        this.termsError = null;
        try {
            await acknowledgeTerms();
            await this.loadContext();
        } catch (error) {
            this.termsError = reduceError(error);
        } finally {
            this.isAcknowledging = false;
        }
    }

    handleCheckAgain() {
        this.loadContext();
    }

    handleCommandSelect(event) {
        this.callComposer('setText', `${event.detail.command} `);
    }

    handleCommandMenuToggle(event) {
        this.isCommandMenuOpen = event.detail.open;
    }

    handleDismissNotify() {
        this.isNotifyDismissed = true;
    }

    // =========================================================
    // Helpers
    // =========================================================

    // Below MIN_CHAT_WIDTH_PX the window asks for a wider region instead of rendering cramped.
    observeWidth() {
        if (this.resizeObserver || typeof ResizeObserver === 'undefined') return;
        this.resizeObserver = new ResizeObserver((entries) => {
            const width = entries[0].contentRect.width;
            const isTooNarrow = width > 0 && width < MIN_CHAT_WIDTH_PX;
            if (isTooNarrow !== this.isTooNarrow) this.isTooNarrow = isTooNarrow;
        });
        this.resizeObserver.observe(this.template.host);
    }

    // Parent -> child calls into the composer (setText, clear, focus).
    callComposer(method, argument) {
        const composer = this.template.querySelector('c-ai-chat-composer');
        if (composer) composer[method](argument);
    }

    updateMessage(messageId, changes) {
        this.messages = this.messages.map((message) => (message.id === messageId ? { ...message, ...changes } : message));
    }

    setFeedbackState(messageId, changes) {
        this.feedbackStates = { ...this.feedbackStates, [messageId]: { ...(this.feedbackStates[messageId] || {}), ...changes } };
    }

    setActionState(messageId, state) {
        this.actionStates = { ...this.actionStates, [messageId]: state };
    }

    findLast(predicate) {
        const index = this.findLastIndex(predicate);
        return index < 0 ? null : this.messages[index];
    }

    findLastIndex(predicate) {
        for (let index = this.messages.length - 1; index >= 0; index--) {
            if (predicate(this.messages[index])) return index;
        }
        return -1;
    }

    toastError(error) {
        this.dispatchEvent(new ShowToastEvent({ title: LABELS.appName, message: reduceError(error), variant: 'error' }));
    }
}