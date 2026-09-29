import { LightningElement, api } from 'lwc';
import getAttentionItems from '@salesforce/apex/AIConsoleController.getAttentionItems';
import { navigate, reduceError } from 'c/aiConsoleUtils';

const KIND_STYLE = {
    violation: { icon: 'shield', tile: 'tile tile_red' },
    pii: { icon: 'refresh', tile: 'tile tile_orange' },
    error: { icon: 'warning', tile: 'tile tile_orange' },
    terms: { icon: 'checkCircle', tile: 'tile tile_blue' },
    draft: { icon: 'pencil', tile: 'tile tile_blue' }
};

/*
Home › Needs attention - up to five things an admin should look at, each linking to where it's fixed.
Only items the user can open are returned (AIConsoleHomeService checks each target section's permission set).
*/
export default class AiHomeAttention extends LightningElement {
    @api section;
    @api pageState;

    items = [];
    error;
    isLoading = true;

    connectedCallback() {
        this.load();
    }

    async load() {
        try {
            this.items = await getAttentionItems();
            this.error = undefined;
        } catch (error) {
            this.error = reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    get title() {
        return this.section?.label || 'Needs attention';
    }

    get count() {
        return this.items.length;
    }

    get hasItems() {
        return this.items.length > 0;
    }

    get rows() {
        return this.items.map((item, index) => {
            const style = KIND_STYLE[item.kind] || KIND_STYLE.draft;
            return { ...item, index, key: `${item.kind}-${index}`, icon: style.icon, iconClass: style.tile };
        });
    }

    handleOpen(event) {
        event.preventDefault();
        const item = this.items[Number(event.currentTarget.dataset.index)];
        if (item && item.target) navigate(this, item.target);
    }
}
