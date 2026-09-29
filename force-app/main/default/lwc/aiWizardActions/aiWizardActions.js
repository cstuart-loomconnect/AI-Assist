import { LightningElement, api } from 'lwc';
import getLibraryActions from '@salesforce/apex/AIConsoleController.getLibraryActions';
import assignWorkflowActions from '@salesforce/apex/AIConsoleController.assignWorkflowActions';
import setWorkflowActionAssignmentActive from '@salesforce/apex/AIConsoleController.setWorkflowActionAssignmentActive';
import removeWorkflowAction from '@salesforce/apex/AIConsoleController.removeWorkflowAction';
import goToWizardStep from '@salesforce/apex/AIConsoleController.goToWizardStep';
import AiWorkflowActionModal from 'c/aiWorkflowActionModal';
import { TABS, SECTIONS, VIEWS, navigate, reduceError, toast, badgeClass } from 'c/aiConsoleUtils';

/*
Wizard step 4 - Workflow Actions (optional). Assignments save as they're made. Actions are edited in
the Library, since one action can serve many agents.
*/
export default class AiWizardActions extends LightningElement {
    @api state;

    library = [];
    selectedIds = new Set();
    isLoadingLibrary = true;
    busy = false;

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
            this.library = await getLibraryActions({ agentId: this.state.agentId });
            this.selectedIds = new Set([...this.selectedIds].filter((id) => this.library.some((action) => action.id === id)));
        } catch (error) {
            toast(this, 'Couldn’t load the Library', reduceError(error), 'error');
        } finally {
            this.isLoadingLibrary = false;
        }
    }

    get assignedTitle() {
        return `Assigned to this agent (${this.state.workflowActions.length})`;
    }

    get hasAssigned() {
        return this.state.workflowActions.length > 0;
    }

    get assignedTiles() {
        return this.state.workflowActions.map((action) => {
            const isFlow = action.actionType === 'Flow';
            const isWrite = action.executionType === 'Write';
            return {
                ...action,
                isWrite,
                icon: isFlow ? 'flow' : 'log',
                executionClass: badgeClass(isWrite ? 'write' : 'ro'),
                implementationLabel: isFlow ? 'Flow API Name' : 'Apex Class Name',
                implementationName: action.implementationName || '—',
                activeChecked: String(action.isActive),
                switchLabel: `${action.name} active`,
                message: action.requiresConfirmation && action.confirmationMessage ? `“${action.confirmationMessage}”` : action.description || 'No description yet.',
                messageClass: action.requiresConfirmation && action.confirmationMessage ? 'message' : 'message message_weak'
            };
        });
    }

    get libraryRows() {
        return this.library.map((action) => {
            const selected = this.selectedIds.has(action.id);
            const isWrite = action.executionType === 'Write';
            return {
                ...action,
                selected,
                rowClass: selected ? 'row_selected' : '',
                selectLabel: `Select ${action.name}`,
                executionClass: badgeClass(isWrite ? 'write' : 'ro'),
                targetLabel: action.targetObject || 'Any',
                runsWithoutAsking: isWrite && !action.requiresConfirmation,
                confirmationLabel: isWrite ? 'Asks first' : '—'
            };
        });
    }

    get libraryEmpty() {
        return this.library.length === 0;
    }

    get addLabel() {
        return this.selectedIds.size ? `Add selected (${this.selectedIds.size})` : 'Add selected';
    }

    get addDisabled() {
        return this.selectedIds.size === 0 || this.busy;
    }

    handleSelectRow(event) {
        const next = new Set(this.selectedIds);
        if (event.target.checked) next.add(event.target.dataset.id);
        else next.delete(event.target.dataset.id);
        this.selectedIds = next;
    }

    async handleAdd() {
        const ids = [...this.selectedIds];
        await this.run(() => assignWorkflowActions({ agentId: this.state.agentId, actionIds: ids }), `${ids.length} ${ids.length === 1 ? 'action' : 'actions'} added`);
        this.selectedIds = new Set();
        this.loadLibrary();
    }

    async handleToggle(event) {
        const isActive = event.currentTarget.dataset.active !== 'true';
        await this.run(() => setWorkflowActionAssignmentActive({ agentId: this.state.agentId, linkId: event.currentTarget.dataset.id, isActive }));
    }

    async handleRemove(event) {
        await this.run(() => removeWorkflowAction({ agentId: this.state.agentId, linkId: event.currentTarget.dataset.id }), 'Action removed');
        this.loadLibrary();
    }

    async handleNewAction() {
        const result = await AiWorkflowActionModal.open({ size: 'medium', label: 'New Workflow Action' });
        if (result) this.loadLibrary();
    }

    handleEditInLibrary(event) {
        navigate(this, { tab: TABS.LIBRARY, section: SECTIONS.LIBRARY_ACTIONS, view: VIEWS.RECORD, recordId: event.currentTarget.dataset.id });
    }

    handleOpenUiSettings(event) {
        event.preventDefault();
        navigate(this, { tab: TABS.SETTINGS, section: SECTIONS.SETTINGS_UI });
    }

    handleOpenUserSettings(event) {
        event.preventDefault();
        navigate(this, { tab: TABS.SETTINGS, section: SECTIONS.SETTINGS_USERS });
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
