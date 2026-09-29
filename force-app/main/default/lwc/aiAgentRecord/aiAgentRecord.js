import { LightningElement, api } from 'lwc';
import getAgentRecord from '@salesforce/apex/AIConsoleController.getAgentRecord';
import updateAgentField from '@salesforce/apex/AIConsoleController.updateAgentField';
import getAgentRelated from '@salesforce/apex/AIConsoleController.getAgentRelated';
import setAgentStatus from '@salesforce/apex/AIConsoleController.setAgentStatus';
import { TABS, SECTIONS, navigate, openWizard, refreshNav, reduceError, toast, badgeClass, relativeTime } from 'c/aiConsoleUtils';

const TAB_DEFS = [
    { key: 'overview', label: 'Overview' },
    { key: 'templates', label: 'Prompt Templates', step: 2 },
    { key: 'dataSources', label: 'Data Sources', step: 3 },
    { key: 'workflowActions', label: 'Workflow Actions', step: 4 },
    { key: 'guardrails', label: 'Guardrails', step: 5 },
    { key: 'conversations', label: 'Conversations' },
    { key: 'violations', label: 'Violations' }
];

/*
One agent's record page inside the Agents tab. Details edit in place (the pencil beside each field);
everything else about the agent is changed in the wizard ("Open in wizard", "Manage"). The related
tabs load on demand through AIConsoleAgentService.getAgentRelated.
*/
export default class AiAgentRecord extends LightningElement {
    agent;
    error;
    activeTab = 'overview';
    related;
    isLoadingRelated = false;
    editingKey;
    draftValue;
    isSaving = false;

    _agentId;
    @api
    get agentId() {
        return this._agentId;
    }
    set agentId(value) {
        if (value === this._agentId) return;
        this._agentId = value;
        this.activeTab = 'overview';
        this.load();
    }

    async load() {
        if (!this._agentId) return;
        try {
            this.agent = await getAgentRecord({ agentId: this._agentId });
            this.error = undefined;
        } catch (error) {
            this.error = reduceError(error);
        }
    }

    // =============================================================
    // View
    // =============================================================

    get statusClass() {
        return badgeClass(this.agent.statusVariant);
    }

    get setupBadge() {
        return this.agent.isSetupComplete ? 'Setup complete' : `Setup · step ${this.agent.setupStep} of 7`;
    }

    get canActivate() {
        return !this.agent.isActive || this.agent.isTestMode;
    }

    get objectType() {
        return this.agent.objectType || '—';
    }

    get lastEditedLabel() {
        return relativeTime(this.agent.setupLastEdited);
    }

    get tabs() {
        return TAB_DEFS.map((tab) => {
            const count = this.agent.counts ? this.agent.counts[tab.key] : undefined;
            const isActive = tab.key === this.activeTab;
            return {
                ...tab,
                label: count === undefined ? tab.label : `${tab.label} (${count})`,
                itemClass: isActive ? 'slds-tabs_default__item slds-is-active' : 'slds-tabs_default__item',
                selected: String(isActive),
                tabindex: isActive ? '0' : '-1'
            };
        });
    }

    get isOverview() {
        return this.activeTab === 'overview';
    }

    get activeTabDef() {
        return TAB_DEFS.find((tab) => tab.key === this.activeTab);
    }

    get activeTabLabel() {
        return this.tabs.find((tab) => tab.key === this.activeTab).label;
    }

    get activeTabStep() {
        return this.activeTabDef.step;
    }

    get detailFields() {
        return this.agent.details.map((field) => ({
            ...field,
            wrapperClass: field.fullWidth ? 'field field_full' : 'field',
            isEditing: field.key === this.editingKey,
            isTextarea: field.editor === 'textarea',
            isSelect: field.editor === 'select',
            editLabel: `Edit ${field.label}`,
            choices: (field.options || []).map((option) => ({ ...option, selected: option.value === this.draftValue }))
        }));
    }

    get dataSourcesTitle() {
        return `Data Sources (${this.agent.counts.dataSources})`;
    }

    get guardrailsTitle() {
        return `Guardrails (${this.agent.counts.guardrails})`;
    }

    get dataSourceRows() {
        return this.agent.dataSources.map((line) => ({ ...line, rowClass: line.warning ? 'line line_warning' : 'line' }));
    }

    get guardrailRows() {
        return this.agent.guardrails.map((line) => ({ ...line, badgeClass: badgeClass(line.badgeVariant) }));
    }

    get noDataSources() {
        return this.agent.dataSources.length === 0;
    }

    get noGuardrails() {
        return this.agent.guardrails.length === 0;
    }

    // =============================================================
    // Handlers
    // =============================================================

    async handleTab(event) {
        event.preventDefault();
        this.activeTab = event.currentTarget.dataset.key;
        this.related = undefined;
        if (this.isOverview) return;

        this.isLoadingRelated = true;
        try {
            this.related = await getAgentRelated({ agentId: this._agentId, relatedKey: this.activeTab });
        } catch (error) {
            toast(this, 'Couldn’t load', reduceError(error), 'error');
        } finally {
            this.isLoadingRelated = false;
        }
    }

    handleEdit(event) {
        const key = event.currentTarget.dataset.key;
        const field = this.agent.details.find((entry) => entry.key === key);
        this.editingKey = key;
        this.draftValue = field.value;
    }

    handleDraft(event) {
        this.draftValue = event.target.value;
    }

    handleCancelEdit() {
        this.editingKey = undefined;
    }

    async handleSaveEdit() {
        this.isSaving = true;
        try {
            this.agent = await updateAgentField({ agentId: this._agentId, fieldKey: this.editingKey, value: this.draftValue });
            this.editingKey = undefined;
            toast(this, 'Saved', this.agent.name);
        } catch (error) {
            toast(this, 'Couldn’t save', reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleBackToList(event) {
        event.preventDefault();
        navigate(this, {});
    }

    handleOpenWizard() {
        openWizard(this, this._agentId, 1);
    }

    handleManage(event) {
        event.preventDefault();
        openWizard(this, this._agentId, Number(event.currentTarget.dataset.step));
    }

    handleManageActive() {
        openWizard(this, this._agentId, this.activeTabStep);
    }

    handleClone() {
        this.dispatchEvent(new CustomEvent('clone', { detail: { agentId: this._agentId } }));
    }

    handleOpenModels(event) {
        event.preventDefault();
        navigate(this, { tab: TABS.LIBRARY, section: SECTIONS.LIBRARY_MODELS });
    }

    handleOpenOwner(event) {
        event.preventDefault();
        navigate(this, { tab: TABS.RECORD, recordId: this.agent.ownerId });
    }

    handleActivate() {
        this.changeStatus('activate', 'Agent activated for everyone');
    }

    handleDeactivate() {
        this.changeStatus('deactivate', 'Agent deactivated');
    }

    async changeStatus(mode, title) {
        this.isSaving = true;
        try {
            await setAgentStatus({ agentId: this._agentId, mode });
            toast(this, title, this.agent.name);
            await this.load();
            refreshNav(this);
        } catch (error) {
            toast(this, 'Couldn’t save', reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }
}