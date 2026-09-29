import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import getModelConfig from '@salesforce/apex/AIConsoleController.getModelConfig';
import getNamedCredentialOptions from '@salesforce/apex/AIConsoleController.getNamedCredentialOptions';
import saveModelConfig from '@salesforce/apex/AIConsoleController.saveModelConfig';
import testModelConnection from '@salesforce/apex/AIConsoleController.testModelConnection';
import { reduceError, toDeveloperName, parseNumber, formatNumber, toast } from 'c/aiConsoleUtils';

const PROVIDERS = [
    { value: 'Anthropic', label: 'Anthropic', description: 'Fills in the Messages API path and version header', apiPath: '/v1/messages', headerName: 'anthropic-version', headerValue: '2023-06-01' },
    { value: 'Open AI', label: 'Open AI', description: 'No version header needed', apiPath: '/v1/chat/completions', headerName: '', headerValue: '' }
];

/*
New / Edit Model Configuration (AIModelConfiguration__c). Picking a provider fills in its API path and
version header; Test connection sends a one-line prompt with the form's current values before saving.
Closes with { id } when saved.
*/
export default class AiModelConfigModal extends LightningModal {
    @api recordId;

    model = { provider: 'Anthropic', apiPath: '/v1/messages', headerName: 'anthropic-version', headerValue: '2023-06-01', temperature: 0.2, maxOutputTokens: 1024, retryAttempts: 2, isActive: true };
    credentials = [];
    developerNameTouched = false;
    isLoading = true;
    isSaving = false;
    isTesting = false;
    testResult;
    error;

    async connectedCallback() {
        try {
            const [credentials, model] = await Promise.all([getNamedCredentialOptions(), this.recordId ? getModelConfig({ modelId: this.recordId }) : Promise.resolve(null)]);
            this.credentials = credentials || [];
            if (model) {
                this.model = { ...model };
                this.developerNameTouched = true;
            } else if (this.credentials.length) {
                this.model = { ...this.model, namedCredential: this.credentials[0].value };
            }
        } catch (error) {
            this.error = reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    get providerOptions() {
        return PROVIDERS.map((provider) => ({
            ...provider,
            checked: provider.value === this.model.provider,
            cardClass: provider.value === this.model.provider ? 'aic-option aic-option_selected' : 'aic-option'
        }));
    }

    get hasCredentialOptions() {
        return this.credentials.length > 0;
    }

    get credentialOptions() {
        return this.credentials.map((option) => ({ ...option, selected: option.value === this.model.namedCredential }));
    }

    get temperatureLabel() {
        return this.model.temperature === null || this.model.temperature === undefined ? '—' : Number(this.model.temperature).toFixed(1);
    }

    get testSummary() {
        const result = this.testResult;
        if (result.success) return `Connected · HTTP ${result.statusCode} · ${formatNumber(result.durationMs)} ms`;
        return result.statusCode ? `HTTP ${result.statusCode} · ${result.message}` : result.message;
    }

    handleProvider(event) {
        const provider = PROVIDERS.find((entry) => entry.value === event.target.value);
        this.model = { ...this.model, provider: provider.value, apiPath: provider.apiPath, headerName: provider.headerName, headerValue: provider.headerValue };
        this.testResult = undefined;
    }

    handleName(event) {
        const name = event.target.value;
        this.model = { ...this.model, name, developerName: this.developerNameTouched ? this.model.developerName : toDeveloperName(name) };
    }

    handleDeveloperName(event) {
        this.developerNameTouched = true;
        this.model = { ...this.model, developerName: event.target.value };
    }

    handleInput(event) {
        this.model = { ...this.model, [event.target.dataset.field]: event.target.value };
        this.testResult = undefined;
    }

    handleNumber(event) {
        this.model = { ...this.model, [event.target.dataset.field]: parseNumber(event.target.value) };
    }

    handleActive(event) {
        this.model = { ...this.model, isActive: event.target.checked };
    }

    async handleTest() {
        this.isTesting = true;
        this.error = undefined;
        try {
            this.testResult = await testModelConnection({ modelJson: JSON.stringify(this.model) });
        } catch (error) {
            this.error = reduceError(error);
        } finally {
            this.isTesting = false;
        }
    }

    handleCancel() {
        this.close();
    }

    async handleSave() {
        this.isSaving = true;
        this.error = undefined;
        try {
            const id = await saveModelConfig({ modelJson: JSON.stringify(this.model) });
            toast(this, 'Model configuration saved', this.model.name);
            this.close({ id });
        } catch (error) {
            this.error = reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }
}
