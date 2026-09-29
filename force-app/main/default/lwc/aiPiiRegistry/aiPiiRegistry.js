import { LightningElement, api } from 'lwc';
import getPiiRegistry from '@salesforce/apex/AIConsoleController.getPiiRegistry';
import getPiiFields from '@salesforce/apex/AIConsoleController.getPiiFields';
import syncPii from '@salesforce/apex/AIConsoleController.syncPii';
import getPiiMappings from '@salesforce/apex/AIConsoleController.getPiiMappings';
import AiPiiAddObjectModal from 'c/aiPiiAddObjectModal';
import { TABS, SECTIONS, navigate, reduceError, toast, badgeClass, formatNumber } from 'c/aiConsoleUtils';

const FIELDS_SHOWN = 6;
const PERMISSION_SET_AUDIENCE = { AIAssistSuperUser: 'Super Users only', AIAssistAdminUser: 'Admins only' };

/*
Settings › PII Registry - the objects whose PII fields are masked before anything reaches the AI
(AIPIIRegistry__c / AIPIIFieldMetadata__c). Sync runs the same AIPiiRegistryWorker the nightly
schedule does. Mapping lookup shows one conversation's fake-to-real pairs.
*/
export default class AiPiiRegistry extends LightningElement {
    @api section;
    @api pageState;

    registry = { objects: [], failed: [] };
    selectedId;
    fields = [];
    showAllFields = false;
    view = 'objects';
    isLoading = true;
    isLoadingFields = false;
    isBusy = false;
    error;

    mappings = [];
    lookupDone = false;
    lookupError;
    conversationObject = 'AIConversation__c';

    connectedCallback() {
        this.load();
    }

    async load() {
        try {
            this.apply(await getPiiRegistry());
            this.error = undefined;
        } catch (error) {
            this.error = reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    apply(registry) {
        this.registry = registry;
        const keep = registry.objects.find((row) => row.id === this.selectedId);
        const next = keep || registry.objects.find((row) => !row.isFailed) || registry.objects[0];
        if (next) this.select(next.id);
    }

    async select(registryId) {
        this.selectedId = registryId;
        this.showAllFields = false;
        this.isLoadingFields = true;
        try {
            this.fields = await getPiiFields({ registryId });
        } catch (error) {
            this.fields = [];
            this.error = reduceError(error);
        } finally {
            this.isLoadingFields = false;
        }
    }

    get title() {
        return this.section?.label || 'PII Registry';
    }

    get eyebrow() {
        const audience = PERMISSION_SET_AUDIENCE[this.section?.requiresPermissionSet];
        return audience ? `Settings · ${audience}` : 'Settings';
    }

    get isLookup() {
        return this.view === 'lookup';
    }

    get objectsTabClass() {
        return this.isLookup ? 'tab' : 'tab tab_on';
    }

    get lookupTabClass() {
        return this.isLookup ? 'tab tab_on' : 'tab';
    }

    get objectsCurrent() {
        return this.isLookup ? 'false' : 'page';
    }

    get lookupCurrent() {
        return this.isLookup ? 'page' : 'false';
    }

    get objectsTitle() {
        const max = this.registry.maxObjects;
        return max ? `Objects in scope (${this.registry.objectCount} of ${max})` : `Objects in scope (${this.registry.objectCount})`;
    }

    get noObjects() {
        return this.registry.objects.length === 0;
    }

    get objectRows() {
        return this.registry.objects.map((row) => {
            const classes = [];
            if (row.isFailed) classes.push('row_failed');
            if (row.id === this.selectedId) classes.push('row_selected');
            return {
                ...row,
                rowClass: classes.join(' '),
                current: row.id === this.selectedId ? 'true' : 'false',
                badgeClass: badgeClass(row.syncVariant),
                fieldsLabel: row.fieldCount === null || row.fieldCount === undefined ? '—' : formatNumber(row.fieldCount),
                piiLabel: row.piiCount === null || row.piiCount === undefined ? '—' : formatNumber(row.piiCount),
                activeLabel: row.isActive ? 'Yes' : 'No'
            };
        });
    }

    get failures() {
        return (this.registry.failed || []).map((row) => ({
            ...row,
            messageText: row.failureMessage ? `${row.failureMessage.replace(/\.$/, '')}.` : 'The last sync didn’t finish.'
        }));
    }

    get selected() {
        return this.registry.objects.find((row) => row.id === this.selectedId);
    }

    get fieldsTitle() {
        return `${this.selected.objectLabel} · PII fields (${this.fields.length})`;
    }

    get visibleFields() {
        return this.showAllFields ? this.fields : this.fields.slice(0, FIELDS_SHOWN);
    }

    get noFields() {
        return this.fields.length === 0;
    }

    get hasMoreFields() {
        return !this.showAllFields && this.fields.length > FIELDS_SHOWN;
    }

    get moreCount() {
        return this.fields.length - FIELDS_SHOWN;
    }

    get hasMappings() {
        return this.mappings.length > 0;
    }

    handleView(event) {
        event.preventDefault();
        this.view = event.currentTarget.dataset.view;
    }

    handleSelect(event) {
        event.preventDefault();
        this.select(event.currentTarget.dataset.id);
    }

    handleShowAll(event) {
        event.preventDefault();
        this.showAllFields = true;
    }

    handleSeeLog(event) {
        event.preventDefault();
        navigate(this, { tab: TABS.ACTIVITY, section: SECTIONS.ACTIVITY_ERROR_LOG });
    }

    async handleSyncAll() {
        await this.runSync(null, 'Sync started', 'Every active object is queued. Refresh in a minute to see the results.');
    }

    async handleResync(event) {
        await this.runSync(event.currentTarget.dataset.id, 'Sync started', 'Refresh in a minute to see the result.');
    }

    async runSync(registryId, title, message) {
        this.isBusy = true;
        this.error = undefined;
        try {
            this.apply(await syncPii({ registryId }));
            toast(this, title, message);
        } catch (error) {
            this.error = reduceError(error);
        } finally {
            this.isBusy = false;
        }
    }

    async handleAddObject() {
        const registry = await AiPiiAddObjectModal.open({ size: 'small', label: 'Add object', existing: this.registry.objects.map((row) => row.objectApiName) });
        if (registry) this.apply(registry);
    }

    async handleConversation(event) {
        const conversationId = event.detail.recordId;
        this.mappings = [];
        this.lookupDone = false;
        this.lookupError = undefined;
        if (!conversationId) return;
        try {
            this.mappings = await getPiiMappings({ conversationId });
            this.lookupDone = true;
        } catch (error) {
            this.lookupError = reduceError(error);
        }
    }
}
