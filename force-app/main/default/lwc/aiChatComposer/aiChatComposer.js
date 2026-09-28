import { LightningElement, api } from 'lwc';
import { LABELS, filterCommands, isTypingCommand } from 'c/aiChatUtils';

// The message box - typing, the slash-command menu, Send / Stop, and the footnote with the usage meter. Enter sends, Shift+Enter adds a line; while the menu is open the arrow keys move and Enter/Tab picks.
export default class AiChatComposer extends LightningElement {
    @api commands = [];
    @api disabled = false;
    @api isWorking = false;
    @api placeholder = LABELS.composerPlaceholder;
    @api footerText = LABELS.disclaimer;
    @api usageLabel;
    @api usageOver = false;
    @api errorText;
    @api maxLength = 32000;

    labels = LABELS;
    text = '';
    activeIndex = 0;
    isMenuDismissed = false;

    // Parent -> child: puts text in the box (Edit message, a suggested command) and focuses it.
    @api
    setText(value) {
        this.text = value || '';
        this.isMenuDismissed = false;
        this.activeIndex = 0;
        const input = this.input;
        if (input) {
            input.value = this.text;
            input.focus();
            input.setSelectionRange(this.text.length, this.text.length);
        }
        this.notifyMenu();
    }

    @api
    clear() {
        this.setText('');
    }

    @api
    focus() {
        if (this.input) this.input.focus();
    }

    get input() {
        return this.template.querySelector('textarea');
    }

    get hasCommands() {
        return Array.isArray(this.commands) && this.commands.length > 0;
    }

    get matches() {
        return filterCommands(this.commands, this.text);
    }

    get hasMatches() {
        return this.matches.length > 0;
    }

    get isMenuOpen() {
        return this.hasCommands && !this.isMenuDismissed && !this.isInputDisabled && isTypingCommand(this.text);
    }

    get menuExpanded() {
        return this.isMenuOpen ? 'true' : 'false';
    }

    get matchViews() {
        return this.matches.map((command, index) => {
            const selected = index === this.activeIndex;
            return {
                ...command,
                index,
                optionId: `command-option-${index}`,
                selected: selected ? 'true' : 'false',
                className: selected ? 'option option_active' : 'option',
                scopeClass: selected ? 'scope scope_active' : 'scope'
            };
        });
    }

    // LWC scopes dynamic ids and the aria idrefs that point at them the same way, so the plain id matches.
    get activeOptionId() {
        return this.isMenuOpen && this.hasMatches ? `command-option-${this.activeIndex}` : null;
    }

    get isInputDisabled() {
        return this.disabled || this.isWorking;
    }

    get isSendDisabled() {
        return this.isInputDisabled || !this.text.trim();
    }

    get effectivePlaceholder() {
        return this.isWorking ? LABELS.composerPlaceholderWorking : this.placeholder;
    }

    get boxClass() {
        if (this.isWorking || this.disabled) return 'box box_disabled';
        return this.isMenuOpen ? 'box box_focused' : 'box';
    }

    get slashClass() {
        return this.isMenuOpen ? 'slash slash_active aia-mono' : 'slash aia-mono';
    }

    get sendClass() {
        return this.isSendDisabled ? 'send send_disabled' : 'send';
    }

    get usageClass() {
        return this.usageOver ? 'aia-mono usage usage_over' : 'aia-mono usage';
    }

    handleInput(event) {
        this.text = event.target.value;
        this.isMenuDismissed = false;
        this.activeIndex = 0;
        this.notifyMenu();
    }

    handleKeyDown(event) {
        if (this.isMenuOpen && this.hasMatches) {
            if (event.key === 'ArrowDown') {
                event.preventDefault();
                this.activeIndex = (this.activeIndex + 1) % this.matches.length;
                return;
            }
            if (event.key === 'ArrowUp') {
                event.preventDefault();
                this.activeIndex = (this.activeIndex - 1 + this.matches.length) % this.matches.length;
                return;
            }
            if ((event.key === 'Enter' && !event.shiftKey) || event.key === 'Tab') {
                event.preventDefault();
                this.pickCommand(this.matches[this.activeIndex]);
                return;
            }
        }
        if (this.isMenuOpen && event.key === 'Escape') {
            event.preventDefault();
            this.isMenuDismissed = true;
            this.notifyMenu();
            return;
        }
        if (event.key === 'Enter' && !event.shiftKey && !event.isComposing) {
            event.preventDefault();
            this.send();
        }
    }

    handleBlur() {
        this.isMenuDismissed = true;
        this.notifyMenu();
    }

    // Keeps focus in the textarea while clicking inside the menu.
    preventBlur(event) {
        event.preventDefault();
    }

    handleCommandClick(event) {
        this.pickCommand(this.matches[Number(event.currentTarget.dataset.index)]);
    }

    handleCommandHover(event) {
        this.activeIndex = Number(event.currentTarget.dataset.index);
    }

    handleSlash() {
        this.setText(this.text && !this.text.startsWith('/') ? `/${this.text}` : this.text || '/');
    }

    handleSendClick() {
        this.send();
    }

    handleStop() {
        this.dispatchEvent(new CustomEvent('stop'));
    }

    pickCommand(command) {
        if (command) this.setText(`${command.command} `);
    }

    send() {
        const text = this.text.trim();
        if (!text || this.isInputDisabled) return;
        this.dispatchEvent(new CustomEvent('send', { detail: { text } }));
    }

    notifyMenu() {
        this.dispatchEvent(new CustomEvent('menutoggle', { detail: { open: this.isMenuOpen } }));
    }
}