import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import getWorkflowAction from '@salesforce/apex/AIConsoleController.getWorkflowAction';
import getObjectOptions from '@salesforce/apex/AIConsoleController.getObjectOptions';
import saveWorkflowAction from '@salesforce/apex/AIConsoleController.saveWorkflowAction';
import { reduceError, toDeveloperName, toast } from 'c/aiConsoleUtils';

/*
New / Edit Workflow Action (AIWorkflowAction__c). Workflow Actions are suggestion-only: the AI can
suggest one in chat and it runs when the user clicks it, so write actions default to asking first.
Closes with { id } when saved.
*/
export default class AiWorkflowActionModal extends LightningModal {
    @api recordId;

    action = { actionType: 'Flow', executionType: 'Write', requiresConfirmation: true, isActive: true };
    objectOptions = [];
    developerNameTouched = false;
    isLoading = true;
    isSaving = false;
    error;

    schemaExample = '{ "subject": "string", "dueDate": "date" }';

    async connectedCallback() {
        try {
            const [objects, existing] = await Promise.all([getObjectOptions(), this.recordId ? getWorkflowAction({ actionId: this.recordId }) : Promise.resolve(null)]);
            this.objectOptions = objects || [];
            if (existing) {
                this.action = { ...existing };
                this.developerNameTouched = true;
            }
        } catch (error) {
            this.error = reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    get typeCards() {
        return [
            { value: 'Flow', label: 'Flow', description: 'An autolaunched Flow' },
            { value: 'Apex', label: 'Apex', description: 'Implements IAIWorkflowActionExecutor' }
        ].map((card) => this.toCard(card, this.action.actionType));
    }

    get executionCards() {
        return [
            { value: 'Write', label: 'Write', description: 'Changes data' },
            { value: 'Read Only', label: 'Read Only', description: 'Only looks things up' }
        ].map((card) => this.toCard(card, this.action.executionType));
    }

    toCard(card, current) {
        const checked = card.value === current;
        return { ...card, checked, cardClass: checked ? 'aic-option aic-option_selected' : 'aic-option' };
    }

    get isFlow() {
        return this.action.actionType !== 'Apex';
    }

    get isWrite() {
        return this.action.executionType === 'Write';
    }

    get implementationLabel() {
        return this.isFlow ? 'Flow API Name' : 'Apex Class Name';
    }

    get implementationField() {
        return this.isFlow ? 'flowApiName' : 'apexClassName';
    }

    get implementationValue() {
        return this.isFlow ? this.action.flowApiName : this.action.apexClassName;
    }

    get implementationHelp() {
        return this.isFlow ? 'The Flow’s API name, e.g. Create_Follow_Up_Task.' : 'The class must implement IAIWorkflowActionExecutor.';
    }

    get objectChoices() {
        return [{ label: 'Any object', value: '' }].concat(this.objectOptions).map((option) => ({ ...option, selected: option.value === (this.action.targetObject || '') }));
    }

    get confirmChecked() {
        return String(!!this.action.requiresConfirmation);
    }

    handleName(event) {
        const name = event.target.value;
        this.action = { ...this.action, name, developerName: this.developerNameTouched ? this.action.developerName : toDeveloperName(name) };
    }

    handleDeveloperName(event) {
        this.developerNameTouched = true;
        this.action = { ...this.action, developerName: event.target.value };
    }

    handleInput(event) {
        this.action = { ...this.action, [event.target.dataset.field]: event.target.value };
    }

    handleConfirmToggle() {
        this.action = { ...this.action, requiresConfirmation: !this.action.requiresConfirmation };
    }

    handleActive(event) {
        this.action = { ...this.action, isActive: event.target.checked };
    }

    handleCancel() {
        this.close();
    }

    async handleSave() {
        this.isSaving = true;
        this.error = undefined;
        try {
            const id = await saveWorkflowAction({ actionJson: JSON.stringify(this.action) });
            toast(this, 'Workflow action saved', this.action.name);
            this.close({ id });
        } catch (error) {
            this.error = reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }
}