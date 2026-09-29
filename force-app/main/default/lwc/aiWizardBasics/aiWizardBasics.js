import { LightningElement, api } from 'lwc';
import saveBasics from '@salesforce/apex/AIConsoleController.saveBasics';
import { TABS, SECTIONS, navigate, toDeveloperName, parseNumber } from 'c/aiConsoleUtils';

/*
Wizard step 1 - Basics. Nothing is saved until the wizard moves on (save), so a new agent only gets a
record once its name, object and model are set. The chat preview shows the greeting and fallback
message as the chat window will.
*/
export default class AiWizardBasics extends LightningElement {
    basics = {};
    developerNameTouched = false;

    _state;
    @api
    get state() {
        return this._state;
    }
    set state(value) {
        this._state = value;
        if (value && value.basics) {
            this.basics = { ...value.basics };
            this.developerNameTouched = !!value.agentId;
        }
    }

    // Called by aiAgentWizard when moving on - saves Basics and returns the new WizardState.
    @api
    async save(nextStep) {
        return saveBasics({ agentId: this._state.agentId, basicsJson: JSON.stringify(this.basics), nextStep });
    }

    get objectChoices() {
        const options = [{ label: 'Select an object', value: '' }].concat(this._state.objectOptions || []);
        return options.map((option) => ({ ...option, selected: option.value === (this.basics.objectType || '') }));
    }

    get modelCards() {
        return (this._state.modelOptions || []).map((model) => {
            const checked = model.id === this.basics.modelId;
            return { ...model, checked, cardClass: checked ? 'aic-option aic-option_selected' : 'aic-option' };
        });
    }

    get noModels() {
        return !(this._state.modelOptions || []).length;
    }

    get iterationsHelp() {
        return `Leave blank to use the org default of ${this._state.orgDefaultIterations}. App Settings caps every agent at ${this._state.iterationsCap}.`;
    }

    get previewName() {
        return this.basics.name || 'New Agent';
    }

    get previewGreeting() {
        return this.basics.greeting || 'Hi, what do you need on this record?';
    }

    get previewFallback() {
        return this.basics.fallback || 'Something went wrong generating a response. Please try again.';
    }

    handleName(event) {
        const name = event.target.value;
        this.basics = { ...this.basics, name, developerName: this.developerNameTouched ? this.basics.developerName : toDeveloperName(name) };
    }

    handleDeveloperName(event) {
        this.developerNameTouched = true;
        this.basics = { ...this.basics, developerName: event.target.value };
    }

    handleInput(event) {
        this.basics = { ...this.basics, [event.target.dataset.field]: event.target.value };
    }

    handleModel(event) {
        this.basics = { ...this.basics, modelId: event.target.value };
    }

    handleIterations(event) {
        this.basics = { ...this.basics, maxIterations: parseNumber(event.target.value) };
    }

    handleManageModels(event) {
        event.preventDefault();
        navigate(this, { tab: TABS.LIBRARY, section: SECTIONS.LIBRARY_MODELS });
    }
}