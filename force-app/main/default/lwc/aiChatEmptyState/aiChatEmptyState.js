import { LightningElement, api } from 'lwc';
import { LABELS, getSuggestedCommands } from 'c/aiChatUtils';

// A new conversation - the Agent's greeting, up to three suggested commands for the record's object, and the PII reassurance banner.
export default class AiChatEmptyState extends LightningElement {
    @api greeting;
    @api recordName;
    @api objectLabel;
    @api objectLabelPlural;
    @api commands = [];
    @api piiProtected = false;
    @api disabled = false;

    labels = LABELS;
    isExplanationOpen = false;

    get greetingText() {
        if (this.greeting) return this.greeting;
        if (this.objectLabel) return `${LABELS.defaultGreeting} ${this.objectLabel.toLowerCase()}?`;
        return LABELS.defaultGreetingNoRecord;
    }

    get suggestions() {
        return getSuggestedCommands(this.commands);
    }

    get hasSuggestions() {
        return this.suggestions.length > 0;
    }

    get suggestionsHeading() {
        return this.objectLabelPlural ? `${LABELS.suggestedFor} ${this.objectLabelPlural}` : LABELS.commands;
    }

    get explanationExpanded() {
        return this.isExplanationOpen ? 'true' : 'false';
    }

    toggleExplanation() {
        this.isExplanationOpen = !this.isExplanationOpen;
    }

    handleSuggestion(event) {
        this.dispatchEvent(new CustomEvent('commandselect', { detail: { command: event.currentTarget.dataset.command } }));
    }
}