import { LightningElement, api } from 'lwc';
import LightningConfirm from 'lightning/confirm';
import getAppSettings from '@salesforce/apex/AIConsoleController.getAppSettings';
import saveAppSettings from '@salesforce/apex/AIConsoleController.saveAppSettings';
import { reduceError, toast, formatNumber, parseNumber } from 'c/aiConsoleUtils';

/*
Settings › App Settings - the AIAssistSettings__c org defaults every AI Assist service reads. Edits
are held on screen until Save; Cancel reloads what's saved. Turning the application off asks first,
since it stops AI Assist for everyone.
*/
export default class AiAppSettings extends LightningElement {
    @api section;
    @api pageState;

    settings = { successCodes: [], retryCodes: [], modelOptions: [], agentOptions: [], emailTemplateOptions: [] };
    isLoading = true;
    isBusy = false;
    error;

    connectedCallback() {
        this.load();
    }

    async load() {
        this.isLoading = true;
        try {
            this.settings = await getAppSettings();
            this.error = undefined;
        } catch (error) {
            this.error = reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    get title() {
        return this.section?.label || 'App Settings';
    }

    get activeChecked() {
        return String(!!this.settings.isApplicationActive);
    }

    get powerClass() {
        return this.settings.isApplicationActive ? 'power' : 'power power_off';
    }

    get onOffLabel() {
        return this.settings.isApplicationActive ? 'On' : 'Off';
    }

    get onOffClass() {
        return this.settings.isApplicationActive ? 'on' : 'off';
    }

    get exceptionChecked() {
        return String(!!this.settings.isExceptionLoggingEnabled);
    }

    get platformChecked() {
        return String(!!this.settings.isPlatformLoggingEnabled);
    }

    get timeoutLabel() {
        return this.settings.calloutTimeout === null || this.settings.calloutTimeout === undefined ? '' : formatNumber(this.settings.calloutTimeout);
    }

    get budgetLabel() {
        return this.settings.globalTokenBudget === null || this.settings.globalTokenBudget === undefined ? '' : formatNumber(this.settings.globalTokenBudget);
    }

    get budgetHelp() {
        return `Across every agent and user. ${formatNumber(this.settings.tokensToday || 0)} used today.`;
    }

    choices(options, value, blankLabel) {
        const list = blankLabel ? [{ label: blankLabel, value: '' }].concat(options || []) : options || [];
        return list.map((option) => ({ ...option, selected: option.value === (value || '') }));
    }

    get modelChoices() {
        return this.choices(this.settings.modelOptions, this.settings.defaultModel, 'None');
    }

    get agentChoices() {
        return this.choices(this.settings.agentOptions, this.settings.auditLoggingRecordId);
    }

    get templateChoices() {
        return this.choices(this.settings.emailTemplateOptions, this.settings.emailTemplateId);
    }

    handleInput(event) {
        this.settings = { ...this.settings, [event.target.dataset.field]: event.target.value };
    }

    handleNumber(event) {
        this.settings = { ...this.settings, [event.target.dataset.field]: parseNumber(event.target.value) };
    }

    async handleToggle(event) {
        const field = event.currentTarget.dataset.field;
        const next = !this.settings[field];
        if (field === 'isApplicationActive' && !next) {
            const confirmed = await LightningConfirm.open({ message: 'Every user loses AI Assist until it’s turned back on and saved.', label: 'Turn off AI Assist?', theme: 'warning' });
            if (!confirmed) return;
        }
        this.settings = { ...this.settings, [field]: next };
    }

    handleCodeKey(event) {
        if (event.key !== 'Enter' && event.key !== ',') return;
        event.preventDefault();
        const code = event.target.value.trim();
        const list = event.target.dataset.list;
        if (!/^[1-5]\d\d$/.test(code)) {
            toast(this, 'Not a status code', 'Enter a three-digit HTTP status code, e.g. 429.', 'warning');
            return;
        }
        if (!this.settings[list].includes(code)) this.settings = { ...this.settings, [list]: [...this.settings[list], code] };
        event.target.value = '';
    }

    handleRemoveCode(event) {
        const list = event.currentTarget.dataset.list;
        const code = event.currentTarget.dataset.code;
        this.settings = { ...this.settings, [list]: this.settings[list].filter((entry) => entry !== code) };
    }

    handleCancel() {
        this.load();
    }

    async handleSave() {
        this.isBusy = true;
        this.error = undefined;
        try {
            this.settings = await saveAppSettings({ settingsJson: JSON.stringify(this.settings) });
            toast(this, 'App settings saved', 'Every AI Assist service uses them from the next request.');
        } catch (error) {
            this.error = reduceError(error);
        } finally {
            this.isBusy = false;
        }
    }
}