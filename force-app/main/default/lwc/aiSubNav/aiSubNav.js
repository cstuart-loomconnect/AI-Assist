import { LightningElement, api } from 'lwc';

/*
The console's left rail (SLDS vertical navigation). Presentational only - aiTabPage owns which item
is active and what selecting one does; this fires select with { name }.
*/
export default class AiSubNav extends LightningElement {
    @api heading;
    @api items = [];
    @api activeName;

    get rows() {
        return (this.items || []).map((item) => {
            const isActive = item.name === this.activeName;
            return {
                ...item,
                hasCount: item.count !== null && item.count !== undefined,
                itemClass: isActive ? 'slds-nav-vertical__item slds-is-active' : 'slds-nav-vertical__item',
                ariaCurrent: isActive ? 'page' : 'false'
            };
        });
    }

    handleClick(event) {
        event.preventDefault();
        this.dispatchEvent(new CustomEvent('select', { detail: { name: event.currentTarget.dataset.name } }));
    }
}