import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import getNewAgentOptions from '@salesforce/apex/AIConsoleController.getNewAgentOptions';
import cloneAgent from '@salesforce/apex/AIConsoleController.cloneAgent';
import { reduceError, shortDate, toast } from 'c/aiConsoleUtils';

const STEP_COUNT = 7;

/*
New Agent: start from scratch, clone a finished agent (optionally with its templates, data source and
workflow action assignments and violation rules), or continue a draft. Closes with { agentId, step }
for the wizard to open at - no agentId means a brand-new agent, which isn't saved until Basics is.
*/
export default class AiAgentNewModal extends LightningModal {
    @api cloneSourceId;

    options = { cloneSources: [], drafts: [] };
    choice = 'scratch';
    sourceId;
    cloneName = '';
    copy = { copyTemplates: true, copyDataSources: true, copyWorkflowActions: true, copyViolationRules: true };
    isLoading = true;
    isWorking = false;
    error;

    async connectedCallback() {
        try {
            this.options = await getNewAgentOptions();
            const preset = this.options.cloneSources.find((source) => source.id === this.cloneSourceId);
            if (preset || this.cloneSourceId) {
                this.choice = 'clone';
                this.selectSource(preset ? preset.id : this.options.cloneSources[0] && this.options.cloneSources[0].id);
            } else if (this.options.cloneSources.length) {
                this.selectSource(this.options.cloneSources[0].id);
            }
        } catch (error) {
            this.error = reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    selectSource(sourceId) {
        const source = this.options.cloneSources.find((entry) => entry.id === sourceId);
        this.sourceId = sourceId;
        this.cloneName = source ? `${source.name} (copy)` : '';
    }

    get isScratch() {
        return this.choice === 'scratch';
    }

    get isClone() {
        return this.choice === 'clone';
    }

    get isDraft() {
        return this.choice === 'draft';
    }

    get scratchClass() {
        return this.isScratch ? 'choice choice_selected' : 'choice';
    }

    get cloneClass() {
        return this.isClone ? 'choice choice_stack choice_selected' : 'choice choice_stack';
    }

    get draftClass() {
        return this.isDraft ? 'choice choice_stack choice_selected' : 'choice choice_stack';
    }

    get hasCloneSources() {
        return this.options.cloneSources.length > 0;
    }

    get hasDrafts() {
        return this.options.drafts.length > 0;
    }

    get draftsNote() {
        const count = this.options.drafts.length;
        return `${count} ${count === 1 ? 'agent isn’t' : 'agents aren’t'} finished.`;
    }

    get sourceChoices() {
        return this.options.cloneSources.map((source) => ({ ...source, selected: source.id === this.sourceId }));
    }

    get selectedSource() {
        return this.options.cloneSources.find((source) => source.id === this.sourceId) || {};
    }

    get templatesLabel() {
        return this.countLabel(this.selectedSource.templates, 'prompt template', 'prompt templates');
    }

    get dataSourcesLabel() {
        return this.countLabel(this.selectedSource.dataSources, 'data source assignment', 'data source assignments');
    }

    get actionsLabel() {
        return this.countLabel(this.selectedSource.workflowActions, 'workflow action assignment', 'workflow action assignments');
    }

    get rulesLabel() {
        return this.countLabel(this.selectedSource.violationRules, 'violation rule', 'violation rules');
    }

    countLabel(count, singular, plural) {
        const value = count || 0;
        return `${value} ${value === 1 ? singular : plural}`;
    }

    get draftRows() {
        return this.options.drafts.map((draft) => ({ ...draft, detail: `Step ${draft.step} of ${STEP_COUNT} · ${shortDate(draft.lastEdited)}` }));
    }

    handleChoice(event) {
        this.choice = event.target.value;
    }

    handleSource(event) {
        this.selectSource(event.target.value);
    }

    handleCloneName(event) {
        this.cloneName = event.target.value;
    }

    handleCopy(event) {
        this.copy = { ...this.copy, [event.target.dataset.field]: event.target.checked };
    }

    handleResume(event) {
        event.preventDefault();
        this.close({ agentId: event.currentTarget.dataset.id, step: Number(event.currentTarget.dataset.step) });
    }

    handleCancel() {
        this.close();
    }

    async handleNext() {
        if (this.isScratch) {
            this.close({ agentId: null, step: 1 });
            return;
        }
        if (this.isDraft) {
            const draft = this.options.drafts[0];
            this.close({ agentId: draft.id, step: draft.step });
            return;
        }

        this.isWorking = true;
        this.error = undefined;
        try {
            const agentId = await cloneAgent({ requestJson: JSON.stringify({ sourceId: this.sourceId, name: this.cloneName, ...this.copy }) });
            toast(this, 'Agent cloned', this.cloneName);
            this.close({ agentId, step: 1 });
        } catch (error) {
            this.error = reduceError(error);
        } finally {
            this.isWorking = false;
        }
    }
}
