import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import getPiiMappings from '@salesforce/apex/AIConsoleController.getPiiMappings';
import { reduceError } from 'c/aiConsoleUtils';

/*
A conversation's PII masking pairs (fake value -> real value), from AIPIIMapping__c. The server only
returns them to users holding the PII Registry section's permission set.
*/
export default class AiConsolePiiMappingsModal extends LightningModal {
    @api conversationId;
    @api conversationName;

    mappings = [];
    isLoading = true;
    error;

    async connectedCallback() {
        try {
            this.mappings = await getPiiMappings({ conversationId: this.conversationId });
        } catch (error) {
            this.error = reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    get hasMappings() {
        return this.mappings.length > 0;
    }

    handleClose() {
        this.close();
    }
}