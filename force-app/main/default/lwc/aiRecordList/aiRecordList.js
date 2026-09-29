import { LightningElement, api } from 'lwc';
import getRecordList from '@salesforce/apex/AIConsoleController.getRecordList';
import AiModelConfigModal from 'c/aiModelConfigModal';
import AiDataSourceModal from 'c/aiDataSourceModal';
import AiWorkflowActionModal from 'c/aiWorkflowActionModal';
import { VIEWS, navigate, refreshNav, reduceError, downloadCsv, toast } from 'c/aiConsoleUtils';

const RELATED_LIST = 'Related List';
const TILE_COLOURS = {
    agent: '#4B37AE',
    model: '#06A59A',
    datasource: '#3A49DA',
    action: '#032D60',
    conversation: '#0B827C',
    violation: '#BA0517',
    log: '#444444'
};
const PANEL_WIDTH = {
    aiDataSourceDetail: 'panel panel_440',
    aiWorkflowActionDetail: 'panel panel_440',
    aiViolationDetail: 'panel panel_400',
    aiPlatformLogDetail: 'panel panel_460'
};

/*
The console's one generic list. Everything it shows - header, filters, columns, rows, which detail
panel sits beside it and what the header buttons do - comes from AIConsoleListService for the
section's Related Object API Name, so this component only lays it out:

- A Related List section (Home) is a compact card with "View all".
- A Sub Navigation section is a full list page. A row opens its detail panel beside the list, the
  record full page (rowView = record), or its edit modal (rowView = editModel).

The open row lives in the URL (c__view=record&c__recordId=...), so it can be linked to.
*/
export default class AiRecordList extends LightningElement {
    @api section;

    result = { columns: [], rows: [], filters: [] };
    rows = [];
    filterValues = {};
    error;
    isLoading = true;
    isLoadingMore = false;
    hasLoaded = false;

    _pageState = {};
    @api
    get pageState() {
        return this._pageState;
    }
    set pageState(value) {
        const previous = this._pageState || {};
        this._pageState = value || {};
        // Coming back from a record's full page refreshes the list - the record may have changed.
        const leftRecordPage = previous.view === VIEWS.RECORD && this._pageState.view !== VIEWS.RECORD && this.result.rowView === VIEWS.RECORD;
        if (this.hasLoaded && leftRecordPage) this.load();
    }

    connectedCallback() {
        this.load();
    }

    async load() {
        this.isLoading = true;
        try {
            const result = await getRecordList({ sectionName: this.section.developerName, filtersJson: JSON.stringify(this.filterValues), offset: 0 });
            this.result = result;
            this.rows = result.rows;
            this.captureFilterValues(result.filters);
            this.error = undefined;
        } catch (error) {
            this.error = reduceError(error);
        } finally {
            this.isLoading = false;
            this.hasLoaded = true;
        }
    }

    async handleLoadMore() {
        this.isLoadingMore = true;
        try {
            const result = await getRecordList({ sectionName: this.section.developerName, filtersJson: JSON.stringify(this.filterValues), offset: this.rows.length });
            this.rows = [...this.rows, ...result.rows];
            this.result = { ...this.result, hasMore: result.hasMore };
        } catch (error) {
            toast(this, 'Couldn’t load more', reduceError(error), 'error');
        } finally {
            this.isLoadingMore = false;
        }
    }

    captureFilterValues(filters) {
        const values = { ...this.filterValues };
        (filters || []).forEach((filter) => {
            if (values[filter.key] === undefined) values[filter.key] = filter.type === 'checkbox' ? filter.value === 'true' : filter.value;
        });
        this.filterValues = values;
    }

    // =============================================================
    // Layout
    // =============================================================

    get isRelatedList() {
        return this.section && this.section.sectionType === RELATED_LIST;
    }

    get isRecordPage() {
        return this.result.rowView === VIEWS.RECORD && this._pageState.view === VIEWS.RECORD && !!this._pageState.recordId;
    }

    get pageRecordId() {
        return this._pageState.recordId;
    }

    get cardTitle() {
        return this.section?.label || this.result.title;
    }

    get pageTitle() {
        return this.result.title || this.section?.label;
    }

    get tileStyle() {
        const colour = TILE_COLOURS[this.result.icon];
        return colour ? `background: ${colour}` : null;
    }

    get hasFilters() {
        return (this.result.filters && this.result.filters.length > 0) || !!this.result.countLabel;
    }

    get filterBarClass() {
        const onlyChips = (this.result.filters || []).every((filter) => filter.type === 'chips');
        return onlyChips ? 'filters filters_chips' : 'filters';
    }

    get filterViews() {
        return (this.result.filters || []).map((filter) => {
            const value = this.filterValues[filter.key];
            return {
                ...filter,
                isChips: filter.type === 'chips',
                isSelect: filter.type === 'select',
                isCheckbox: filter.type === 'checkbox',
                value,
                checked: value === true,
                variant: filter.labelHidden ? 'label-hidden' : 'standard',
                style: filter.width ? `width: ${filter.width}px` : '',
                chipOptions: (filter.options || []).map((option) => ({ ...option, pressed: String(option.value === value) }))
            };
        });
    }

    get showPanel() {
        return !!this.result.detailComponent && this.result.rowView !== VIEWS.RECORD && !!this.selectedId;
    }

    get panelClass() {
        return PANEL_WIDTH[this.result.detailComponent] || 'panel panel_440';
    }

    get isDataSourcePanel() {
        return this.result.detailComponent === 'aiDataSourceDetail';
    }

    get isWorkflowActionPanel() {
        return this.result.detailComponent === 'aiWorkflowActionDetail';
    }

    get isViolationPanel() {
        return this.result.detailComponent === 'aiViolationDetail';
    }

    get isLogPanel() {
        return this.result.detailComponent === 'aiPlatformLogDetail';
    }

    // The row in the URL, else the first row - a panel list always has something open.
    get selectedId() {
        if (!this.result.detailComponent || this.result.rowView === VIEWS.RECORD) return null;
        const requested = this._pageState.view === VIEWS.RECORD ? this._pageState.recordId : null;
        if (requested) return requested;
        return this.rows.length ? this.rows[0].id : null;
    }

    // =============================================================
    // Handlers
    // =============================================================

    handleChip(event) {
        this.filterValues = { ...this.filterValues, [event.currentTarget.dataset.key]: event.currentTarget.dataset.value };
        this.load();
    }

    handleSelect(event) {
        this.filterValues = { ...this.filterValues, [event.target.dataset.key]: event.detail.value };
        this.load();
    }

    handleCheckbox(event) {
        this.filterValues = { ...this.filterValues, [event.target.dataset.key]: event.target.checked };
        this.load();
    }

    handleRowOpen(event) {
        const recordId = event.detail.id;

        if (this.result.rowView === 'editModel') {
            this.openModelModal(recordId);
            return;
        }
        // A panel swap replaces the history entry; opening a full page adds one, so Back returns to the list.
        const opensPage = this.result.rowView === VIEWS.RECORD;
        navigate(this, { section: this.section.developerName, view: VIEWS.RECORD, recordId, replace: !opensPage });
    }

    handleBack() {
        navigate(this, { section: this.section.developerName });
    }

    handleViewAll(event) {
        event.preventDefault();
        navigate(this, this.result.viewAll);
    }

    handleBannerLink(event) {
        event.preventDefault();
        if (this.result.bannerTarget) navigate(this, this.result.bannerTarget);
    }

    handleDetailChanged() {
        this.load();
        refreshNav(this);
    }

    async handleAction(event) {
        const action = event.target.dataset.action;

        if (action === 'export') {
            this.exportRows();
            return;
        }

        let saved;
        if (action === 'newModel') saved = await this.openModelModal(null);
        if (action === 'newDataSource') saved = await AiDataSourceModal.open({ size: 'medium', label: 'New Data Source' });
        if (action === 'newWorkflowAction') saved = await AiWorkflowActionModal.open({ size: 'medium', label: 'New Workflow Action' });

        if (saved && saved.id && action !== 'newModel') {
            this.afterSave(saved.id);
        }
    }

    async openModelModal(recordId) {
        const saved = await AiModelConfigModal.open({ size: 'medium', label: recordId ? 'Edit Model Configuration' : 'New Model Configuration', recordId });
        if (saved && saved.id) this.afterSave(null);
        return saved;
    }

    async afterSave(recordId) {
        await this.load();
        refreshNav(this);
        if (recordId && this.result.detailComponent) navigate(this, { section: this.section.developerName, view: VIEWS.RECORD, recordId, replace: true });
    }

    exportRows() {
        const headers = this.result.columns.map((column) => column.label);
        const rows = this.rows.map((row) => this.result.columns.map((column) => {
            const cell = row.cells.find((entry) => entry.key === column.key);
            return cell ? cell.value : '';
        }));
        const stamp = new Date().toISOString().slice(0, 10);
        downloadCsv(`${(this.result.title || 'export').replace(/\s+/g, '_')}_${stamp}.csv`, headers, rows);
    }
}
