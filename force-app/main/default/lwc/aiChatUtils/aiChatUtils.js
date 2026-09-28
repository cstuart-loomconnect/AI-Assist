/*
Module: aiChatUtils

Client-side helpers shared by the AI Assist chat window components - formatting, markdown
rendering, command filtering, history grouping and the fixed values mirrored from
AIAssistApplicationConstants. No Apex calls and no component state live here; every function
is pure so any component can import it.
*/

// Mirrors AIAssistApplicationConstants.CHAT_STATE_*.
export const CHAT_STATE = {
    READY: 'READY',
    INACTIVE: 'INACTIVE',
    MAINTENANCE: 'MAINTENANCE',
    CHANNEL_DISABLED: 'CHANNEL_DISABLED',
    NO_AGENT: 'NO_AGENT',
    TERMS: 'TERMS'
};

// Mirrors AIAssistApplicationConstants.CHAT_SEND_STATUS_*.
export const SEND_STATUS = {
    SENT: 'SENT',
    BLOCKED: 'BLOCKED',
    LIMIT: 'LIMIT',
    ERROR: 'ERROR'
};

export const CHANNEL = {
    UTILITY_BAR: 'Utility Bar',
    RECORD_PAGE: 'Record Page Chat'
};

export const FEEDBACK_RATING = {
    HELPFUL: 'Helpful',
    NOT_HELPFUL: 'Not Helpful'
};

export const FEEDBACK_REASONS = ['Not accurate', 'Missing info', 'Wrong record', 'Too long', 'Other'];

export const ACTIONS_DISPLAY_INLINE_BUTTONS = 'Inline Buttons';

export const MESSAGE_READY_CHANNEL = '/event/AIMessageReadyEvent__e';
export const AGENT_PROGRESS_CHANNEL = '/event/AIAgentProgressEvent__e';

// The narrowest the chat window can render in - below this it asks for a wider region.
export const MIN_CHAT_WIDTH_PX = 320;

// Every user-facing string in one place, so wording changes (or a move to Custom Labels) happen here only.
export const LABELS = {
    appName: 'AI Assist',
    disclaimer: 'AI can make mistakes. Check before acting.',
    composerPlaceholder: 'Ask about this record, or type / for commands',
    composerPlaceholderNoRecord: 'Ask anything, or type / for commands',
    composerPlaceholderWorking: 'Wait for the answer, or stop it',
    composerPlaceholderBlocked: 'Messaging is paused until your limit resets',
    composerPlaceholderNoNewChats: 'Starting new conversations is paused',
    messageLabel: 'Message',
    send: 'Send',
    stop: 'Stop',
    commands: 'Commands',
    commandsHint: '↑↓ to move · Enter to use',
    noCommands: 'No commands match',
    newConversation: 'New conversation',
    newConversationDisabled: 'New conversation (disabled by admin)',
    history: 'Conversation history',
    moreOptions: 'More options',
    closeConversation: 'End conversation',
    exportConversation: 'Export conversation',
    switchAgent: 'Switch AI agent',
    piiProtected: 'PII protected',
    piiBanner: 'Personal details on this record are swapped for placeholders before anything is sent to the AI model.',
    piiHowItWorks: 'How this works',
    piiExplanation: 'Names, emails, phone numbers and other personal fields are replaced with placeholders like ‹PERSON_1› before the request leaves Salesforce, and swapped back in the answer you see.',
    suggestedFor: 'Suggested for',
    workingOn: 'Working on',
    defaultGreeting: 'What do you need on this',
    defaultGreetingNoRecord: 'What can I help you with?',
    showEarlier: 'Show earlier messages',
    helpful: 'Helpful',
    notHelpful: 'Not helpful',
    copy: 'Copy',
    copied: 'Copied',
    regenerate: 'Regenerate',
    sources: 'Sources',
    suggestedAction: 'Suggested action',
    editFirst: 'Edit first',
    dismiss: 'Dismiss',
    confirm: 'Confirm',
    cancel: 'Cancel',
    actionDone: 'Done',
    actionFailed: 'Didn’t work',
    workingHeading: 'Working on it',
    stepReading: 'Reading records and thinking',
    stepWriting: 'Write the answer',
    stoppedWaiting: 'Stopped waiting. If the answer finishes, it will still appear in this conversation.',
    notSent: 'Not sent',
    blockedHeading: 'Blocked by a company rule',
    blockedWhy: 'Why?',
    blockedExplanation: 'Your admin sets rules for what can be sent to AI Assist. The message stayed in Salesforce and wasn’t sent to the AI model.',
    editMessage: 'Edit message',
    providerErrorHeading: 'Couldn’t reach the AI service',
    providerErrorBody: 'It didn’t respond in time. Nothing was lost — try again.',
    tryAgain: 'Try again',
    ref: 'Ref',
    feedbackHeading: 'What went wrong?',
    feedbackMore: 'Tell us more (optional)',
    feedbackSkip: 'Skip',
    feedbackSend: 'Send feedback',
    feedbackThanks: 'Thanks — your feedback was sent.',
    close: 'Close',
    back: 'Back to chat',
    conversations: 'Conversations',
    newShort: 'New',
    searchConversations: 'Search conversations',
    thisRecord: 'This record',
    allRecords: 'All records',
    retentionNote: 'Conversations are deleted after the retention period your admin sets.',
    noConversations: 'No conversations yet.',
    noSearchResults: 'No conversations match your search.',
    termsEyebrow: 'Before you start',
    termsHeading: 'A few things to know about AI Assist',
    termsPiiTitle: 'Personal data is masked',
    termsPiiBody: 'Names, emails and phone numbers are replaced with placeholders before they reach the AI model.',
    termsWrongTitle: 'Answers can be wrong',
    termsWrongBody: 'Check anything important against the record before you act on it.',
    termsLoggedTitle: 'Conversations are logged',
    termsLoggedBody: 'Your admin can review usage and messages that break company rules.',
    termsAgreePrefix: 'I’ve read the',
    termsPolicy: 'AI usage policy',
    termsAgreeSuffix: 'and agree to use AI Assist in line with it.',
    termsAgree: 'Agree and continue',
    inactiveBadge: 'Off',
    inactiveHeading: 'AI Assist is turned off',
    inactiveBody: 'Your organisation has paused AI Assist. Contact your Salesforce admin if you need it switched back on.',
    maintenanceBadge: 'Maintenance',
    maintenanceHeading: 'AI Assist is down for maintenance',
    maintenanceBody: 'Your admin is making changes. Your conversations are saved and will be here when it’s back.',
    checkAgain: 'Check again',
    contactAdmin: 'Questions? Contact your Salesforce admin.',
    channelHeading: 'AI Assist isn’t available here',
    channelBody: 'Your admin hasn’t enabled AI Assist in this part of Salesforce for you.',
    noAgentHeading: 'No AI agent is set up here',
    noAgentBody: 'There’s no active AI agent for this page yet. Contact your Salesforce admin.',
    spaceHeading: 'This chat needs more room',
    spaceBody: 'Place AI Assist in a wider region of the page, or use it from the utility bar.',
    loadErrorHeading: 'AI Assist couldn’t load',
    newChatsPausedHeading: 'New conversations are paused',
    newChatsPausedBody: 'Your admin has stopped new chats for now. You can still carry on with a conversation that’s already open.',
    openOnRecord: 'Open on this record',
    continueLabel: 'Continue',
    noOpenConversation: 'No open conversation? Contact your Salesforce admin.',
    lastMessage: 'Last message',
    usageBlockHeading: 'You’ve reached your daily limit',
    usageNotifyHeading: 'You’re over your daily limit',
    usageNotifyBody: 'You can keep going. Your admin can see usage above the limit.',
    usageConversationsHeading: 'Daily limit reached',
    usageConversationsBody: 'You can finish this conversation, but can’t start a new one until your limit resets.',
    today: 'today',
    tokens: 'tokens',
    debugBadge: 'DEBUG',
    debugFooter: 'Debug mode is on for your user only.',
    requestTrace: 'Request trace',
    showTrace: 'Show request trace',
    toolIterations: 'tool iterations',
    attempts: 'attempts',
    sentPreviewPrefix: 'sent:',
    requestJson: 'request.json',
    responseJson: 'response.json',
    copyIds: 'copy ids',
    piiMappings: 'pii mappings',
    closeTrace: 'close trace',
    piiMappingsHeading: 'PII masking pairs',
    piiMappingsSubtitle: 'Real value → masked value sent to the AI provider',
    piiMappingsEmpty: 'Nothing has been masked in this conversation yet.',
    copyJson: 'Copy JSON',
    endedHeading: 'This conversation has ended.',
    resume: 'Continue conversation',
    startNew: 'Start a new conversation',
    newConversationStarted: 'New conversation started',
    earlierThisWeek: 'Earlier this week',
    yesterday: 'Yesterday',
    todayHeading: 'Today',
    older: 'Older'
};

// 12400 -> "12.4k", 50000 -> "50k", 812 -> "812".
export function formatTokensShort(value) {
    const number = Number(value) || 0;
    if (number < 1000) return String(Math.round(number));
    const thousands = number / 1000;
    const rounded = thousands >= 100 ? Math.round(thousands) : Math.round(thousands * 10) / 10;
    return `${rounded}k`;
}

// 1240 -> "1,240 tokens".
export function formatTokenCount(value) {
    if (value === null || value === undefined) return '';
    return `${Number(value).toLocaleString()} ${LABELS.tokens}`;
}

// "12.4k / 50k today", or "12.4k today" with no limit.
export function formatUsage(usage) {
    if (!usage) return '';
    const used = formatTokensShort(usage.tokensUsed);
    return usage.tokenLimit ? `${used} / ${formatTokensShort(usage.tokenLimit)} ${LABELS.today}` : `${used} ${LABELS.today}`;
}

export function formatTime(value) {
    if (!value) return '';
    return new Date(value).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

// "Today · 13:02", "Yesterday · 09:10", "Thu 24 Sep · 16:40".
export function formatDaySeparator(value, now = new Date()) {
    const date = new Date(value);
    const dayDifference = getDayDifference(date, now);
    let day;
    if (dayDifference === 0) day = LABELS.todayHeading;
    else if (dayDifference === 1) day = LABELS.yesterday;
    else day = date.toLocaleDateString([], { weekday: 'short', day: 'numeric', month: 'short' });
    return `${day} · ${formatTime(value)}`;
}

// History list's right-hand date: "13:02" today, "Thu" this week, "24 Sep" older.
export function formatHistoryDate(value, now = new Date()) {
    const date = new Date(value);
    const dayDifference = getDayDifference(date, now);
    if (dayDifference === 0) return formatTime(value);
    if (dayDifference < 7) return date.toLocaleDateString([], { weekday: 'short' });
    return date.toLocaleDateString([], { day: 'numeric', month: 'short' });
}

// 372 -> "6h 12m", 45 -> "45m".
export function formatDuration(minutes) {
    const total = Math.max(0, Math.round(Number(minutes) || 0));
    const hours = Math.floor(total / 60);
    const mins = total % 60;
    return hours > 0 ? `${hours}h ${mins}m` : `${mins}m`;
}

// 4 -> "0:04", 75 -> "1:15".
export function formatElapsed(seconds) {
    const total = Math.max(0, Math.floor(seconds));
    return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, '0')}`;
}

// 2840 -> "2.84s", 410 -> "410ms".
export function formatMilliseconds(value) {
    if (value === null || value === undefined) return '—';
    return value >= 1000 ? `${(value / 1000).toFixed(2)}s` : `${value}ms`;
}

export function getDayDifference(date, now = new Date()) {
    const startOf = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
    return Math.round((startOf(now) - startOf(date)) / 86400000);
}

// Groups history summaries under Today / Yesterday / Earlier this week / Older, keeping order.
export function groupConversations(conversations, now = new Date()) {
    const groups = [];
    const byLabel = new Map();
    (conversations || []).forEach((conversation) => {
        const dayDifference = getDayDifference(new Date(conversation.lastActivity), now);
        let label = LABELS.older;
        if (dayDifference === 0) label = LABELS.todayHeading;
        else if (dayDifference === 1) label = LABELS.yesterday;
        else if (dayDifference < 7) label = LABELS.earlierThisWeek;
        if (!byLabel.has(label)) {
            const group = { label, items: [] };
            byLabel.set(label, group);
            groups.push(group);
        }
        byLabel.get(label).items.push(conversation);
    });
    return groups;
}

// History / "open on this record" badge for a conversation's status.
export function getConversationStatus(summary) {
    if (!summary) return null;
    if (summary.status === 'Active') return { label: 'Active', className: 'aia-status aia-status_active' };
    if (summary.status === 'Archived') return { label: 'Archived', className: 'aia-status' };
    if (summary.closeReason === 'Idle Timeout') return { label: 'Timed out', className: 'aia-status' };
    if (summary.closeReason === 'Message Limit Reached' || summary.closeReason === 'Token Limit Reached') return { label: 'Limit reached', className: 'aia-status' };
    return { label: 'Closed', className: 'aia-status' };
}

// Substring match anywhere in the command (design: "/ri" matches /risk-check, /brief, /drive-renewal), split for highlighting. Prefix matches rank first.
export function filterCommands(commands, typedText) {
    const query = (typedText || '').trim().split(/\s/)[0].replace(/^\//, '').toLowerCase();
    const matches = [];
    (commands || []).forEach((command) => {
        const name = command.command.replace(/^\//, '');
        const index = query ? name.toLowerCase().indexOf(query) : 0;
        if (index < 0) return;
        matches.push({
            ...command,
            key: command.id,
            before: '/' + name.slice(0, index),
            match: name.slice(index, index + query.length),
            after: name.slice(index + query.length),
            rank: index === 0 ? 0 : 1
        });
    });
    return matches.sort((a, b) => a.rank - b.rank);
}

// The new-conversation screen's three suggestions - record-specific commands first.
export function getSuggestedCommands(commands, max = 3) {
    const list = commands || [];
    const specific = list.filter((command) => command.isRecordSpecific);
    const general = list.filter((command) => !command.isRecordSpecific);
    return [...specific, ...general].slice(0, max);
}

// True while the composer holds only a command being typed ("/ri"), which is when the menu shows.
export function isTypingCommand(text) {
    return /^\/[A-Za-z0-9_-]*$/.test(text || '');
}

const escapeHtml = (text) =>
    text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');

const renderInline = (text) =>
    escapeHtml(text)
        .replace(/`([^`]+)`/g, '<code>$1</code>')
        .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
        .replace(/(^|[^*])\*([^*\s][^*]*)\*/g, '$1<em>$2</em>')
        .replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g, '<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>');

// Minimal, escape-first markdown for AI replies (paragraphs, **bold**, *italic*, `code`, lists, headings, links). The output also passes through lightning-formatted-rich-text's sanitiser.
export function markdownToHtml(markdown) {
    if (!markdown) return '';
    const lines = markdown.replace(/\r\n/g, '\n').split('\n');
    const html = [];
    let listType = null;
    let paragraph = [];

    const flushParagraph = () => {
        if (paragraph.length) html.push(`<p>${paragraph.map(renderInline).join('<br>')}</p>`);
        paragraph = [];
    };
    const closeList = () => {
        if (listType) html.push(`</${listType}>`);
        listType = null;
    };

    lines.forEach((line) => {
        const bullet = line.match(/^\s*[-*•]\s+(.*)$/);
        const numbered = line.match(/^\s*\d+[.)]\s+(.*)$/);
        const heading = line.match(/^\s*#{1,6}\s+(.*)$/);

        if (bullet || numbered) {
            flushParagraph();
            const type = bullet ? 'ul' : 'ol';
            if (listType !== type) {
                closeList();
                html.push(`<${type}>`);
                listType = type;
            }
            html.push(`<li>${renderInline((bullet || numbered)[1])}</li>`);
        } else if (heading) {
            flushParagraph();
            closeList();
            html.push(`<p><strong>${renderInline(heading[1])}</strong></p>`);
        } else if (!line.trim()) {
            flushParagraph();
            closeList();
        } else {
            closeList();
            paragraph.push(line);
        }
    });
    flushParagraph();
    closeList();
    return html.join('');
}

// Readable message from an Apex/LDS error in any of its shapes.
export function reduceError(error) {
    if (!error) return 'Something went wrong.';
    if (typeof error === 'string') return error;
    if (Array.isArray(error.body)) return error.body.map((entry) => entry.message).join(', ');
    if (error.body && typeof error.body.message === 'string') return error.body.message;
    if (typeof error.message === 'string') return error.message;
    return 'Something went wrong.';
}

// Salesforce Ids arrive as 15 or 18 characters depending on the source - compare on the first 15.
export function isSameId(first, second) {
    if (!first || !second) return false;
    return String(first).slice(0, 15) === String(second).slice(0, 15);
}

export async function copyToClipboard(text) {
    try {
        if (navigator.clipboard && navigator.clipboard.writeText) {
            await navigator.clipboard.writeText(text);
            return true;
        }
    } catch (error) {
        // Clipboard API blocked - fall through to the legacy path.
    }
    try {
        const textArea = document.createElement('textarea');
        textArea.value = text;
        textArea.setAttribute('readonly', '');
        textArea.style.position = 'fixed';
        textArea.style.opacity = '0';
        document.body.appendChild(textArea);
        textArea.select();
        const copied = document.execCommand('copy');
        document.body.removeChild(textArea);
        return copied;
    } catch (error) {
        return false;
    }
}

// Saves text as a file through a temporary link.
export function downloadTextFile(fileName, text) {
    const link = document.createElement('a');
    link.href = `data:text/plain;charset=utf-8,${encodeURIComponent(text)}`;
    link.download = fileName;
    link.style.display = 'none';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
}

// "AI Conversation - 000123" -> "AI-Conversation-000123.txt".
export function toTranscriptFileName(conversationName) {
    return `${(conversationName || 'AI-Conversation').replace(/[^A-Za-z0-9]+/g, '-').replace(/^-|-$/g, '')}.txt`;
}

let localIdCounter = 0;
export function nextLocalId(prefix = 'local') {
    localIdCounter += 1;
    return `${prefix}-${Date.now()}-${localIdCounter}`;
}