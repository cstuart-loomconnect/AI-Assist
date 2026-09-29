import { LightningElement, api } from 'lwc';
import getDataSource from '@salesforce/apex/AIConsoleController.getDataSource';
import setDataSourceActive from '@salesforce/apex/AIConsoleController.setDataSourceActive';
import AiDataSourceModal from 'c/aiDataSourceModal';
import { TABS, SECTIONS, VIEWS, navigate, reduceError, toast, badgeClass } from 'c/aiConsoleUtils';

/*
The panel beside Library › Data Sources: what the AI reads about the source, its query, which agents
use it and how it's been doing. Fires changed after an edit or (de)activation so the list refreshes.
*/
export default class AiDataSourceDetail extends LightningElement {
    source;
    error;
    isSaving = false;

    _recordId;
    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        if (value === this._recordId) return;
        this._recordId = value;
        this.load();
    }

    async load() {
        if (!this._recordId) return;
        this.source = undefined;
        try {
            this.source = await getDataSource({ dataSourceId: this._recordId });
            this.error = undefined;
        } catch (error) {
            this.error = reduceError(error);
        }
    }

    get isSoql() {
        return this.source.sourceType !== 'Apex';
    }

    get bindingLabel() {
        return this.source.bindingType === 'Bound' ? `Bound · ${this.source.targetObject}` : `${this.source.bindingType || 'Unbound'} · ${this.source.targetObject}`;
    }

    get statusLabel() {
        return this.source.isActive ? 'Active' : 'Inactive';
    }

    get statusClass() {
        return badgeClass(this.source.isActive ? 'ok' : '');
    }

    get toggleLabel() {
        return this.source.isActive ? 'Deactivate' : 'Activate';
    }

    get hasUsedBy() {
        return this.source.usedBy && this.source.usedBy.length > 0;
    }

    handleOpenAgent(event) {
        event.preventDefault();
        navigate(this, { tab: TABS.AGENTS, section: SECTIONS.AGENTS_ALL, view: VIEWS.RECORD, recordId: event.currentTarget.dataset.id });
    }

    // Test runs from the same modal - its "Test it" panel sits under the query.
    async handleEdit() {
        await this.openModal();
    }

    async handleTest() {
        await this.openModal();
    }

    async openModal() {
        const saved = await AiDataSourceModal.open({ size: 'medium', label: 'Edit Data Source', recordId: this._recordId });
        if (saved && saved.id) {
            await this.load();
            this.dispatchEvent(new CustomEvent('changed'));
        }
    }

    async handleToggle() {
        this.isSaving = true;
        try {
            await setDataSourceActive({ dataSourceId: this._recordId, isActive: !this.source.isActive });
            toast(this, this.source.isActive ? 'Data source deactivated' : 'Data source activated', this.source.name);
            await this.load();
            this.dispatchEvent(new CustomEvent('changed'));
        } catch (error) {
            toast(this, 'Couldn’t save', reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }
}