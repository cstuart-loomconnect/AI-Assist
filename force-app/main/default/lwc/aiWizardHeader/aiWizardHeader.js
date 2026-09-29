import { LightningElement, api } from 'lwc';
import { WIZARD_STEPS, relativeTime } from 'c/aiConsoleUtils';

/*
The Agent Wizard's header: where you are, whether it's saved, and the seven-step path. A step can be
jumped to once it's been reached. Fires stepselect { step }, saveexit and agents.
*/
export default class AiWizardHeader extends LightningElement {
    @api state;
    @api step = 1;
    @api busy = false;

    get agentName() {
        return this.state && this.state.agentName ? this.state.agentName : 'New Agent';
    }

    get crumb() {
        return this.state && this.state.isSetupComplete ? 'Agent' : 'New Agent';
    }

    get statusLabel() {
        return (this.state && this.state.statusLabel) || 'Draft';
    }

    get savedLabel() {
        if (!this.state || !this.state.lastSaved) return null;
        return `Saved · ${relativeTime(this.state.lastSaved).replace(', ', ' ')}`;
    }

    get reachedStep() {
        if (!this.state || !this.state.agentId) return 1;
        return this.state.isSetupComplete ? WIZARD_STEPS.length : Math.max(this.state.setupStep || 1, this.step);
    }

    get steps() {
        return WIZARD_STEPS.map((label, index) => {
            const number = index + 1;
            const isCurrent = number === this.step;
            const isDone = !isCurrent && (number < this.reachedStep || (this.state && this.state.isSetupComplete));
            let buttonClass = 'chevron';
            if (isDone) buttonClass += ' chevron_done';
            if (isCurrent) buttonClass += ' chevron_current';
            return {
                number,
                label: `${number}. ${label}`,
                isDone,
                buttonClass,
                ariaCurrent: isCurrent ? 'step' : 'false',
                disabled: isCurrent || number > this.reachedStep || this.busy
            };
        });
    }

    handleStep(event) {
        this.dispatchEvent(new CustomEvent('stepselect', { detail: { step: Number(event.currentTarget.dataset.step) } }));
    }

    handleSaveExit() {
        this.dispatchEvent(new CustomEvent('saveexit'));
    }

    handleAgents(event) {
        event.preventDefault();
        this.dispatchEvent(new CustomEvent('agents'));
    }
}
