import { LightningElement, api } from 'lwc';
import LightningConfirm from 'lightning/confirm';
import saveRule from '@salesforce/apex/AIConsoleController.saveRule';
import setRuleActive from '@salesforce/apex/AIConsoleController.setRuleActive';
import deleteRule from '@salesforce/apex/AIConsoleController.deleteRule';
import goToWizardStep from '@salesforce/apex/AIConsoleController.goToWizardStep';
import { reduceError, toast, toDeveloperName, clone, badgeClass } from 'c/aiConsoleUtils';

const AI_EVALUATED = 'AI_Evaluated';
const DETERMINISTIC = 'Deterministic_Apex';
const VIOLATION_TYPES = [
    { value: 'Unauthorized_Workflow_Action', label: 'Unauthorized Workflow Action' },
    { value: 'Unauthorized_Data_Access', label: 'Unauthorized Data Access' },
    { value: 'AI_Flagged_Intent', label: 'AI Flagged Intent' },
    { value: 'PII_Masking_Failure', label: 'PII Masking Failure' },
    { value: 'Usage_Limit_Exceeded', label: 'Usage Limit Exceeded' },
    { value: 'Configuration_Violation', label: 'Configuration Violation' }
];

/*
Wizard step 5 - Guardrails: the agent's AIViolationRule__c rows. The table's Active switches save
straight away; the editor below saves with "Save rule" (or when the wizard moves on). The preview
shows what the chat window shows when a rule blocks a message.
*/
export default class AiWizardGuardrails extends LightningElement {
    editor;
    original;
    selectedId;
    busy = false;
    developerNameTouched = false;
    signalTouched = false;

    _state;
    @api
    get state() {
        return this._state;
    }
    set state(value) {
        this._state = value;
        if (!value) return;
        const rules = value.violationRules || [];
        const keep = rules.find((rule) => rule.id === this.selectedId);
        if (keep) {
            if (!this.isDirty) this.openRule(keep);
        } else if (this.selectedId !== 'new') {
            if (rules.length) this.openRule(rules[0]);
            else this.startNew();
        }
    }

    @api
    async save(nextStep) {
        let state = this._state;
        if (this.isDirty && this.hasEditorContent) state = await this.saveEditor();
        if (nextStep === null || nextStep === undefined) return state;
        return goToWizardStep({ agentId: state.agentId, nextStep });
    }

    openRule(rule) {
        this.selectedId = rule.id;
        this.editor = clone(rule);
        this.original = JSON.stringify(this.editor);
        this.developerNameTouched = true;
        this.signalTouched = true;
    }

    startNew() {
        this.selectedId = 'new';
        this.editor = { id: null, name: '', developerName: '', detectionMethod: AI_EVALUATED, violationType: VIOLATION_TYPES[0].value, blockRequest: false, isActive: true, instruction: '', signalTag: '' };
        this.original = JSON.stringify(this.editor);
        this.developerNameTouched = false;
        this.signalTouched = false;
    }

    get isDirty() {
        return !!this.editor && JSON.stringify(this.editor) !== this.original;
    }

    // A blank new rule left on screen isn't worth an error when moving on.
    get hasEditorContent() {
        return !!(this.editor && (this.editor.id || this.editor.name));
    }

    async saveEditor() {
        const state = await saveRule({ agentId: this._state.agentId, ruleJson: JSON.stringify(this.editor) });
        const saved = state.violationRules.find((rule) => rule.id === this.editor.id || (!this.editor.id && rule.name === this.editor.name.trim()));
        if (saved) this.selectedId = saved.id;
        this.original = JSON.stringify(this.editor);
        this.publish(state);
        return state;
    }

    publish(state) {
        this.dispatchEvent(new CustomEvent('statechange', { detail: { state } }));
    }

    // =============================================================
    // View
    // =============================================================

    get rules() {
        return (this._state && this._state.violationRules) || [];
    }

    get rulesTitle() {
        return `Violation rules (${this.rules.length})`;
    }

    get noRules() {
        return this.rules.length === 0;
    }

    get ruleRows() {
        return this.rules.map((rule) => {
            const isEditing = rule.id === this.selectedId;
            const classes = [];
            if (isEditing) classes.push('row_selected');
            if (!rule.isActive) classes.push('row_muted');
            return {
                ...rule,
                isEditing,
                rowClass: classes.join(' '),
                firesLabel: rule.blockRequest ? 'Blocks' : 'Logs only',
                firesClass: badgeClass(rule.blockRequest ? 'err' : ''),
                activeChecked: String(rule.isActive),
                switchLabel: `${rule.name} active`
            };
        });
    }

    get editorTitle() {
        return this.editor.name || 'New rule';
    }

    get detectionCards() {
        return [
            { value: DETERMINISTIC, label: 'Deterministic Apex', description: 'Exact checks on structured data. Predictable.' },
            { value: AI_EVALUATED, label: 'AI Evaluated', description: 'The model watches the conversation for it.' }
        ].map((card) => {
            const checked = card.value === this.editor.detectionMethod;
            return { ...card, checked, cardClass: checked ? 'aic-option aic-option_selected' : 'aic-option' };
        });
    }

    get isAiEvaluated() {
        return this.editor.detectionMethod === AI_EVALUATED;
    }

    get signalHelp() {
        return this.isAiEvaluated ? 'The exact tag the model outputs. Apex looks for this, never free text.' : 'The tag the Apex check reports when it fires.';
    }

    get violationTypeChoices() {
        return VIOLATION_TYPES.map((option) => ({ ...option, selected: option.value === this.editor.violationType }));
    }

    get blockChecked() {
        return String(!!this.editor.blockRequest);
    }

    get blockReason() {
        const what = (this.editor.name || 'this').toLowerCase();
        return `Your admin doesn’t allow ${what} in AI Assist. The message wasn’t sent to the AI model.`;
    }

    // =============================================================
    // Handlers
    // =============================================================

    async handleSelect(event) {
        event.preventDefault();
        const id = event.currentTarget.dataset.id;
        if (id === this.selectedId) return;
        if (this.isDirty && this.hasEditorContent && !(await this.confirmDiscard())) return;
        const rule = this.rules.find((entry) => entry.id === id);
        if (rule) this.openRule(rule);
    }

    async handleNew() {
        if (this.isDirty && this.hasEditorContent && !(await this.confirmDiscard())) return;
        this.startNew();
    }

    confirmDiscard() {
        return LightningConfirm.open({ message: 'Your changes to this rule haven’t been saved.', label: 'Discard changes?', theme: 'warning' });
    }

    handleName(event) {
        const name = event.target.value;
        const developerName = this.developerNameTouched ? this.editor.developerName : toDeveloperName(name);
        const signalTag = this.signalTouched ? this.editor.signalTag : `VIOLATION_${developerName}`.toUpperCase().slice(0, 40);
        this.editor = { ...this.editor, name, developerName, signalTag };
    }

    handleDeveloperName(event) {
        this.developerNameTouched = true;
        this.editor = { ...this.editor, developerName: event.target.value };
    }

    handleSignalTag(event) {
        this.signalTouched = true;
        this.editor = { ...this.editor, signalTag: event.target.value.toUpperCase() };
    }

    handleInput(event) {
        this.editor = { ...this.editor, [event.target.dataset.field]: event.target.value };
    }

    handleDetection(event) {
        this.editor = { ...this.editor, detectionMethod: event.target.value };
    }

    handleBlockToggle() {
        this.editor = { ...this.editor, blockRequest: !this.editor.blockRequest };
    }

    async handleSaveRule() {
        await this.run(async () => {
            await this.saveEditor();
            toast(this, 'Rule saved', this.editor.name);
        });
    }

    async handleDelete() {
        const confirmed = await LightningConfirm.open({ message: `${this.editor.name} will stop checking messages and be deleted.`, label: 'Delete this rule?', theme: 'error' });
        if (!confirmed) return;
        await this.run(async () => {
            const state = await deleteRule({ agentId: this._state.agentId, ruleId: this.editor.id });
            this.selectedId = undefined;
            this.original = JSON.stringify(this.editor);
            this.publish(state);
        });
    }

    async handleToggle(event) {
        const isActive = event.currentTarget.dataset.active !== 'true';
        const ruleId = event.currentTarget.dataset.id;
        await this.run(async () => {
            const state = await setRuleActive({ agentId: this._state.agentId, ruleId, isActive });
            if (ruleId === this.selectedId) {
                const originalCopy = JSON.parse(this.original);
                originalCopy.isActive = isActive;
                this.original = JSON.stringify(originalCopy);
                this.editor = { ...this.editor, isActive };
            }
            this.publish(state);
        });
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