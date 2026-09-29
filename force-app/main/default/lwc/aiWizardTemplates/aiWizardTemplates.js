import { LightningElement, api } from 'lwc';
import LightningConfirm from 'lightning/confirm';
import saveTemplate from '@salesforce/apex/AIConsoleController.saveTemplate';
import setTemplateActive from '@salesforce/apex/AIConsoleController.setTemplateActive';
import cloneTemplate from '@salesforce/apex/AIConsoleController.cloneTemplate';
import deleteTemplate from '@salesforce/apex/AIConsoleController.deleteTemplate';
import saveNoMatchBehavior from '@salesforce/apex/AIConsoleController.saveNoMatchBehavior';
import goToWizardStep from '@salesforce/apex/AIConsoleController.goToWizardStep';
import getObjectFields from '@salesforce/apex/AIConsoleController.getObjectFields';
import { reduceError, toast, toDeveloperName, parseNumber, formatNumber, clone, badgeClass } from 'c/aiConsoleUtils';

const NEW_KEY = 'new';
const PROMPT_LIMIT = 32768;
const NO_MATCH_CLOSEST = 'Closet Match'; // The org's picklist value is spelled this way.
const NO_MATCH_FALLBACK = 'Fallback Message';
const OPERATORS = [
    { value: 'equals', label: 'equals' },
    { value: 'notEquals', label: 'not equal to' },
    { value: 'contains', label: 'contains' },
    { value: 'greaterThan', label: 'greater than' },
    { value: 'lessThan', label: 'less than' }
];

/*
Wizard step 2 - Prompt Templates. The list on the left picks which template the editor shows; the
editor holds unsaved changes until Save (or until the wizard moves on, when save() saves them).
ActivationCriteria__c is stored as { logic, conditions[] } - see AIConsoleWizardService.
*/
export default class AiWizardTemplates extends LightningElement {
    editor;
    original;
    selectedKey;
    keywordDraft = '';
    fields = [];
    busy = false;
    developerNameTouched = false;

    _state;
    @api
    get state() {
        return this._state;
    }
    set state(value) {
        this._state = value;
        if (!value) return;
        const templates = value.templates || [];
        // Keep the open template open after a save; otherwise open the first one.
        // Unsaved edits to it survive a save made elsewhere on the step (the Active switch, No Match).
        const keep = templates.find((template) => template.id === this.selectedKey);
        if (keep) {
            if (!this.isDirty) this.openTemplate(keep);
        }
        else if (this.selectedKey !== NEW_KEY) {
            if (templates.length) this.openTemplate(templates[0]);
            else this.startNew();
        }
    }

    connectedCallback() {
        this.loadFields();
    }

    async loadFields() {
        const objectType = this._state && this._state.basics ? this._state.basics.objectType : null;
        if (!objectType) return;
        try {
            this.fields = (await getObjectFields({ objectApiName: objectType })).filter((field) => !field.apiName.includes('.') && field.isFilterable);
        } catch (error) {
            this.fields = [];
        }
    }

    // Saves the open template if it has changes, then records the wizard's move.
    @api
    async save(nextStep) {
        let state = this._state;
        if (this.isDirty) state = await this.saveEditor();
        if (nextStep === null || nextStep === undefined) return state;
        return goToWizardStep({ agentId: state.agentId, nextStep });
    }

    // =============================================================
    // Editor state
    // =============================================================

    openTemplate(template) {
        this.selectedKey = template.id;
        this.editor = clone(template);
        this.original = JSON.stringify(this.editor);
        this.developerNameTouched = true;
        this.keywordDraft = '';
    }

    startNew() {
        this.selectedKey = NEW_KEY;
        this.editor = { id: null, name: '', developerName: '', isActive: true, criteriaLogic: 'any', conditions: [], keywords: [] };
        this.original = JSON.stringify(this.editor);
        this.developerNameTouched = false;
        this.keywordDraft = '';
    }

    get isDirty() {
        return !!this.editor && JSON.stringify(this.editor) !== this.original;
    }

    async saveEditor() {
        const state = await saveTemplate({ agentId: this._state.agentId, templateJson: JSON.stringify(this.editor) });
        const saved = state.templates.find((template) => template.name === this.editor.name && (!this.editor.id || template.id === this.editor.id));
        this.selectedKey = saved ? saved.id : this.selectedKey;
        this.original = JSON.stringify(this.editor); // Saved - the fresh copy from the server replaces it.
        this.publish(state);
        return state;
    }

    publish(state) {
        this.dispatchEvent(new CustomEvent('statechange', { detail: { state } }));
    }

    // =============================================================
    // View
    // =============================================================

    get templates() {
        return (this._state && this._state.templates) || [];
    }

    get listTitle() {
        return `Templates (${this.templates.length})`;
    }

    get noTemplates() {
        return this.templates.length === 0 && this.selectedKey !== NEW_KEY;
    }

    get templateRows() {
        const rows = this.templates.map((template) => ({
            key: template.id,
            name: template.name,
            criteriaSummary: template.criteriaSummary,
            statusLabel: template.isActive ? 'Active' : 'Inactive',
            badgeClass: badgeClass(template.isActive ? 'ok' : ''),
            itemClass: template.id === this.selectedKey ? 'tpl tpl_selected' : 'tpl',
            current: template.id === this.selectedKey ? 'true' : 'false'
        }));
        if (this.selectedKey === NEW_KEY) {
            rows.push({ key: NEW_KEY, name: this.editor.name || 'New template', criteriaSummary: 'Not saved yet', statusLabel: 'New', badgeClass: badgeClass(''), itemClass: 'tpl tpl_selected', current: 'true' });
        }
        return rows;
    }

    get closestValue() {
        return NO_MATCH_CLOSEST;
    }

    get fallbackValue() {
        return NO_MATCH_FALLBACK;
    }

    get isClosest() {
        return this._state.noMatchBehavior !== NO_MATCH_FALLBACK;
    }

    get isFallback() {
        return this._state.noMatchBehavior === NO_MATCH_FALLBACK;
    }

    get editorTitle() {
        return this.editor.name || 'New template';
    }

    get activeLabel() {
        return this.editor.isActive ? 'Active' : 'Inactive';
    }

    get activeChecked() {
        return String(!!this.editor.isActive);
    }

    get isAny() {
        return this.editor.criteriaLogic !== 'all';
    }

    get isAll() {
        return this.editor.criteriaLogic === 'all';
    }

    get conditionRows() {
        return (this.editor.conditions || []).map((condition, index) => ({
            ...condition,
            index,
            key: `condition-${index}`,
            fieldChoices: this.fieldChoicesFor(condition.field),
            operatorChoices: OPERATORS.map((operator) => ({ ...operator, selected: operator.value === (condition.operator || 'equals') }))
        }));
    }

    fieldChoicesFor(selectedField) {
        const choices = this.fields.map((field) => ({ value: field.apiName, label: `${field.label} (${field.apiName})`, selected: field.apiName === selectedField }));
        // A saved condition on a field that's gone (or not loaded yet) still shows.
        if (selectedField && !choices.some((choice) => choice.value === selectedField)) choices.unshift({ value: selectedField, label: selectedField, selected: true });
        return choices;
    }

    get keywordPills() {
        return (this.editor.keywords || []).map((value) => ({ value, removeLabel: `Remove ${value}` }));
    }

    get promptCount() {
        return `${formatNumber((this.editor.prompt || '').length)} / ${formatNumber(PROMPT_LIMIT)}`;
    }

    // =============================================================
    // Handlers
    // =============================================================

    async handleSelect(event) {
        event.preventDefault();
        const key = event.currentTarget.dataset.id;
        if (key === this.selectedKey) return;
        if (this.isDirty && !(await this.confirmDiscard())) return;
        const template = this.templates.find((entry) => entry.id === key);
        if (template) this.openTemplate(template);
    }

    async handleNew() {
        if (this.isDirty && !(await this.confirmDiscard())) return;
        this.startNew();
    }

    async confirmDiscard() {
        return LightningConfirm.open({ message: 'Your changes to this template haven’t been saved.', label: 'Discard changes?', theme: 'warning' });
    }

    handleName(event) {
        const name = event.target.value;
        this.editor = { ...this.editor, name, developerName: this.developerNameTouched ? this.editor.developerName : toDeveloperName(name) };
    }

    handleDeveloperName(event) {
        this.developerNameTouched = true;
        this.editor = { ...this.editor, developerName: event.target.value };
    }

    handleInput(event) {
        this.editor = { ...this.editor, [event.target.dataset.field]: event.target.value };
    }

    handleLength(event) {
        this.editor = { ...this.editor, maxResponseLength: parseNumber(event.target.value) };
    }

    handleLogic(event) {
        this.editor = { ...this.editor, criteriaLogic: event.target.value };
    }

    handleAddCondition() {
        this.editor = { ...this.editor, conditions: [...(this.editor.conditions || []), { field: '', operator: 'equals', value: '' }] };
    }

    handleCondition(event) {
        const index = Number(event.target.dataset.index);
        const prop = event.target.dataset.prop;
        const conditions = this.editor.conditions.map((condition, position) => (position === index ? { ...condition, [prop]: event.target.value } : condition));
        this.editor = { ...this.editor, conditions };
    }

    handleRemoveCondition(event) {
        const index = Number(event.currentTarget.dataset.index);
        this.editor = { ...this.editor, conditions: this.editor.conditions.filter((condition, position) => position !== index) };
    }

    handleKeywordDraft(event) {
        this.keywordDraft = event.target.value;
    }

    handleKeywordKey(event) {
        if ((event.key === 'Enter' || event.key === ',') && this.keywordDraft.trim()) {
            event.preventDefault();
            const keyword = this.keywordDraft.trim().replace(/,/g, '');
            const keywords = this.editor.keywords || [];
            if (!keywords.includes(keyword)) this.editor = { ...this.editor, keywords: [...keywords, keyword] };
            this.keywordDraft = '';
            event.target.value = '';
        } else if (event.key === 'Backspace' && !this.keywordDraft && (this.editor.keywords || []).length) {
            this.editor = { ...this.editor, keywords: this.editor.keywords.slice(0, -1) };
        }
    }

    handleRemoveKeyword(event) {
        const value = event.currentTarget.dataset.value;
        this.editor = { ...this.editor, keywords: this.editor.keywords.filter((keyword) => keyword !== value) };
    }

    // An existing template's switch saves straight away; a new one's is saved with it.
    async handleActiveToggle() {
        const isActive = !this.editor.isActive;
        this.editor = { ...this.editor, isActive };
        if (!this.editor.id) return;

        await this.run(async () => {
            const state = await setTemplateActive({ agentId: this._state.agentId, templateId: this.editor.id, isActive });
            const originalCopy = JSON.parse(this.original);
            originalCopy.isActive = isActive;
            this.original = JSON.stringify(originalCopy);
            this.publish(state);
        });
    }

    async handleSaveTemplate() {
        await this.run(async () => {
            await this.saveEditor();
            toast(this, 'Template saved', this.editor.name);
        });
    }

    async handleClone() {
        await this.run(async () => {
            const state = await cloneTemplate({ agentId: this._state.agentId, templateId: this.editor.id });
            toast(this, 'Template cloned', `${this.editor.name} (copy) starts inactive.`);
            this.publish(state);
        });
    }

    async handleDelete() {
        const confirmed = await LightningConfirm.open({ message: `${this.editor.name} will be deleted.`, label: 'Delete this template?', theme: 'error' });
        if (!confirmed) return;
        await this.run(async () => {
            const state = await deleteTemplate({ agentId: this._state.agentId, templateId: this.editor.id });
            this.selectedKey = undefined;
            this.publish(state);
        });
    }

    async handleNoMatch(event) {
        const behavior = event.target.value;
        await this.run(async () => this.publish(await saveNoMatchBehavior({ agentId: this._state.agentId, behavior })));
    }

    async run(work) {
        this.busy = true;
        try {
            await work();
        } catch (error) {
            toast(this, 'Couldn’t save', reduceError(error), 'error');
        } finally {
            this.busy = false;
        }
    }
}