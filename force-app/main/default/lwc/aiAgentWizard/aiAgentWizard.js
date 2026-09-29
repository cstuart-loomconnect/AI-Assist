import { LightningElement, api } from 'lwc';
import getWizard from '@salesforce/apex/AIConsoleController.getWizard';
import goToWizardStep from '@salesforce/apex/AIConsoleController.goToWizardStep';
import finishWizard from '@salesforce/apex/AIConsoleController.finishWizard';
import { TABS, SECTIONS, VIEWS, WIZARD_STEPS, navigate, setLayout, refreshNav, reduceError, toast } from 'c/aiConsoleUtils';

const FINISH_LABELS = { test: 'Finish in test mode', activate: 'Finish and activate', inactive: 'Finish' };

/*
The Agent Wizard - every agent is built in the same seven steps. It has its own tab (AI Agent Wizard),
where it's the one Component section; the agent and step come from the URL (c__recordId, c__step) -
none means a brand-new agent. This shell owns the saved
WizardState (from AIConsoleWizardService) and moving between steps; each step component shows and
edits its part and exposes save(nextStep), which saves what's on screen and returns the new state.
Steps 2-5 also save as they go (toggles, Add selected), firing statechange.

The step is in the URL (c__step), so Back/refresh land on the same step; a brand-new agent gets its
Id in the URL once Basics is saved.
*/
export default class AiAgentWizard extends LightningElement {
    @api section;

    state;
    error;
    isLoading = true;
    busy = false;
    currentStep = 1;
    goLive;

    _agentId;
    @api
    get agentId() {
        return this._agentId;
    }
    set agentId(value) {
        this.showAgent(value);
    }

    @api
    get step() {
        return this.currentStep;
    }
    set step(value) {
        this.showStep(value);
    }

    // Set by aiTabPage from the URL. A new agent id or step moves the wizard there.
    _pageState = {};
    @api
    get pageState() {
        return this._pageState;
    }
    set pageState(value) {
        this._pageState = value || {};
        this.showStep(this._pageState.step);
        this.showAgent(this._pageState.recordId);
    }

    showAgent(value) {
        const changed = (value || null) !== (this._agentId || null);
        this._agentId = value || null;
        // A new agent saved on step 1 comes back with its Id - already loaded, nothing to fetch.
        if (changed && !(this.state && this.state.agentId === this._agentId)) this.load();
    }

    showStep(value) {
        const requested = Number(value) || 1;
        this.currentStep = Math.max(1, Math.min(WIZARD_STEPS.length, requested));
    }

    isLoadRequested = false;

    connectedCallback() {
        setLayout(this, { fullWidth: true });
        if (!this.state && !this.isLoadRequested) this.load();
    }

    async load() {
        this.isLoadRequested = true;
        this.isLoading = true;
        try {
            this.state = await getWizard({ agentId: this._agentId });
            // A new agent can only start on Basics.
            if (!this.state.agentId) this.currentStep = 1;
            this.goLive = this.goLive || (this.state.isSetupComplete && this.state.isActive && !this.state.isTestMode ? 'activate' : 'test');
            this.error = undefined;
        } catch (error) {
            this.error = reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // =============================================================
    // View
    // =============================================================

    get isStep1() {
        return this.currentStep === 1;
    }
    get isStep2() {
        return this.currentStep === 2;
    }
    get isStep3() {
        return this.currentStep === 3;
    }
    get isStep4() {
        return this.currentStep === 4;
    }
    get isStep5() {
        return this.currentStep === 5;
    }
    get isStep6() {
        return this.currentStep === 6;
    }
    get isStep7() {
        return this.currentStep === 7;
    }

    get isLastStep() {
        return this.currentStep === WIZARD_STEPS.length;
    }

    get showSummary() {
        return !this.isLastStep && !this.isLoading;
    }

    get hasBack() {
        return this.currentStep > 1;
    }

    get stepLabel() {
        return `Step ${this.currentStep} of ${WIZARD_STEPS.length}${this.currentStep === 4 ? ' · optional' : ''}`;
    }

    get nextLabel() {
        return `Next: ${WIZARD_STEPS[this.currentStep]}`;
    }

    get finishLabel() {
        return FINISH_LABELS[this.goLive] || 'Finish';
    }

    // =============================================================
    // Moving between steps
    // =============================================================

    handleNext() {
        this.moveTo(this.currentStep + 1);
    }

    handleBack() {
        this.moveTo(this.currentStep - 1);
    }

    handleStepSelect(event) {
        this.moveTo(Number(event.detail.step));
    }

    // Saves what the current step has on screen, then shows target.
    async moveTo(target) {
        if (this.busy) return;
        this.busy = true;
        this.error = undefined;
        try {
            const state = await this.saveCurrent(target);
            this.state = state;
            this.currentStep = target;
            // No section: staying in the section the wizard was opened from keeps this component mounted.
            navigate(this, { recordId: state.agentId, step: target, replace: true });
            window.scrollTo({ top: 0 });
        } catch (error) {
            this.error = reduceError(error);
        } finally {
            this.busy = false;
        }
    }

    async saveCurrent(nextStep) {
        const stepComponent = this.template.querySelector('.current-step');
        if (stepComponent && typeof stepComponent.save === 'function') return stepComponent.save(nextStep);
        return goToWizardStep({ agentId: this.state.agentId, nextStep });
    }

    handleStateChange(event) {
        this.state = event.detail.state;
    }

    handleGoLive(event) {
        this.goLive = event.detail.mode;
    }

    handleDismissError() {
        this.error = undefined;
    }

    async handleSaveExit() {
        if (this.busy) return;
        this.busy = true;
        this.error = undefined;
        try {
            const state = await this.saveCurrent(null);
            toast(this, 'Saved', `${state.agentName} is saved. Pick up where you left off any time.`);
            refreshNav(this);
            navigate(this, { tab: TABS.AGENTS, section: SECTIONS.AGENTS_ALL });
        } catch (error) {
            this.error = reduceError(error);
        } finally {
            this.busy = false;
        }
    }

    handleCancel() {
        navigate(this, { tab: TABS.AGENTS, section: SECTIONS.AGENTS_ALL });
    }

    async handleFinish() {
        if (this.busy) return;
        this.busy = true;
        this.error = undefined;
        try {
            this.state = await finishWizard({ agentId: this.state.agentId, mode: this.goLive });
            toast(this, 'Setup complete', `${this.state.agentName} · ${this.state.statusLabel}`);
            refreshNav(this);
            navigate(this, { tab: TABS.AGENTS, section: SECTIONS.AGENTS_ALL, view: VIEWS.RECORD, recordId: this.state.agentId });
        } catch (error) {
            this.error = reduceError(error);
        } finally {
            this.busy = false;
        }
    }
}
