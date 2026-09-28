import { LightningElement, api } from 'lwc';
import { LABELS } from 'c/aiChatUtils';

const BADGE_CLASSES = {
    debug: 'badge badge_debug aia-mono',
    maintenance: 'badge badge_maintenance',
    off: 'badge badge_off'
};

// The chat window's top bar - logo, title, Agent picker and the New / History / More controls. Purely presentational: every click is reported to aiAssistChat as an event.
export default class AiChatHeader extends LightningElement {
    @api title = LABELS.appName;
    @api agentName;
    @api agentId;
    @api agents = [];
    @api showAgentLine = false;
    @api showNew = false;
    @api newDisabled = false;
    @api showHistory = false;
    @api menuItems = [];
    @api badge; // 'debug' | 'maintenance' | 'off'
    @api muted = false;

    labels = LABELS;
    isAgentMenuOpen = false;

    get logoClass() {
        return this.muted ? 'aia-logo aia-logo_muted' : 'aia-logo';
    }

    get logoStroke() {
        return this.muted ? '#6B6F7C' : '#FFFFFF';
    }

    get titleClass() {
        return this.muted ? 'title title_muted' : 'title';
    }

    get canSwitchAgent() {
        return Array.isArray(this.agents) && this.agents.length > 1;
    }

    get agentOptions() {
        return (this.agents || []).map((agent) => ({
            ...agent,
            isSelected: agent.id === this.agentId,
            checked: agent.id === this.agentId ? 'true' : 'false'
        }));
    }

    get agentMenuExpanded() {
        return this.isAgentMenuOpen ? 'true' : 'false';
    }

    get hasMenuItems() {
        return Array.isArray(this.menuItems) && this.menuItems.length > 0;
    }

    get newLabel() {
        return this.newDisabled ? LABELS.newConversationDisabled : LABELS.newConversation;
    }

    get badgeLabel() {
        if (this.badge === 'debug') return LABELS.debugBadge;
        if (this.badge === 'maintenance') return LABELS.maintenanceBadge;
        if (this.badge === 'off') return LABELS.inactiveBadge;
        return null;
    }

    get badgeClass() {
        return BADGE_CLASSES[this.badge] || 'badge';
    }

    get isDebugBadge() {
        return this.badge === 'debug';
    }

    toggleAgentMenu() {
        this.isAgentMenuOpen = !this.isAgentMenuOpen;
    }

    // Closes the Agent menu once focus leaves the picker entirely.
    handlePickerFocusOut(event) {
        const picker = this.template.querySelector('.agent-picker');
        if (picker && event.relatedTarget && picker.contains(event.relatedTarget)) return;
        this.isAgentMenuOpen = false;
    }

    handlePickerKeyDown(event) {
        if (event.key === 'Escape') this.isAgentMenuOpen = false;
    }

    handleAgentSelect(event) {
        const agentId = event.currentTarget.dataset.id;
        this.isAgentMenuOpen = false;
        if (agentId !== this.agentId) this.dispatchEvent(new CustomEvent('agentselect', { detail: { agentId } }));
    }

    handleNew() {
        this.dispatchEvent(new CustomEvent('newconversation'));
    }

    handleHistory() {
        this.dispatchEvent(new CustomEvent('openhistory'));
    }

    handleMenuSelect(event) {
        this.dispatchEvent(new CustomEvent('menuselect', { detail: { value: event.detail.value } }));
    }
}