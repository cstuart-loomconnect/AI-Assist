import { LightningElement, api } from 'lwc';

const LIVE_OPTIONS = [
    { value: 'activate', label: 'Activate for everyone', description: 'Active on, Test Mode off.' },
    { value: 'test', label: 'Test mode first', description: 'Only admins and testers see it. Real data, real guardrails.' },
    { value: 'inactive', label: 'Leave inactive', description: 'Mark setup complete, switch on later.' }
];

/*
Wizard step 7 - Review & Activate: everything the earlier steps saved, what needs a look, the go-live
choice (the wizard's Finish button acts on it) and the Try it panel. Fires edit { step }, golive { mode }.
*/
export default class AiWizardReview extends LightningElement {
    @api state;
    @api goLive = 'test';

    get hasWarnings() {
        return this.state && this.state.warnings && this.state.warnings.length > 0;
    }

    get warningCountLabel() {
        const count = this.state.warnings.length;
        return `${count} ${count === 1 ? 'thing' : 'things'} to look at.`;
    }

    get firstWarning() {
        const text = this.state.warnings[0];
        return text.endsWith('.') ? text : `${text}.`;
    }

    get sections() {
        const review = (this.state && this.state.review) || [];
        return review.map((section, index) => ({
            ...section,
            wrapperClass: index === review.length - 1 ? 'sum sum_last' : 'sum',
            dotClass: section.needsLook ? 'dot dot_warn' : 'dot',
            values: section.values.map((value) => ({ ...value, valueClass: section.needsLook && value.label === 'Needs a look' ? 'value_warn' : '' }))
        }));
    }

    get liveOptions() {
        return LIVE_OPTIONS.map((option) => {
            const checked = option.value === this.goLive;
            return { ...option, checked, cardClass: checked ? 'aic-option aic-option_selected' : 'aic-option' };
        });
    }

    // The wizard saves the current step before moving - nothing on this one needs saving.
    @api
    async save() {
        return this.state;
    }

    handleEdit(event) {
        event.preventDefault();
        this.dispatchEvent(new CustomEvent('edit', { detail: { step: Number(event.currentTarget.dataset.step) } }));
    }

    handleGoLive(event) {
        this.dispatchEvent(new CustomEvent('golive', { detail: { mode: event.target.value } }));
    }

    handleTryItState(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('statechange', { detail: event.detail }));
    }
}