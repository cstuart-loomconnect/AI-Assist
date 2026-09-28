import { LightningElement, api } from 'lwc';
import { LABELS } from 'c/aiChatUtils';

// While a reply is being generated: the step card (AIAssistUISettings__c.ShowExecutionTraceToUser__c on) or the lighter typing indicator.
export default class AiChatWorkingIndicator extends LightningElement {
    @api mode = 'typing'; // 'steps' | 'typing'
    @api label;
    @api elapsedLabel;
    @api steps = []; // [{ label, state: 'done' | 'active' | 'pending' }]

    labels = LABELS;

    get isSteps() {
        return this.mode === 'steps';
    }

    get stepViews() {
        return (this.steps || []).map((step, index) => ({
            key: `${index}-${step.label}`,
            label: step.label,
            isDone: step.state === 'done',
            isActive: step.state === 'active',
            className: `step step_${step.state}`
        }));
    }
}