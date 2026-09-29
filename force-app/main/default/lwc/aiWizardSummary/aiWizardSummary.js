import { LightningElement, api } from 'lwc';
import { WIZARD_STEPS } from 'c/aiConsoleUtils';

/*
The Agent Wizard's right-hand rail. Setup progress shows each step's saved summary once it's done;
Ready to activate? shows each check once the wizard has reached the step it belongs to.
*/
export default class AiWizardSummary extends LightningElement {
    @api state;
    @api step = 1;

    get isComplete() {
        return !!(this.state && this.state.isSetupComplete);
    }

    get reachedStep() {
        if (!this.state || !this.state.agentId) return this.step;
        return this.isComplete ? WIZARD_STEPS.length + 1 : Math.max(this.state.setupStep || 1, this.step);
    }

    get doneCount() {
        return this.isComplete ? WIZARD_STEPS.length : Math.max(0, this.reachedStep - 1);
    }

    get doneLabel() {
        return `${this.doneCount} of ${WIZARD_STEPS.length} done`;
    }

    get barStyle() {
        return `width: ${Math.round((this.doneCount / WIZARD_STEPS.length) * 100)}%`;
    }

    get items() {
        const summary = (this.state && this.state.summary) || [];
        return WIZARD_STEPS.map((label, index) => {
            const number = index + 1;
            const isCurrent = number === this.step;
            const isDone = !isCurrent && (this.isComplete || number < this.reachedStep);
            let value = 'Not started';
            if (isCurrent) value = 'In progress';
            else if (isDone) value = summary[index] ? summary[index].value : '';

            let dotClass = 'dot';
            if (isDone) dotClass += ' dot_done';
            if (isCurrent) dotClass += ' dot_current';

            return { number, label, value, isDone, dotClass, rowClass: isCurrent ? 'item item_current' : 'item' };
        });
    }

    get checks() {
        const checks = (this.state && this.state.checks) || [];
        return checks.map((check, index) => {
            const reached = this.isComplete || this.reachedStep >= check.step;
            const isOk = reached && check.state === 'ok';
            const isWarn = reached && check.state === 'warn';
            return {
                key: `check-${index}`,
                text: check.text,
                isOk,
                isWarn,
                markClass: isOk ? 'mark mark_ok' : isWarn ? 'mark mark_warn' : 'mark',
                textClass: !reached ? 'check__text check__text_pending' : isWarn ? 'check__text check__text_warn' : 'check__text'
            };
        });
    }
}