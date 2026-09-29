import { LightningElement, api } from 'lwc';
import LightningConfirm from 'lightning/confirm';
import getAgentList from '@salesforce/apex/AIConsoleController.getAgentList';
import setAgentStatus from '@salesforce/apex/AIConsoleController.setAgentStatus';
import deleteAgent from '@salesforce/apex/AIConsoleController.deleteAgent';
import AiAgentNewModal from 'c/aiAgentNewModal';
import { VIEWS, navigate, openWizard, refreshNav, reduceError, toast, badgeClass, formatNumber, relativeTime, debounce } from 'c/aiConsoleUtils';

const STATUS_FILTERS = [
    { value: 'all', label: 'All statuses' },
    { value: 'Active', label: 'Active' },
    { value: 'Test mode', label: 'Test mode' },
    { value: 'Inactive', label: 'Inactive' }
];

/*
The AI Agents tab's Sub Navigation sections (All Agents, Drafts, In test mode) - one component, the
section's Filter Criteria decides which agents it lists. It also routes the tab's other views:
c__view=record opens aiAgentRecord and c__view=new opens the New Agent modal over the list. The
wizard has its own tab (AI Agent Wizard); an old c__view=wizard link is sent there.
*/
export default class AiAgentList extends LightningElement {
    @api section;

    list = { rows: [], views: [] };
    searchText = '';
    statusFilter = 'all';
    isLoading = true;
    error;
    loadedAt;
    isModalOpen = false;

    searchLater = debounce(() => this.load(), 300);

    _pageState = {};
    @api
    get pageState() {
        return this._pageState;
    }
    set pageState(value) {
        const previousView = this._pageState ? this._pageState.view : null;
        this._pageState = value || {};

        if (this._pageState.view === VIEWS.WIZARD) openWizard(this, this._pageState.recordId, this._pageState.step, true);
        if (this._pageState.view === VIEWS.NEW) this.openNewAgent(null);
        // Back on the list after the wizard or a record page - agents may have changed.
        if (previousView && !this._pageState.view && this.loadedAt) this.load();
    }

    connectedCallback() {
        if (this._pageState.view === VIEWS.WIZARD) openWizard(this, this._pageState.recordId, this._pageState.step, true);
        this.load();
    }

    async load() {
        this.isLoading = !this.loadedAt;
        try {
            this.list = await getAgentList({ sectionName: this.section.developerName, searchText: this.searchText });
            this.loadedAt = Date.now();
            this.error = undefined;
        } catch (error) {
            this.error = reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // =============================================================
    // Views
    // =============================================================

    get isRecord() {
        return this._pageState.view === VIEWS.RECORD && !!this._pageState.recordId;
    }

    get pageRecordId() {
        return this._pageState.recordId;
    }

    get title() {
        return this.list.title || this.section.label;
    }

    get hasViews() {
        return this.list.views && this.list.views.length > 1;
    }

    get viewOptions() {
        return (this.list.views || []).map((view) => ({ ...view, checked: view.value === this.section.developerName }));
    }

    get statusOptions() {
        return STATUS_FILTERS.map((option) => ({ ...option, checked: option.value === this.statusFilter }));
    }

    get filteredRows() {
        return this.list.rows.filter((row) => this.statusFilter === 'all' || row.statusLabel === this.statusFilter);
    }

    get listInfo() {
        const count = this.filteredRows.length;
        return `${count} ${count === 1 ? 'item' : 'items'} · Sorted by Last Edited · Updated ${this.updatedLabel}`;
    }

    get updatedLabel() {
        if (!this.loadedAt) return 'just now';
        const minutes = Math.floor((Date.now() - this.loadedAt) / 60000);
        return minutes < 1 ? 'a few seconds ago' : `${minutes} min ago`;
    }

    get isEmpty() {
        return this.filteredRows.length === 0;
    }

    get rows() {
        return this.filteredRows.map((row) => ({
            ...row,
            modelLabel: row.modelName || '—',
            statusClass: badgeClass(row.statusVariant),
            conversationsLabel: formatNumber(row.conversations30Days),
            lastEditedLabel: relativeTime(row.lastEdited),
            canActivate: !row.isActive || row.isTestMode,
            menuLabel: `Actions for ${row.name}`
        }));
    }

    // =============================================================
    // Handlers
    // =============================================================

    handleView(event) {
        navigate(this, { section: event.detail.value });
    }

    handleSearch(event) {
        this.searchText = event.target.value;
        this.searchLater();
    }

    handleRefresh() {
        this.load();
        refreshNav(this);
    }

    handleStatusFilter(event) {
        this.statusFilter = event.detail.value;
    }

    handleOpen(event) {
        event.preventDefault();
        navigate(this, { section: this.section.developerName, view: VIEWS.RECORD, recordId: event.currentTarget.dataset.id });
    }

    handleResume(event) {
        event.preventDefault();
        openWizard(this, event.currentTarget.dataset.id, Number(event.currentTarget.dataset.step));
    }

    handleNewAgent() {
        this.openNewAgent(null);
    }

    handleCloneFromRecord(event) {
        this.openNewAgent(event.detail.agentId);
    }

    async handleRowAction(event) {
        const agentId = event.target.dataset.id;
        const action = event.detail.value;
        const agent = this.list.rows.find((row) => row.id === agentId);

        if (action === 'wizard') {
            openWizard(this, agentId, 1);
            return;
        }
        if (action === 'clone') {
            this.openNewAgent(agentId);
            return;
        }
        if (action === 'delete') {
            const confirmed = await LightningConfirm.open({ message: `${agent.name} and its prompt templates, assignments and violation rules will be deleted. This can’t be undone.`, label: `Delete ${agent.name}?`, theme: 'error' });
            if (!confirmed) return;
            await this.run(() => deleteAgent({ agentId }), 'Agent deleted', agent.name);
            return;
        }

        const titles = { activate: 'Agent activated for everyone', deactivate: 'Agent deactivated' };
        await this.run(() => setAgentStatus({ agentId, mode: action }), titles[action], agent.name);
    }

    async run(call, successTitle, name) {
        try {
            await call();
            toast(this, successTitle, name);
            await this.load();
            refreshNav(this);
        } catch (error) {
            toast(this, 'Couldn’t save', reduceError(error), 'error');
        }
    }

    // The modal decides how to start; this turns its choice into a navigation.
    async openNewAgent(cloneSourceId) {
        if (this.isModalOpen) return;
        this.isModalOpen = true;

        const result = await AiAgentNewModal.open({ size: 'medium', label: 'New Agent', cloneSourceId });
        this.isModalOpen = false;

        if (!result) {
            if (this._pageState.view === VIEWS.NEW) navigate(this, { section: this.section.developerName, replace: true });
            return;
        }

        refreshNav(this);
        // Opened from a c__view=new link: replace that history entry, so Back doesn't reopen the modal.
        openWizard(this, result.agentId, result.step || 1, this._pageState.view === VIEWS.NEW);
    }
}
