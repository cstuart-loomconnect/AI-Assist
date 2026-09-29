import { LightningElement, api } from 'lwc';
import { navigate, badgeClass } from 'c/aiConsoleUtils';

/*
Renders one AIConsoleDataStructure.ListResult table. Presentational: a link cell with a target
navigates there (through aiTabPage); a link cell without one fires rowopen with the row's Id, so the
list around it decides what "open" means (detail panel, record view, edit modal).
*/
export default class AiConsoleTable extends LightningElement {
    @api columns = [];
    @api rows = [];
    @api selectedId;
    @api density = 'default'; // compact | default | comfy
    @api wrapKeys = []; // Column keys whose text may wrap (long comments, messages).
    @api emptyMessage = 'Nothing to show yet.';

    get theadClass() {
        return (this.columns || []).every((column) => column.hideLabel) ? 'slds-assistive-text' : '';
    }

    get headerCells() {
        return (this.columns || []).map((column) => ({
            ...column,
            thClass: `aic-th${column.alignRight ? ' aic-right' : ''}${this.density === 'compact' ? ' compact' : ''}`
        }));
    }

    get displayRows() {
        const alignByKey = {};
        (this.columns || []).forEach((column) => {
            alignByKey[column.key] = column.alignRight;
        });
        const wrap = new Set(this.wrapKeys || []);

        return (this.rows || []).map((row) => {
            const classes = [];
            if (row.id === this.selectedId) classes.push('row_selected');
            if (row.isWarning) classes.push('row_warning');
            if (row.isError) classes.push('row_error');
            if (row.isMuted) classes.push('row_muted');

            return {
                id: row.id,
                rowClass: classes.join(' '),
                cells: (row.cells || []).map((cell) => ({
                    ...cell,
                    isLink: cell.type === 'link',
                    isBadge: cell.type === 'badge',
                    isMono: cell.type === 'mono',
                    isWarning: cell.type === 'warning',
                    isTwoLine: cell.type === 'twoLine',
                    badgeClass: badgeClass(cell.variant),
                    linkClass: cell.bold ? 'aic-bold' : '',
                    ariaCurrent: row.id === this.selectedId && !cell.target ? 'true' : 'false',
                    textClass: cell.variant === 'error' ? 'error-count' : '',
                    tdClass: `aic-td density_${this.density}${cell.alignRight || alignByKey[cell.key] ? ' aic-right' : ''}${wrap.has(cell.key) ? ' cell_wrap' : ''}`
                }))
            };
        });
    }

    get isEmpty() {
        return !this.rows || this.rows.length === 0;
    }

    handleLink(event) {
        event.preventDefault();
        const rowId = event.currentTarget.dataset.row;
        const cellKey = event.currentTarget.dataset.cell;
        const row = (this.rows || []).find((entry) => entry.id === rowId);
        const cell = row && row.cells.find((entry) => entry.key === cellKey);

        if (cell && cell.target) {
            navigate(this, cell.target);
            return;
        }
        this.dispatchEvent(new CustomEvent('rowopen', { detail: { id: rowId } }));
    }
}