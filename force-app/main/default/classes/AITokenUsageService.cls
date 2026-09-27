/*
Class Name: AITokenUsageService

=================================================================
=================================================================

Description: Read-only token usage figures - one query per method, no DML.

Every figure is summed from AIConversation__c.ConversationTokenUsage__c (kept up to date by
AIConversationMessageTriggerHandler), so it's one row per conversation rather than per message.
Date ranges filter on the conversation's CreatedDate - a conversation's tokens all count
towards the day it started - and are inclusive of both dates, in the running user's time zone.

Every method returns 0 rather than null when there's no usage.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-27     Chandler Stuart          Initial development
*/

public without sharing class AITokenUsageService {

    public class AITokenUsageServiceException extends Exception {}

    // Every conversation's tokens, across all users and Agents.
    public static Decimal getGlobalUsage(Date startDate, Date endDate) {
        try {

            Datetime rangeStart = toRangeStart(startDate, endDate);
            Datetime rangeEnd = toRangeEnd(endDate);

            AggregateResult[] results = [ SELECT SUM(ConversationTokenUsage__c) totalTokens
                                          FROM AIConversation__c
                                          WHERE CreatedDate >= :rangeStart AND CreatedDate < :rangeEnd ];

            return getTotalTokens(results);

        } catch (Exception ex) {
            throw ex instanceof AITokenUsageServiceException ? ex : new AITokenUsageServiceException('Failed to get global token usage: ' + ex.getMessage(), ex);
        }
    }

    // One conversation's running total.
    public static Decimal getConversationUsage(Id conversationId) {
        try {

            if (conversationId == null || conversationId.getSobjectType() != AIConversation__c.SObjectType) throw new AITokenUsageServiceException('A valid AI Conversation Id is required.');

            List<AIConversation__c> conversations = [ SELECT ConversationTokenUsage__c FROM AIConversation__c WHERE Id = :conversationId LIMIT 1 ];
            if (conversations.isEmpty()) throw new AITokenUsageServiceException('AI Conversation not found for Id: ' + conversationId);

            return conversations[0].ConversationTokenUsage__c == null ? 0 : conversations[0].ConversationTokenUsage__c;

        } catch (Exception ex) {
            throw ex instanceof AITokenUsageServiceException ? ex : new AITokenUsageServiceException('Failed to get conversation token usage: ' + ex.getMessage(), ex);
        }
    }

    // Tokens across every conversation with one Agent, whoever owns them.
    public static Decimal getAgentUsage(Id agentId, Date startDate, Date endDate) {
        try {

            if (agentId == null || agentId.getSobjectType() != AIAgent__c.SObjectType) throw new AITokenUsageServiceException('A valid AI Agent Id is required.');

            Datetime rangeStart = toRangeStart(startDate, endDate);
            Datetime rangeEnd = toRangeEnd(endDate);

            AggregateResult[] results = [ SELECT SUM(ConversationTokenUsage__c) totalTokens
                                          FROM AIConversation__c
                                          WHERE AIAgent__c = :agentId
                                          AND CreatedDate >= :rangeStart AND CreatedDate < :rangeEnd ];

            return getTotalTokens(results);

        } catch (Exception ex) {
            throw ex instanceof AITokenUsageServiceException ? ex : new AITokenUsageServiceException('Failed to get Agent token usage: ' + ex.getMessage(), ex);
        }
    }

    // Tokens across every conversation the user owns - the same ownership AIConversationMessageService's usage limits count by.
    public static Decimal getUserUsage(Id userId, Date startDate, Date endDate) {
        try {

            if (userId == null || userId.getSobjectType() != User.SObjectType) throw new AITokenUsageServiceException('A valid User Id is required.');

            Datetime rangeStart = toRangeStart(startDate, endDate);
            Datetime rangeEnd = toRangeEnd(endDate);

            AggregateResult[] results = [ SELECT SUM(ConversationTokenUsage__c) totalTokens
                                          FROM AIConversation__c
                                          WHERE OwnerId = :userId
                                          AND CreatedDate >= :rangeStart AND CreatedDate < :rangeEnd ];

            return getTotalTokens(results);

        } catch (Exception ex) {
            throw ex instanceof AITokenUsageServiceException ? ex : new AITokenUsageServiceException('Failed to get user token usage: ' + ex.getMessage(), ex);
        }
    }

    // Midnight at the start of startDate. Also checks the range, since every ranged method needs both dates.
    private static Datetime toRangeStart(Date startDate, Date endDate) {
        if (startDate == null || endDate == null) throw new AITokenUsageServiceException('A start date and an end date are required.');
        if (startDate > endDate) throw new AITokenUsageServiceException('The start date must be on or before the end date.');
        return Datetime.newInstance(startDate, Time.newInstance(0, 0, 0, 0));
    }

    // Midnight at the start of the day after endDate - queried with <, so all of endDate is included.
    private static Datetime toRangeEnd(Date endDate) {
        return Datetime.newInstance(endDate.addDays(1), Time.newInstance(0, 0, 0, 0));
    }

    // SUM returns one row with a null total when nothing matches.
    private static Decimal getTotalTokens(AggregateResult[] results) {
        Object totalTokens = results.isEmpty() ? null : results[0].get('totalTokens');
        return totalTokens == null ? 0 : (Decimal) totalTokens;
    }
}