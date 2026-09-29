/*
Shared helpers for the AI Assist console components. Everything a console component needs that
isn't specific to it: the tab / section Developer Names it links to (matching the seeded
AINavTab__mdt / AINavTabSection__mdt records and AIConsoleConstants), the navigation event aiTabPage
listens for, error text, badge classes, number formatting and CSV export.
*/
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export const TABS = {
    HOME: 'AI_Home',
    AGENTS: 'AI_Agents',
    AGENT_WIZARD: 'AI_Agent_Wizard',
    LIBRARY: 'AI_Library',
    ACTIVITY: 'AI_Activity',
    SETTINGS: 'AI_Settings',
    RECORD: 'record' // A Salesforce record page, not a console tab.
};

export const SECTIONS = {
    AGENTS_ALL: 'Agents_All',
    AGENTS_DRAFTS: 'Agents_Drafts',
    LIBRARY_MODELS: 'Library_Model_Configurations',
    LIBRARY_DATA_SOURCES: 'Library_Data_Sources',
    LIBRARY_ACTIONS: 'Library_Workflow_Actions',
    ACTIVITY_CONVERSATIONS: 'Activity_Conversations',
    ACTIVITY_VIOLATIONS: 'Activity_Violations',
    ACTIVITY_FEEDBACK: 'Activity_Feedback',
    ACTIVITY_ERROR_LOG: 'Activity_Error_Log',
    SETTINGS_APP: 'Settings_App',
    SETTINGS_UI: 'Settings_UI',
    SETTINGS_USERS: 'Settings_Users',
    SETTINGS_TERMS: 'Settings_Terms',
    SETTINGS_PII: 'Settings_PII'
};

export const VIEWS = {
    RECORD: 'record',
    WIZARD: 'wizard',
    NEW: 'new'
};

export const WIZARD_STEPS = ['Basics', 'Prompt Templates', 'Data Sources', 'Workflow Actions', 'Guardrails', 'Conversation Rules', 'Review & Activate'];

export const NAVIGATE_EVENT = 'consolenavigate';
export const PAGE_STATE_EVENT = 'consolepagestate';
export const LAYOUT_EVENT = 'consolelayout';
export const REFRESH_EVENT = 'consolerefresh';

// Asks aiTabPage to go somewhere: { tab, section, view, recordId, step }. Leave tab out to stay on this tab.
export function navigate(component, target) {
    component.dispatchEvent(new CustomEvent(NAVIGATE_EVENT, { bubbles: true, composed: true, detail: { ...target } }));
}

// Shares page state that isn't in the URL (e.g. Home's date range) with every section on the page.
export function setPageState(component, changes) {
    component.dispatchEvent(new CustomEvent(PAGE_STATE_EVENT, { bubbles: true, composed: true, detail: { ...changes } }));
}

// The Agent Wizard's own tab. No agentId starts a new agent; step opens that step (once reached).
export function openWizard(component, agentId, step, replace = false) {
    navigate(component, { tab: TABS.AGENT_WIZARD, recordId: agentId || null, step: step || 1, replace });
}

// fullWidth hides the Sub Navigation rail and the page padding - the Agent Wizard uses it.
export function setLayout(component, layout) {
    component.dispatchEvent(new CustomEvent(LAYOUT_EVENT, { bubbles: true, composed: true, detail: { ...layout } }));
}

// Something changed that the rail's counts depend on.
export function refreshNav(component) {
    component.dispatchEvent(new CustomEvent(REFRESH_EVENT, { bubbles: true, composed: true }));
}

export function toast(component, title, message, variant = 'success') {
    component.dispatchEvent(new ShowToastEvent({ title, message, variant }));
}

export function reduceError(error) {
    if (!error) return 'Something went wrong.';
    if (typeof error === 'string') return error;
    if (Array.isArray(error.body)) return error.body.map((entry) => entry.message).join(', ');
    if (error.body && typeof error.body.message === 'string') return error.body.message;
    if (typeof error.message === 'string') return error.message;
    return 'Something went wrong.';
}

export function badgeClass(variant) {
    return variant ? `aic-badge aic-badge_${variant}` : 'aic-badge';
}

export function formatNumber(value) {
    if (value === null || value === undefined || value === '') return '—';
    return Number(value).toLocaleString(undefined, { maximumFractionDigits: 0 });
}

// "16.9k" / "1.2M"
export function compactNumber(value) {
    const number = Number(value || 0);
    if (number >= 1000000) return `${(number / 1000000).toFixed(1).replace(/\.0$/, '')}M`;
    if (number >= 1000) return `${(number / 1000).toFixed(1).replace(/\.0$/, '')}k`;
    return formatNumber(number);
}

// "1,204" typed into a number box -> 1204. Blank stays null.
export function parseNumber(value) {
    if (value === null || value === undefined) return null;
    const cleaned = String(value).replace(/,/g, '').trim();
    if (cleaned === '') return null;
    const number = Number(cleaned);
    return Number.isNaN(number) ? null : number;
}

// "Opportunity Deal Coach" -> "Opportunity_Deal_Coach", the same rule AIAssistGlobalUtility uses.
export function toDeveloperName(name) {
    return (name || '')
        .trim()
        .replace(/[^a-zA-Z0-9]+/g, '_')
        .replace(/^_+|_+$/g, '');
}

export function relativeTime(dateValue) {
    if (!dateValue) return '';
    const date = new Date(dateValue);
    const now = new Date();
    const time = date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', hour12: false });
    const sameDay = date.toDateString() === now.toDateString();
    const yesterday = new Date(now.getTime() - 86400000).toDateString() === date.toDateString();
    if (sameDay) return `Today, ${time}`;
    if (yesterday) return `Yesterday, ${time}`;
    return date.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
}

export function shortDate(dateValue) {
    if (!dateValue) return '';
    const date = new Date(dateValue);
    const now = new Date();
    if (date.toDateString() === now.toDateString()) return 'today';
    return date.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
}

export function debounce(callback, waitMs) {
    let timer;
    return (...args) => {
        clearTimeout(timer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        timer = setTimeout(() => callback(...args), waitMs);
    };
}

export function clone(value) {
    return value === undefined ? undefined : JSON.parse(JSON.stringify(value));
}

// Downloads rows as a CSV file in the browser - Export on the Conversations and Error Log lists.
export function downloadCsv(fileName, headers, rows) {
    const escape = (value) => {
        const text = value === null || value === undefined ? '' : String(value);
        return /[",\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
    };
    const lines = [headers.map(escape).join(',')].concat(rows.map((row) => row.map(escape).join(',')));
    const link = document.createElement('a');
    link.href = `data:text/csv;charset=utf-8,${encodeURIComponent(lines.join('\n'))}`;
    link.download = fileName;
    link.style.display = 'none';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
}