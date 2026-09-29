import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import getObjectOptions from '@salesforce/apex/AIConsoleController.getObjectOptions';
import addPiiObject from '@salesforce/apex/AIConsoleController.addPiiObject';
import { reduceError, toast } from 'c/aiConsoleUtils';

/*
Adds an object to the PII Registry and starts its first sync. Closes with the refreshed registry.
*/
export default class AiPiiAddObjectModal extends LightningModal {
    @api existing = [];

    options = [];
    objectApiName = '';
    isLoading = true;
    isSaving = false;
    error;

    async connectedCallback() {
        try {
            const taken = new Set(this.existing || []);
            this.options = (await getObjectOptions()).filter((option) => !taken.has(option.value));
        } catch (error) {
            this.error = reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    get choices() {
        return [{ label: 'Select an object', value: '' }].concat(this.options).map((option) => ({ ...option, selected: option.value === this.objectApiName }));
    }

    get isSaveDisabled() {
        return this.isSaving || !this.objectApiName;
    }

    handleObject(event) {
        this.objectApiName = event.target.value;
    }

    handleCancel() {
        this.close();
    }

    async handleSave() {
        this.isSaving = true;
        this.error = undefined;
        try {
            const registry = await addPiiObject({ objectApiName: this.objectApiName });
            toast(this, 'Object added', 'The first sync has started.');
            this.close(registry);
        } catch (error) {
            this.error = reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }
}