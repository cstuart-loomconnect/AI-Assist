import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import getDataSource from '@salesforce/apex/AIConsoleController.getDataSource';
import getObjectOptions from '@salesforce/apex/AIConsoleController.getObjectOptions';
import saveDataSource from '@salesforce/apex/AIConsoleController.saveDataSource';
import testDataSource from '@salesforce/apex/AIConsoleController.testDataSource';
import checkSoql from '@salesforce/apex/AIConsoleController.checkSoql';
import { reduceError, toDeveloperName, formatNumber, toast, debounce } from 'c/aiConsoleUtils';

const BOUND_SCHEMA = JSON.stringify({ type: 'object', properties: { recordId: { type: 'string' } }, required: ['recordId'] }, null, 2);

/*
New / Edit Data Source (AIDataSource__c). The SOQL template is written by hand (Write SOQL) or composed
in aiSoqlBuilder; either way it's checked against the org as it changes (AIConsoleSoqlBuilderService.checkSoql
runs it with LIMIT 0) and can be test-run read-only against a real record. Opened from the wizard it
can also assign the saved source to that agent ("Save & assign"). Closes with { id, assigned }.
*/
export default class AiDataSourceModal extends LightningModal {
    @api recordId;
    @api agentId;
    @api agentName;
    @api agentObject;

    source = { sourceType: 'SOQL', bindingType: 'Bound', isActive: true, inputSchema: BOUND_SCHEMA };
    objectOptions = [];
    mode = 'write';
    developerNameTouched = false;
    soqlCheck;
    testRecordId;
    testResult;
    isTesting = false;
    isLoading = true;
    isSaving = false;
    error;

    runCheckLater = debounce(() => this.runCheck(), 600);

    async connectedCallback() {
        try {
            const [objects, existing] = await Promise.all([getObjectOptions(), this.recordId ? getDataSource({ dataSourceId: this.recordId }) : Promise.resolve(null)]);
            this.objectOptions = objects || [];

            if (existing) {
                this.source = { ...existing };
                this.developerNameTouched = true;
            } else {
                this.source = { ...this.source, targetObject: this.agentObject || '' };
            }
            if (this.source.soqlTemplate) this.runCheck();
        } catch (error) {
            this.error = reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // =============================================================
    // View
    // =============================================================

    get tagline() {
        if (this.isBuilder) {
            const parts = [this.source.name, 'SOQL template', this.source.bindingType === 'Bound' ? `Bound to ${this.source.targetObject || '…'}` : 'Unbound'];
            return parts.filter((part) => part).join(' · ');
        }
        if (this.recordId) return 'Changes apply to every agent that uses this source';
        return this.agentName ? `Saved to the Library and assigned to ${this.agentName}` : 'Saved to the Library';
    }

    get isBuilder() {
        return this.mode === 'builder';
    }

    get isSoql() {
        return this.source.sourceType !== 'Apex';
    }

    get sourceTypeCards() {
        return [
            { value: 'SOQL', label: 'SOQL template', description: 'A read-only query with binds' },
            { value: 'Apex', label: 'Apex class', description: 'Implements IAIDataSourceExecutor' }
        ].map((card) => this.toCard(card, this.source.sourceType));
    }

    get bindingCards() {
        return [
            { value: 'Bound', label: 'Bound', description: 'Runs on the open record · :recordId' },
            { value: 'Unbound', label: 'Unbound', description: 'Needs no record' }
        ].map((card) => this.toCard(card, this.source.bindingType));
    }

    toCard(card, current) {
        const checked = card.value === current;
        return { ...card, checked, cardClass: checked ? 'aic-option aic-option_selected' : 'aic-option' };
    }

    get objectChoices() {
        const options = [{ label: 'Select an object', value: '' }].concat(this.objectOptions);
        return options.map((option) => ({ ...option, selected: option.value === this.source.targetObject }));
    }

    get targetHelp() {
        if (!this.agentObject || !this.source.targetObject) return null;
        if (this.source.targetObject === this.agentObject) return 'Matches the agent’s object.';
        if (this.source.bindingType === 'Bound') return `This agent runs on ${this.agentObject}, so a source bound to ${this.source.targetObject} won’t run for it.`;
        return null;
    }

    get validityLabel() {
        return this.soqlCheck && this.soqlCheck.isValid ? 'Valid query' : 'Not valid yet';
    }

    get validityClass() {
        return this.soqlCheck && this.soqlCheck.isValid ? 'valid' : 'invalid';
    }

    get soqlError() {
        return this.soqlCheck && !this.soqlCheck.isValid ? this.soqlCheck.message : null;
    }

    get rowCountLabel() {
        const count = this.testResult.rowCount;
        return `${formatNumber(count)} ${count === 1 ? 'row' : 'rows'}`;
    }

    get durationLabel() {
        return `${formatNumber(this.testResult.durationMs)} ms`;
    }

    get hasTestRows() {
        return this.testResult && this.testResult.rows && this.testResult.rows.length > 0;
    }

    get testRows() {
        return (this.testResult.rows || []).map((row, rowIndex) => ({
            key: `r${rowIndex}`,
            cells: row.map((value, cellIndex) => ({ key: `r${rowIndex}c${cellIndex}`, value }))
        }));
    }

    // =============================================================
    // Edits
    // =============================================================

    handleName(event) {
        const name = event.target.value;
        this.source = { ...this.source, name, developerName: this.developerNameTouched ? this.source.developerName : toDeveloperName(name) };
    }

    handleDeveloperName(event) {
        this.developerNameTouched = true;
        this.source = { ...this.source, developerName: event.target.value };
    }

    handleInput(event) {
        const field = event.target.dataset.field;
        const value = event.target.value;
        const changes = { [field]: value };

        // Switching binding keeps the schema's recordId in step with it, unless the admin has written their own.
        if (field === 'bindingType' && (!this.source.inputSchema || this.source.inputSchema === BOUND_SCHEMA)) {
            changes.inputSchema = value === 'Bound' ? BOUND_SCHEMA : '';
        }

        this.source = { ...this.source, ...changes };
        if (field === 'targetObject') this.testRecordId = undefined;
        if (['bindingType', 'targetObject'].includes(field) && this.source.soqlTemplate) this.runCheckLater();
    }

    handleSoql(event) {
        this.source = { ...this.source, soqlTemplate: event.target.value };
        this.testResult = undefined;
        this.runCheckLater();
    }

    handleActive(event) {
        this.source = { ...this.source, isActive: event.target.checked };
    }

    handleBuilderMode() {
        if (!this.source.targetObject) {
            this.error = 'Pick a Target Object before using the Builder.';
            return;
        }
        this.error = undefined;
        this.mode = 'builder';
    }

    handleWriteMode() {
        this.mode = 'write';
    }

    handleBuilderChange(event) {
        const { soql, inputSchema } = event.detail;
        this.source = { ...this.source, soqlTemplate: soql, inputSchema };
        this.testResult = undefined;
        this.runCheckLater();
    }

    async runCheck() {
        if (!this.isSoql || !this.source.soqlTemplate) {
            this.soqlCheck = undefined;
            return;
        }
        try {
            this.soqlCheck = await checkSoql({ soql: this.source.soqlTemplate, targetObject: this.source.targetObject, bindingType: this.source.bindingType });
        } catch (error) {
            this.soqlCheck = { isValid: false, message: reduceError(error), notes: [] };
        }
    }

    handleTestRecord(event) {
        this.testRecordId = event.detail.recordId || event.detail.value || undefined;
    }

    async handleRunTest() {
        this.isTesting = true;
        try {
            this.testResult = await testDataSource({ dataSourceJson: JSON.stringify(this.source), testRecordId: this.testRecordId || null });
        } catch (error) {
            this.testResult = { success: false, message: reduceError(error) };
        } finally {
            this.isTesting = false;
        }
    }

    // =============================================================
    // Save
    // =============================================================

    handleCancel() {
        this.close();
    }

    handleSave() {
        this.save(false);
    }

    handleSaveAndAssign() {
        this.save(true);
    }

    async save(assign) {
        this.isSaving = true;
        this.error = undefined;
        try {
            const id = await saveDataSource({ dataSourceJson: JSON.stringify(this.source), assignToAgentId: assign ? this.agentId : null });
            toast(this, assign ? 'Data source saved and assigned' : 'Data source saved', this.source.name);
            this.close({ id, assigned: assign });
        } catch (error) {
            this.error = reduceError(error);
            this.mode = 'write';
        } finally {
            this.isSaving = false;
        }
    }
}
