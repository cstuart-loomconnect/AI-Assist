import { LightningElement, api } from 'lwc';
import getUiSettings from '@salesforce/apex/AIConsoleController.getUiSettings';
import saveUiSettings from '@salesforce/apex/AIConsoleController.saveUiSettings';
import { reduceError, toast } from 'c/aiConsoleUtils';

const LEVELS = [
    { value: 'org', label: 'Org default' },
    { value: 'profile', label: 'Profile' },
    { value: 'user', label: 'User' }
];

/*
Settings › UI Settings - the chat window's look and behaviour (AIAssistUISettings__c, a hierarchy custom
setting) at Org default, Profile or User level. A value that differs from what the level would inherit
is "Overridden"; Reset puts the inherited value back (saved with Save).
*/
export default class AiUiSettings extends LightningElement {
    @api section;
    @api pageState;

    level = 'org';
    ownerId;
    view = { rows: [], ownerOptions: [] };
    values = {};
    isLoading = true;
    isBusy = false;
    error;

    connectedCallback() {
        this.load();
    }

    async load() {
        this.isLoading = true;
        try {
            this.view = await getUiSettings({ level: this.level, ownerId: this.ownerId || null });
            this.ownerId = this.view.ownerId;
            this.values = {};
            this.view.rows.forEach((row) => {
                this.values[row.key] = row.value;
            });
            this.values = { ...this.values };
            this.error = undefined;
        } catch (error) {
            this.error = reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    get title() {
        return this.section?.label || 'UI Settings';
    }

    get isOrgLevel() {
        return this.level === 'org';
    }

    get levels() {
        return LEVELS.map((level) => ({
            ...level,
            linkClass: level.value === this.level ? 'scope scope_on' : 'scope',
            current: level.value === this.level ? 'page' : 'false'
        }));
    }

    get ownerLabel() {
        return this.level === 'profile' ? 'Profile' : 'User';
    }

    get ownerChoices() {
        return (this.view.ownerOptions || []).map((option) => ({ ...option, selected: option.value === this.ownerId }));
    }

    get ownerNote() {
        if (this.level === 'profile') {
            const users = this.view.userCount || 0;
            return `${users} ${users === 1 ? 'user' : 'users'}. A User-level setting beats Profile, and Profile beats Org default.`;
        }
        return 'A User-level setting beats Profile, and Profile beats Org default.';
    }

    get saveLabel() {
        if (this.isOrgLevel) return 'Save org default';
        return this.view.ownerName ? `Save for ${this.view.ownerName}` : 'Save';
    }

    get saveDisabled() {
        return this.isBusy || this.isLoading || (!this.isOrgLevel && !this.ownerId);
    }

    isOverridden(row) {
        if (this.isOrgLevel) return false;
        return String(this.values[row.key]) !== String(row.inheritedValue);
    }

    get overriddenCount() {
        return this.view.rows.filter((row) => this.isOverridden(row)).length;
    }

    get rows() {
        return this.view.rows.map((row) => {
            const value = this.values[row.key];
            const overridden = this.isOverridden(row);
            return {
                ...row,
                value,
                isToggle: row.type === 'toggle',
                isRadio: row.type === 'radio',
                checked: String(value === true),
                isOverridden: overridden,
                rowClass: overridden ? 'row row_overridden' : 'row',
                resetLabel: `Reset to ${row.inheritedLabel}`,
                choices: (row.options || []).map((option) => ({ ...option, checked: option.value === value }))
            };
        });
    }

    handleLevel(event) {
        event.preventDefault();
        const level = event.currentTarget.dataset.level;
        if (level === this.level) return;
        this.level = level;
        this.ownerId = null;
        this.load();
    }

    handleOwner(event) {
        this.ownerId = event.target.value;
        this.load();
    }

    handleToggle(event) {
        const key = event.currentTarget.dataset.key;
        this.values = { ...this.values, [key]: !(this.values[key] === true) };
    }

    handleRadio(event) {
        this.values = { ...this.values, [event.target.dataset.key]: event.target.value };
    }

    handleNumber(event) {
        const number = event.target.value === '' ? null : Math.round(Number(event.target.value));
        this.values = { ...this.values, [event.target.dataset.key]: number };
    }

    handleReset(event) {
        event.preventDefault();
        const key = event.currentTarget.dataset.key;
        const row = this.view.rows.find((entry) => entry.key === key);
        this.values = { ...this.values, [key]: row.inheritedValue };
    }

    handleCancel() {
        this.load();
    }

    async handleSave() {
        this.isBusy = true;
        this.error = undefined;
        try {
            this.view = await saveUiSettings({ level: this.level, ownerId: this.ownerId || null, valuesJson: JSON.stringify(this.values) });
            toast(this, 'UI settings saved', this.isOrgLevel ? 'Org default' : this.view.ownerName);
            await this.load();
        } catch (error) {
            this.error = reduceError(error);
        } finally {
            this.isBusy = false;
        }
    }
}
