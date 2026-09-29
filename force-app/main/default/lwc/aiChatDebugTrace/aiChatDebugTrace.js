import { LightningElement, api } from 'lwc';
import { LABELS, copyToClipboard, formatMilliseconds, downloadTextFile } from 'c/aiChatUtils';

// Debug mode's request trace for one AI reply (AIUserSettings__c.DebugModeEnabled__c) - loaded by aiAssistChat via AIChatController.getDebugTrace and handed down.
// "pii mappings" and "close trace" are handed back up as events - aiAssistChat owns the Apex calls and the trace state. requestJson/responseJson/sentPreviewText only carry a value for a reply captured with debug mode already on - an older reply, or one for a non-debug user, has none of it and the panel just omits that row.
export default class AiChatDebugTrace extends LightningElement {
    @api trace;
    @api errorMessage;

    labels = LABELS;
    copyLabel = LABELS.copyIds;

    get statusLabel() {
        return this.trace.isSuccess ? '200' : 'ERR';
    }

    get statusClass() {
        return this.trace.isSuccess ? 'status status_ok' : 'status status_error';
    }

    get durationLabel() {
        return formatMilliseconds(this.trace.durationMs);
    }

    get modelLabel() {
        const trace = this.trace;
        return [trace.provider, trace.modelConfiguration, trace.model].filter(Boolean).join(' · ') || '—';
    }

    get tokensLabel() {
        const format = (value) => (value === null || value === undefined ? '—' : Number(value).toLocaleString());
        return `${format(this.trace.promptTokens)} / ${format(this.trace.replyTokens)}`;
    }

    get piiLabel() {
        return `${this.trace.piiFieldsMasked} fields`;
    }

    get hasIterations() {
        return this.trace.toolCallingIterationsUsed !== null && this.trace.toolCallingIterationsUsed !== undefined;
    }

    get iterationsLabel() {
        return `${this.trace.toolCallingIterationsUsed} of ${this.trace.toolCallingIterationsMax}`;
    }

    get hasAttempts() {
        return this.trace.attemptNumber !== null && this.trace.attemptNumber !== undefined;
    }

    get hasSteps() {
        return this.trace.steps && this.trace.steps.length > 0;
    }

    get stepViews() {
        return this.trace.steps.map((step, index) => ({
            key: `${index}`,
            text: `${step.stepOrder || index + 1} · ${step.label}`,
            durationLabel: formatMilliseconds(step.durationMs),
            statusClass: step.isSuccess ? 'muted' : 'failed'
        }));
    }

    get hasSentPreview() {
        return !!this.trace.sentPreviewText;
    }

    get hasRequestJson() {
        return !!this.trace.requestJson;
    }

    get hasResponseJson() {
        return !!this.trace.responseJson;
    }

    async handleCopyIds() {
        const trace = this.trace;
        const ids = [
            `conversation: ${trace.conversationId}`,
            `conversationPublicId: ${trace.conversationPublicId}`,
            `userMessage: ${trace.userMessageId}`,
            `reply: ${trace.replyMessageId}`
        ].join('\n');
        const copied = await copyToClipboard(ids);
        this.copyLabel = copied ? LABELS.copied : LABELS.copyIds;
    }

    handleDownloadRequest() {
        downloadTextFile(`request-${this.trace.replyMessageId}.json`, this.trace.requestJson);
    }

    handleDownloadResponse() {
        downloadTextFile(`response-${this.trace.replyMessageId}.json`, this.trace.responseJson);
    }

    handleViewPiiMappings() {
        this.dispatchEvent(new CustomEvent('viewpiimappings'));
    }

    handleCloseTrace() {
        this.dispatchEvent(new CustomEvent('closetrace'));
    }
}