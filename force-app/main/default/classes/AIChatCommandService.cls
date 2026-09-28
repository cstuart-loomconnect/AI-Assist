/*
Class Name: AIChatCommandService

=================================================================
=================================================================

Description: Slash commands read from AIChatCommand__mdt - Agent by Developer Name, and limited
by AvailableTo__c to the running user's AI Assist User Type. Builds the commands offered in the
chat window and on the new-conversation screen (getAvailableCommands), and resolves the command
token typed in a message to its record (findCommand), so a command that isn't offered can't be
typed either.

Also owns splitting a message body into what the user sees vs. the command's hidden prompt
(getDisplayText / isCommandText / getCommandToken) - the same CHAT_COMMAND_PROMPT_SEPARATOR marker
AIChatController appends when sending a command, so the mechanics of "is this text a command" and
"what should be shown for it" stay next to the mdt rules that decide which commands exist.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-28     Chandler Stuart          Split out of AIChatController.
*/

public with sharing class AIChatCommandService {

    // Test-only stand-in for the AIChatCommand__mdt records - Custom Metadata records can't be inserted in a test.
    @TestVisible private static List<AIChatCommand__mdt> testCommands;

    // The commands this user can use here - listed in the chat window and on the new-conversation screen.
    public static List<AIChatDataStructure.CommandOption> getAvailableCommands(Id agentId, AIChatDataStructure.RecordContext record) {

        List<AIChatDataStructure.CommandOption> commands = new List<AIChatDataStructure.CommandOption>();

        for (AIChatCommand__mdt command : getUsableCommands(agentId, record.objectApiName)) {

            AIChatDataStructure.CommandOption option = new AIChatDataStructure.CommandOption();
            option.id = command.Id;
            option.command = command.Command__c;
            option.description = command.Description__c;
            option.isRecordSpecific = String.isNotBlank(command.ObjectAPIName__c);
            option.scopeLabel = option.isRecordSpecific ? (record.objectLabel == null ? command.ObjectAPIName__c : record.objectLabel) : 'Any record';

            commands.add(option);
        }

        return commands;
    }

    // The command typed, if this user can use it here - the same rules as the list, so a command that isn't offered can't be typed either.
    public static AIChatCommand__mdt findCommand(String commandToken, Id agentId, String objectApiName) {

        for (AIChatCommand__mdt command : getUsableCommands(agentId, objectApiName)) {
            if (command.Command__c == commandToken) return command;
        }

        return null;
    }

    // Active AIChatCommand__mdt records for this object (or any), this Agent (or any) and the running user's AI Assist User Type, lowest DisplayOrder__c first.
    // Filtered and sorted here rather than in the query, so a test's in-memory records go through the same rules. Queried with SOQL, not getAll(), since getAll() cuts PromptText__c (a Long Text Area) off at 255 characters.
    private static List<AIChatCommand__mdt> getUsableCommands(Id agentId, String objectApiName) {

        List<AIChatCommand__mdt> allCommands = testCommands != null ? testCommands : [ SELECT Id, DeveloperName, Command__c, Description__c, PromptText__c, ObjectAPIName__c, AgentDeveloperName__c, AvailableTo__c, IsActive__c, DisplayOrder__c
                                                                                        FROM AIChatCommand__mdt ];

        List<AIAgent__c> agents = [ SELECT DeveloperName__c FROM AIAgent__c WHERE Id = :agentId LIMIT 1 ];
        String agentDeveloperName = agents.isEmpty() ? null : agents[0].DeveloperName__c;

        String userType = [ SELECT AIAssistUserType__c FROM User WHERE Id = :UserInfo.getUserId() ].AIAssistUserType__c;

        List<AIChatCommand__mdt> usableCommands = new List<AIChatCommand__mdt>();

        for (AIChatCommand__mdt command : allCommands) {
            if (command.IsActive__c != true || String.isBlank(command.Command__c)) continue;
            if (String.isNotBlank(command.ObjectAPIName__c) && command.ObjectAPIName__c != objectApiName) continue;
            if (String.isNotBlank(command.AgentDeveloperName__c) && command.AgentDeveloperName__c != agentDeveloperName) continue;
            if (!isCommandAvailableToUserType(command.AvailableTo__c, userType)) continue;
            usableCommands.add(command);
        }

        usableCommands.sort(new CommandDisplayOrder());
        return usableCommands;
    }

    // AvailableTo__c levels each include the ones above them. A blank value, like All Users, is open to everyone; a user with no AI Assist User Type only gets All Users commands.
    @TestVisible private static Boolean isCommandAvailableToUserType(String availableTo, String userType) {

        if (availableTo == AIAssistApplicationConstants.CHAT_COMMAND_AVAILABLE_TO_ADMINS_ONLY) return userType == AIAssistApplicationConstants.USER_TYPE_ADMIN;

        if (availableTo == AIAssistApplicationConstants.CHAT_COMMAND_AVAILABLE_TO_SUPER_USERS_AND_ADMINS) {
            return userType == AIAssistApplicationConstants.USER_TYPE_ADMIN || userType == AIAssistApplicationConstants.USER_TYPE_SUPER_USER;
        }

        return true;
    }

    // Lowest DisplayOrder__c first, blank last, then by command.
    private class CommandDisplayOrder implements Comparator<AIChatCommand__mdt> {
        public Integer compare(AIChatCommand__mdt first, AIChatCommand__mdt second) {

            if (first.DisplayOrder__c != second.DisplayOrder__c) {
                if (first.DisplayOrder__c == null) return 1;
                if (second.DisplayOrder__c == null) return -1;
                return first.DisplayOrder__c < second.DisplayOrder__c ? -1 : 1;
            }

            return first.Command__c.compareTo(second.Command__c);
        }
    }

    // The part of a message body the user sees - everything before a command's hidden instructions.
    public static String getDisplayText(String messageBody) {

        if (String.isBlank(messageBody)) return '';

        Integer separatorIndex = messageBody.indexOf(AIAssistApplicationConstants.CHAT_COMMAND_PROMPT_SEPARATOR);
        return separatorIndex < 0 ? messageBody : messageBody.left(separatorIndex);
    }

    public static Boolean isCommandText(String text) {
        return String.isNotBlank(text) && Pattern.matches(AIAssistApplicationConstants.CHAT_COMMAND_PATTERN, text.trim());
    }

    public static String getCommandToken(String text) {
        return text.trim().split('\\s', 2)[0];
    }
}
