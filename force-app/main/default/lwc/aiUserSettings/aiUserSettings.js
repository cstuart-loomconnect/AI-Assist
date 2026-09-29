import { LightningElement, api } from 'lwc';
import getUserSettingsList from '@salesforce/apex/AIConsoleController.getUserSettingsList';
import getUserSettings from '@salesforce/apex/AIConsoleController.getUserSettings';
import saveUserSettings from '@salesforce/apex/AIConsoleController.saveUserSettings';
import { reduceError, toast, formatNumber, parseNumber, debounce } from 'c/aiConsoleUtils';

/*
Settings › User Settings - every AIUserSettings__c row (one per user with an AI Assist User Type).
The panel edits the picked user's access, limits and features; the type itself is changed on the
user record, which is what creates and removes these rows.
*/
export default class AiUserSettings extends LightningElement {
    @api section;
    @api pageState;

    list = [];
    detail;
    selectedId;
    searchText = '';
    listError;
    detailError;
    isSaving = false;

    searchLater = debounce(() => this.loadList(), 300);

    connectedCallback() {
        this.loadList();
    }

    async loadList() {
        try {
            this.list = await getUserSettingsList({ searchText: this.searchText });
            this.listError = undefined;
            const keep = this.list.find((row) => row.id === this.selectedId);
            if (!keep && this.list.length) this.select(this.list[0].id);
        } catch (error) {
            this.listError = reduceError(error);
        }
    }

    async select(settingsId) {
        this.selectedId = settingsId;
        try {
            this.detail = await getUserSettings({ settingsId });
            this.detailError = undefined;
        } catch (error) {
            this.detailError = reduceError(error);
        }
    }

    get title() {
        return this.section?.label || 'User Settings';
    }

    get isEmpty() {
        return this.list.length === 0;
    }

    get rows() {
        return this.list.map((row) => {
            const classes = [];
            if (row.id === this.selectedId) classes.push('row_selected');
            if (row.isInactive) classes.push('row_inactive');
            return {
                ...row,
                rowClass: classes.join(' '),
                current: row.id === this.selectedId ? 'true' : 'false',
                inactiveLabel: row.userType ? `${row.userType} · inactive` : 'No type · inactive',
                tokensLabel: row.isInactive ? '—' : formatNumber(row.maxTokens)
            };
        });
    }

    get detailSubtitle() {
        return `${this.detail.userType} · ${this.detail.isActive ? 'Active' : 'Inactive'}`;
    }

    get channelChoices() {
        return (this.detail.channelOptions || []).map((option) => ({ ...option, checked: (this.detail.allowedChannels || []).includes(option.value) }));
    }

    choices(options, value) {
        return [{ label: '—', value: '' }].concat(options || []).map((option) => ({ ...option, selected: option.value === (value || '') }));
    }

    get visibilityChoices() {
        return this.choices(this.detail.visibilityOptions, this.detail.visibilityScope);
    }

    get behaviorChoices() {
        return this.choices(this.detail.limitBehaviorOptions, this.detail.limitBehavior);
    }

    get maxTokensLabel() {
        return this.detail.maxTokens === null || this.detail.maxTokens === undefined ? '' : formatNumber(this.detail.maxTokens);
    }

    get workflowChecked() {
        return String(!!this.detail.workflowActionsEnabled);
    }

    get exportChecked() {
        return String(!!this.detail.exportEnabled);
    }

    get debugChecked() {
        return String(!!this.detail.debugModeEnabled);
    }

    handleSearch(event) {
        this.searchText = event.target.value;
        this.searchLater();
    }

    handleSelect(event) {
        event.preventDefault();
        this.select(event.currentTarget.dataset.id);
    }

    handleChannel(event) {
        const channels = new Set(this.detail.allowedChannels || []);
        if (event.target.checked) channels.add(event.target.value);
        else channels.delete(event.target.value);
        this.detail = { ...this.detail, allowedChannels: [...channels] };
    }

    handleInput(event) {
        this.detail = { ...this.detail, [event.target.dataset.field]: event.target.value || null };
    }

    handleNumber(event) {
        const value = parseNumber(event.target.value);
        this.detail = { ...this.detail, [event.target.dataset.field]: value === null ? null : Math.round(value) };
    }

    handleToggle(event) {
        const field = event.currentTarget.dataset.field;
        this.detail = { ...this.detail, [field]: !this.detail[field] };
    }

    async handleSave() {
        this.isSaving = true;
        this.detailError = undefined;
        try {
            this.detail = await saveUserSettings({ settingsJson: JSON.stringify(this.detail) });
            toast(this, 'User settings saved', this.detail.userName);
            this.loadList();
        } catch (error) {
            this.detailError = reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }
}