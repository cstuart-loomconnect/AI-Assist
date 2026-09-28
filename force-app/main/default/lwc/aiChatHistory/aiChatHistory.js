import { LightningElement, api } from 'lwc';
import { LABELS, groupConversations, getConversationStatus, formatHistoryDate, isSameId } from 'c/aiChatUtils';

// The user's past conversations - grouped by day, searchable by title, filtered to this record or all records. aiAssistChat loads the list (AIChatController.getConversationHistory) whenever the filter changes; search runs here over what's loaded.
export default class AiChatHistory extends LightningElement {
    @api conversations = [];
    @api isLoading = false;
    @api errorMessage;
    @api filter = 'record'; // 'record' | 'all'
    @api hasRecord = false;
    @api currentConversationId;
    @api newDisabled = false;

    labels = LABELS;
    searchTerm = '';

    get thisRecordPressed() {
        return this.filter === 'record' ? 'true' : 'false';
    }

    get allRecordsPressed() {
        return this.filter === 'all' ? 'true' : 'false';
    }

    get filteredConversations() {
        const term = this.searchTerm.trim().toLowerCase();
        const list = this.conversations || [];
        return term ? list.filter((conversation) => `${conversation.title} ${conversation.agentName || ''}`.toLowerCase().includes(term)) : list;
    }

    get groups() {
        return groupConversations(this.filteredConversations).map((group) => ({
            ...group,
            items: group.items.map((conversation) => {
                const isCurrent = isSameId(conversation.id, this.currentConversationId);
                const status = getConversationStatus(conversation);
                return {
                    ...conversation,
                    status,
                    showStatus: status && status.label !== 'Closed',
                    dateLabel: formatHistoryDate(conversation.lastActivity),
                    metaLabel: `${conversation.agentName || LABELS.appName} · ${conversation.messageCount} messages`,
                    className: isCurrent ? 'conversation conversation_current' : 'conversation',
                    titleClass: isCurrent ? 'conversation-title conversation-title_current slds-truncate' : 'conversation-title slds-truncate'
                };
            })
        }));
    }

    get hasGroups() {
        return this.groups.length > 0;
    }

    get emptyMessage() {
        return this.searchTerm.trim() ? LABELS.noSearchResults : LABELS.noConversations;
    }

    handleSearch(event) {
        this.searchTerm = event.target.value || '';
    }

    handleFilter(event) {
        const filter = event.currentTarget.dataset.filter;
        if (filter !== this.filter) this.dispatchEvent(new CustomEvent('filterchange', { detail: { filter } }));
    }

    handleOpen(event) {
        this.dispatchEvent(new CustomEvent('open', { detail: { conversationId: event.currentTarget.dataset.id } }));
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    handleNew() {
        this.dispatchEvent(new CustomEvent('newconversation'));
    }
}