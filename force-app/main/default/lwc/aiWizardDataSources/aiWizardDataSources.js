import { LightningElement, api } from 'lwc';
import getLibrarySources from '@salesforce/apex/AIConsoleController.getLibrarySources';
import assignDataSources from '@salesforce/apex/AIConsoleController.assignDataSources';
import setDataSourceAssignmentActive from '@salesforce/apex/AIConsoleController.setDataSourceAssignmentActive';
import removeDataSource from '@salesforce/apex/AIConsoleController.removeDataSource';
import goToWizardStep from '@salesforce/apex/AIConsoleController.goToWizardStep';
import AiDataSourceModal from 'c/aiDataSourceModal';
import { TABS, SECTIONS, VIEWS, navigate, reduceError, toast, debounce } from 'c/aiConsoleUtils';

/*
Wizard step 3 - Data Sources. Assignments save as they're made (Add selected, the Active switch,
Remove); the Library table lists what isn't assigned yet. A bound source whose Target Object isn't
the agent's object is flagged - it will never run for this agent.
*/
export default class AiWizardDataSources extends LightningElement {
    @api state;

    library = [];
    selectedIds = new Set();
    searchText = '';
    onlyThisObject = true;
    isLoadingLibrary = true;
    busy = false;

    searchLater = debounce(() => this.loadLibrary(), 300);

    connectedCallback() {
        this.loadLibrary();
    }

    @api
    async save(nextStep) {
        if (nextStep === null || nextStep === undefined) return this.state;
        return goToWizardStep({ agentId: this.state.agentId, nextStep });
    }

    async loadLibrary() {
        this.isLoadingLibrary = true;
        try {
            this.library = await getLibrarySources({ agentId: this.state.agentId, searchText: this.searchText, onlyThisObject: this.onlyThisObject });
            this.selectedIds = new Set([...this.selectedIds].filter((id) => this.library.some((source) => source.id === id)));
        } catch (error) {
            toast(this, 'Couldn’t load the Library', reduceError(error), 'error');
        } finally {
            this.isLoadingLibrary = false;
        }
    }

    get objectType() {
        return this.state.basics ? this.state.basics.objectType : '';
    }

    get assignedTitle() {
        return `Assigned to this agent (${this.state.dataSources.length})`;
    }

    get noneAssigned() {
        return this.state.dataSources.length === 0;
    }

    get assignedRows() {
        return this.state.dataSources.map((source) => ({
            ...source,
            rowClass: source.isMismatch ? 'row_warning' : '',
            targetClass: source.isMismatch ? 'aic-td aic-bold' : 'aic-td',
            mismatchText: `Bound to ${source.targetObject}. This agent runs on ${this.objectType}, so this source will never run.`,
            activeChecked: String(source.isActive),
            switchLabel: `${source.name} active`
        }));
    }

    get objectFilterLabel() {
        return `Runs on ${this.objectType || 'this object'} (bound or unbound)`;
    }

    get showAll() {
        return !this.onlyThisObject;
    }

    get libraryRows() {
        return this.library.map((source) => {
            const selected = this.selectedIds.has(source.id);
            return {
                ...source,
                selected,
                rowClass: selected ? 'row_selected' : '',
                selectLabel: `Select ${source.name}`,
                usedByLabel: `${source.usedBy} ${source.usedBy === 1 ? 'agent' : 'agents'}`
            };
        });
    }

    get libraryEmpty() {
        return this.library.length === 0;
    }

    get allSelected() {
        return this.library.length > 0 && this.selectedIds.size === this.library.length;
    }

    get addLabel() {
        return this.selectedIds.size ? `Add selected (${this.selectedIds.size})` : 'Add selected';
    }

    get addDisabled() {
        return this.selectedIds.size === 0 || this.busy;
    }

    handleSearch(event) {
        this.searchText = event.target.value;
        this.searchLater();
    }

    handleShow(event) {
        this.onlyThisObject = event.target.value === 'object';
        this.loadLibrary();
    }

    handleSelectRow(event) {
        const next = new Set(this.selectedIds);
        if (event.target.checked) next.add(event.target.dataset.id);
        else next.delete(event.target.dataset.id);
        this.selectedIds = next;
    }

    handleSelectAll(event) {
        this.selectedIds = event.target.checked ? new Set(this.library.map((source) => source.id)) : new Set();
    }

    handleOpenSource(event) {
        event.preventDefault();
        navigate(this, { tab: TABS.LIBRARY, section: SECTIONS.LIBRARY_DATA_SOURCES, view: VIEWS.RECORD, recordId: event.currentTarget.dataset.id });
    }

    async handleAdd() {
        const ids = [...this.selectedIds];
        await this.run(() => assignDataSources({ agentId: this.state.agentId, dataSourceIds: ids }), `${ids.length} ${ids.length === 1 ? 'data source' : 'data sources'} added`);
        this.selectedIds = new Set();
        this.loadLibrary();
    }

    async handleToggle(event) {
        const isActive = event.currentTarget.dataset.active !== 'true';
        await this.run(() => setDataSourceAssignmentActive({ agentId: this.state.agentId, linkId: event.currentTarget.dataset.id, isActive }));
    }

    async handleRemove(event) {
        await this.run(() => removeDataSource({ agentId: this.state.agentId, linkId: event.currentTarget.dataset.id }), 'Data source removed');
        this.loadLibrary();
    }

    async handleNewSource() {
        const result = await AiDataSourceModal.open({
            size: 'medium',
            label: 'New Data Source',
            agentId: this.state.agentId,
            agentName: this.state.agentName,
            agentObject: this.objectType
        });
        if (!result) return;
        // "Save & assign" linked it already; a plain Save leaves it in the Library table.
        await this.run(() => goToWizardStep({ agentId: this.state.agentId, nextStep: null }));
        this.loadLibrary();
    }

    async run(call, successTitle) {
        this.busy = true;
        try {
            const state = await call();
            if (successTitle) toast(this, successTitle, this.state.agentName);
            this.dispatchEvent(new CustomEvent('statechange', { detail: { state } }));
        } catch (error) {
            toast(this, 'Couldn’t save', reduceError(error), 'error');
        } finally {
            this.busy = false;
        }
    }
}
