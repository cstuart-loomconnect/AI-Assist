import { LightningElement, api } from 'lwc';
import getQueryObjects from '@salesforce/apex/AIConsoleController.getQueryObjects';
import getObjectFields from '@salesforce/apex/AIConsoleController.getObjectFields';
import { reduceError, formatNumber } from 'c/aiConsoleUtils';

const MAX_MATCHES = 8;
const DATE_TYPES = ['DATE', 'DATETIME'];
const NUMBER_TYPES = ['DOUBLE', 'CURRENCY', 'INTEGER', 'PERCENT', 'LONG'];

const OPERATORS = {
    date: [
        { value: '=', label: 'on' },
        { value: '>=', label: 'on or after' },
        { value: '<=', label: 'on or before' },
        { value: '>', label: 'after' },
        { value: '<', label: 'before' }
    ],
    number: [
        { value: '=', label: 'equals' },
        { value: '!=', label: 'not equal to' },
        { value: '>', label: 'greater than' },
        { value: '>=', label: 'at least' },
        { value: '<', label: 'less than' },
        { value: '<=', label: 'at most' }
    ],
    boolean: [{ value: '=', label: 'equals' }],
    text: [
        { value: '=', label: 'equals' },
        { value: '!=', label: 'not equal to' },
        { value: 'contains', label: 'contains' },
        { value: 'startsWith', label: 'starts with' }
    ]
};

const MODES = {
    date: [
        { value: 'today', label: 'Today (TODAY)' },
        { value: 'value', label: 'A date…' },
        { value: 'ai', label: 'Asked by the AI (bind)' }
    ],
    boolean: [
        { value: 'true', label: 'True' },
        { value: 'false', label: 'False' },
        { value: 'ai', label: 'Asked by the AI (bind)' }
    ],
    other: [
        { value: 'value', label: 'A value…' },
        { value: 'ai', label: 'Asked by the AI (bind)' }
    ]
};

let nextId = 1;

/*
The SOQL Builder inside aiDataSourceModal. The admin picks an object (for a bound source, the bound
object or anything that looks up to it), the fields to return, conditions, sort and limit; this
composes the SOQL template and its Input Schema and fires change with { soql, inputSchema }.
Validation (check) and the test run belong to the modal and come back in as properties.

A bound source always filters on the open record (the locked first condition). "Asked by the AI"
turns a condition's value into a bind the model fills in, and adds it to the Input Schema.
*/
export default class AiSoqlBuilder extends LightningElement {
    @api check;
    @api testResult;
    @api testRecordId;
    @api isTesting = false;

    objects = [];
    fields = [];
    objectKey;
    selectedFields = [];
    fieldSearch = '';
    activeMatch = 0;
    showMatches = false;
    conditions = [];
    logic = 'AND';
    sortField = 'CreatedDate';
    direction = 'DESC';
    rowLimit = 20;
    loadError;
    copied = false;

    _targetObject;
    _bindingType;

    @api
    get targetObject() {
        return this._targetObject;
    }
    set targetObject(value) {
        const changed = value !== this._targetObject;
        this._targetObject = value;
        if (changed && this.isConnectedToPage) this.loadObjects();
    }

    @api
    get bindingType() {
        return this._bindingType;
    }
    set bindingType(value) {
        const changed = value !== this._bindingType;
        this._bindingType = value;
        if (changed && this.isConnectedToPage) this.loadObjects();
    }

    isConnectedToPage = false;

    connectedCallback() {
        this.isConnectedToPage = true;
        this.loadObjects();
    }

    // =============================================================
    // Loading
    // =============================================================

    async loadObjects() {
        if (!this._targetObject && this.isBound) return;
        try {
            this.objects = (await getQueryObjects({ boundObject: this._targetObject, bindingType: this._bindingType })).map((option) => ({
                ...option,
                key: `${option.apiName}.${option.relationshipField || ''}`
            }));
            const keep = this.objects.find((option) => option.key === this.objectKey);
            this.objectKey = keep ? keep.key : this.objects.length ? this.objects[0].key : undefined;
            await this.loadFields();
        } catch (error) {
            this.loadError = reduceError(error);
        }
    }

    async loadFields() {
        const selected = this.selectedObject;
        if (!selected) return;
        try {
            this.fields = await getObjectFields({ objectApiName: selected.apiName });
            this.selectedFields = this.selectedFields.filter((apiName) => this.fields.some((field) => field.apiName === apiName));
            if (!this.selectedFields.length) {
                const nameField = this.fields.find((field) => field.apiName === 'Name');
                if (nameField) this.selectedFields = ['Name'];
            }
            if (!this.fields.some((field) => field.apiName === this.sortField)) this.sortField = '';
            this.emitChange();
        } catch (error) {
            this.loadError = reduceError(error);
        }
    }

    // =============================================================
    // View
    // =============================================================

    get isBound() {
        return this._bindingType === 'Bound';
    }

    get selectedObject() {
        return this.objects.find((option) => option.key === this.objectKey);
    }

    get objectChoices() {
        return this.objects.map((option) => ({ ...option, selected: option.key === this.objectKey }));
    }

    get relationshipLabel() {
        return this.selectedObject ? this.selectedObject.relationshipLabel : '';
    }

    get lockedFieldLabel() {
        const selected = this.selectedObject;
        if (!selected) return '';
        const field = this.fields.find((entry) => entry.apiName === selected.relationshipField);
        return field ? field.label : selected.relationshipField;
    }

    get topLevelFields() {
        return this.fields.filter((field) => !field.apiName.includes('.'));
    }

    get fieldCountLabel() {
        return `${this.selectedFields.length} of ${formatNumber(this.topLevelFields.length)}`;
    }

    get selectedFieldViews() {
        return this.selectedFields.map((apiName) => {
            const field = this.fields.find((entry) => entry.apiName === apiName);
            return { apiName, label: field ? field.label : apiName, removeLabel: `Remove ${apiName}` };
        });
    }

    get fieldMatches() {
        const search = this.fieldSearch.trim().toLowerCase();
        return this.fields
            .filter((field) => !this.selectedFields.includes(field.apiName))
            .filter((field) => !search || field.label.toLowerCase().includes(search) || field.apiName.toLowerCase().includes(search))
            .slice(0, MAX_MATCHES)
            .map((field, index) => ({
                ...field,
                ariaSelected: String(index === this.activeMatch),
                optionClass: index === this.activeMatch ? 'match match_active' : 'match'
            }));
    }

    get dropdownExpanded() {
        return String(this.showMatches);
    }

    get isAnd() {
        return this.logic === 'AND';
    }

    get isOr() {
        return this.logic === 'OR';
    }

    get filterableFields() {
        return this.topLevelFields.filter((field) => field.isFilterable && field.dataType !== 'TEXTAREA');
    }

    get conditionViews() {
        return this.conditions.map((condition, index) => {
            const field = this.fields.find((entry) => entry.apiName === condition.field);
            const kind = this.kindOf(field);
            const modes = kind === 'date' ? MODES.date : kind === 'boolean' ? MODES.boolean : MODES.other;
            const joiner = index === 0 && !this.isBound ? 'WHERE' : this.logic;

            return {
                ...condition,
                joiner,
                fieldOptions: this.filterableFields.map((entry) => ({ value: entry.apiName, label: entry.label, selected: entry.apiName === condition.field })),
                operatorOptions: OPERATORS[kind].map((operator) => ({ ...operator, selected: operator.value === condition.operator })),
                modeOptions: modes.map((mode) => ({ ...mode, selected: mode.value === condition.valueMode })),
                showValueInput: condition.valueMode === 'value',
                inputType: kind === 'date' ? 'date' : kind === 'number' ? 'number' : 'text'
            };
        });
    }

    get sortOptions() {
        return this.topLevelFields.filter((field) => field.isSortable).map((field) => ({ value: field.apiName, label: field.label, selected: field.apiName === this.sortField }));
    }

    get sortIsDate() {
        const field = this.fields.find((entry) => entry.apiName === this.sortField);
        return field && DATE_TYPES.includes(field.dataType);
    }

    get descLabel() {
        return this.sortIsDate ? 'Newest first' : 'Descending';
    }

    get ascLabel() {
        return this.sortIsDate ? 'Oldest first' : 'Ascending';
    }

    get isDesc() {
        return this.direction === 'DESC';
    }

    get isAsc() {
        return this.direction === 'ASC';
    }

    get hasCheck() {
        return !!this.check;
    }

    get checkNotes() {
        return (this.check && this.check.notes) || [];
    }

    get copyLabel() {
        return this.copied ? 'Copied' : 'Copy';
    }

    get testSummary() {
        const count = this.testResult.rowCount;
        return `${formatNumber(count)} ${count === 1 ? 'row' : 'rows'} · ${formatNumber(this.testResult.durationMs)} ms`;
    }

    // =============================================================
    // Composing the query
    // =============================================================

    kindOf(field) {
        if (!field) return 'text';
        if (DATE_TYPES.includes(field.dataType)) return 'date';
        if (NUMBER_TYPES.includes(field.dataType)) return 'number';
        if (field.dataType === 'BOOLEAN') return 'boolean';
        return 'text';
    }

    bindNameFor(condition) {
        const base = condition.field.replace(/__c$/i, '').replace(/[^A-Za-z0-9]/g, '');
        return base.charAt(0).toLowerCase() + base.slice(1);
    }

    conditionText(condition) {
        const field = this.fields.find((entry) => entry.apiName === condition.field);
        if (!field) return null;
        const kind = this.kindOf(field);

        if (condition.valueMode === 'ai') {
            const bind = `:${this.bindNameFor(condition)}`;
            if (condition.operator === 'contains' || condition.operator === 'startsWith') return { text: `${field.apiName} LIKE `, bind };
            return { text: `${field.apiName} ${condition.operator} `, bind };
        }

        let literal;
        if (kind === 'date') {
            if (condition.valueMode === 'today') literal = 'TODAY';
            else if (!condition.value) return null;
            else literal = field.dataType === 'DATETIME' ? `${condition.value}T00:00:00Z` : condition.value;
        } else if (kind === 'boolean') {
            literal = condition.valueMode === 'false' ? 'false' : 'true';
        } else if (kind === 'number') {
            if (condition.value === '' || condition.value === null || condition.value === undefined) return null;
            literal = String(Number(condition.value));
        } else {
            const escaped = String(condition.value || '').replace(/\\/g, '\\\\').replace(/'/g, "\\'");
            if (condition.operator === 'contains') return { text: `${field.apiName} LIKE '%${escaped}%'` };
            if (condition.operator === 'startsWith') return { text: `${field.apiName} LIKE '${escaped}%'` };
            literal = `'${escaped}'`;
        }
        return { text: `${field.apiName} ${condition.operator} ${literal}` };
    }

    // [{ key, tokens: [{ key, text, cls }] }] - the query as highlighted lines.
    get soqlLines() {
        const selected = this.selectedObject;
        if (!selected) return [];

        const lines = [];
        const push = (parts) => lines.push({ key: `l${lines.length}`, tokens: parts.map((part, index) => ({ key: `l${lines.length}t${index}`, text: part.text, cls: part.cls || '' })) });

        const fields = this.selectedFields.length ? this.selectedFields : ['Id'];
        const chunks = [];
        for (let index = 0; index < fields.length; index += 3) chunks.push(fields.slice(index, index + 3).join(', '));
        chunks.forEach((chunk, index) => {
            const trailing = index < chunks.length - 1 ? ',' : '';
            push(index === 0 ? [{ text: 'SELECT', cls: 'kw' }, { text: ` ${chunk}${trailing}` }] : [{ text: `       ${chunk}${trailing}` }]);
        });

        push([{ text: 'FROM', cls: 'kw' }, { text: ` ${selected.apiName}` }]);

        const parts = this.conditions.map((condition) => this.conditionText(condition)).filter((part) => part);
        const conditionTokens = (part) => [{ text: part.text }].concat(part.bind ? [{ text: part.bind, cls: 'bind' }] : []);

        if (this.isBound) {
            push([{ text: 'WHERE', cls: 'kw' }, { text: ` ${selected.relationshipField} = ` }, { text: ':recordId', cls: 'bind' }]);
            if (parts.length && this.logic === 'AND') parts.forEach((part) => push([{ text: '  ' }, { text: 'AND', cls: 'kw' }, { text: ' ' }].concat(conditionTokens(part))));
            if (parts.length && this.logic === 'OR') {
                parts.forEach((part, index) => {
                    const lead = index === 0 ? [{ text: '  ' }, { text: 'AND', cls: 'kw' }, { text: ' (' }] : [{ text: '       ' }, { text: 'OR', cls: 'kw' }, { text: ' ' }];
                    const tail = index === parts.length - 1 ? [{ text: ')' }] : [];
                    push(lead.concat(conditionTokens(part), tail));
                });
            }
        } else {
            parts.forEach((part, index) => {
                const lead = index === 0 ? [{ text: 'WHERE', cls: 'kw' }, { text: ' ' }] : [{ text: '  ' }, { text: this.logic, cls: 'kw' }, { text: ' ' }];
                push(lead.concat(conditionTokens(part)));
            });
        }

        if (this.sortField) push([{ text: 'ORDER BY', cls: 'kw' }, { text: ` ${this.sortField} ${this.direction}` }]);
        push([{ text: 'LIMIT', cls: 'kw' }, { text: ` ${this.rowLimit}` }]);
        return lines;
    }

    get soql() {
        return this.soqlLines.map((line) => line.tokens.map((token) => token.text).join('')).join('\n');
    }

    get aiBinds() {
        return this.conditions.filter((condition) => condition.field && condition.valueMode === 'ai').map((condition) => this.bindNameFor(condition));
    }

    get inputSchema() {
        const properties = {};
        const required = [];
        if (this.isBound) {
            properties.recordId = { type: 'string' };
            required.push('recordId');
        }
        this.aiBinds.forEach((bind) => {
            properties[bind] = { type: 'string' };
            required.push(bind);
        });
        return JSON.stringify({ type: 'object', properties, required }, null, 2);
    }

    get schemaPreview() {
        const entries = [];
        if (this.isBound) entries.push('"recordId": "string (automatic)"');
        this.aiBinds.forEach((bind) => entries.push(`"${bind}": "string (asked by the AI)"`));
        return entries.length ? `{ ${entries.join(',\n  ')} }` : '{ }';
    }

    emitChange() {
        this.dispatchEvent(new CustomEvent('change', { detail: { soql: this.soql, inputSchema: this.inputSchema } }));
    }

    // =============================================================
    // Handlers
    // =============================================================

    handleObject(event) {
        this.objectKey = event.target.value;
        this.selectedFields = [];
        this.conditions = [];
        this.loadFields();
    }

    focusFieldSearch() {
        const input = this.template.querySelector('.field-search');
        if (input) input.focus();
    }

    handleFieldSearch(event) {
        this.fieldSearch = event.target.value;
        this.activeMatch = 0;
        this.showMatches = this.fieldSearch.trim().length > 0;
    }

    handleFieldKey(event) {
        const matches = this.fieldMatches;
        if (event.key === 'ArrowDown') {
            event.preventDefault();
            this.showMatches = true;
            this.activeMatch = Math.min(this.activeMatch + 1, matches.length - 1);
        } else if (event.key === 'ArrowUp') {
            event.preventDefault();
            this.activeMatch = Math.max(this.activeMatch - 1, 0);
        } else if (event.key === 'Enter') {
            event.preventDefault();
            if (matches[this.activeMatch]) this.addField(matches[this.activeMatch].apiName);
        } else if (event.key === 'Escape') {
            this.showMatches = false;
        } else if (event.key === 'Backspace' && !this.fieldSearch && this.selectedFields.length) {
            this.selectedFields = this.selectedFields.slice(0, -1);
            this.emitChange();
        }
    }

    handlePickField(event) {
        event.preventDefault();
        this.addField(event.currentTarget.dataset.api);
    }

    addField(apiName) {
        if (!this.selectedFields.includes(apiName)) this.selectedFields = [...this.selectedFields, apiName];
        this.fieldSearch = '';
        this.showMatches = false;
        this.emitChange();
    }

    handleRemoveField(event) {
        event.stopPropagation();
        const apiName = event.currentTarget.dataset.api;
        this.selectedFields = this.selectedFields.filter((entry) => entry !== apiName);
        this.emitChange();
    }

    handleLogic(event) {
        this.logic = event.target.value;
        this.emitChange();
    }

    handleAddCondition() {
        this.conditions = [...this.conditions, { id: `c${nextId++}`, field: '', operator: '=', valueMode: 'value', value: '' }];
    }

    handleRemoveCondition(event) {
        const id = event.currentTarget.dataset.id;
        this.conditions = this.conditions.filter((condition) => condition.id !== id);
        this.emitChange();
    }

    handleCondition(event) {
        const id = event.target.dataset.id;
        const prop = event.target.dataset.prop;
        const value = event.target.value;

        this.conditions = this.conditions.map((condition) => {
            if (condition.id !== id) return condition;
            const updated = { ...condition, [prop]: value };
            if (prop === 'field') {
                // A new field resets the operator and value to ones that fit its type.
                const kind = this.kindOf(this.fields.find((entry) => entry.apiName === value));
                updated.operator = OPERATORS[kind][0].value;
                updated.valueMode = kind === 'date' ? 'today' : kind === 'boolean' ? 'true' : 'value';
                updated.value = '';
            }
            return updated;
        });
        this.emitChange();
    }

    handleSort(event) {
        this.sortField = event.target.value;
        this.emitChange();
    }

    handleDirection(event) {
        this.direction = event.target.value;
        this.emitChange();
    }

    handleLimit(event) {
        const value = Math.round(Number(event.target.value));
        this.rowLimit = Number.isFinite(value) && value >= 1 ? Math.min(value, 200) : 20;
        this.emitChange();
    }

    async handleCopy() {
        try {
            await navigator.clipboard.writeText(this.soql);
            this.copied = true;
        } catch (error) {
            this.copied = false;
        }
    }

    handleRecord(event) {
        this.dispatchEvent(new CustomEvent('recordchange', { detail: { recordId: event.detail.recordId } }));
    }

    handleRunTest() {
        this.dispatchEvent(new CustomEvent('runtest'));
    }
}