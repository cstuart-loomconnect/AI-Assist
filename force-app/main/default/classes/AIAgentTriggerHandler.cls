/*
Class Name: AIAgentTriggerHandler

=================================================================
=================================================================

Description: Handler for managing AI Agent events related to AI Assist. Generates
PublicId__c when blank on insert, and regenerates DeveloperName__c from Name whenever
Name changes.

=================================================================
=================================================================

Version      Date            Author                   Description
1.0          2026-09-05      Chandler Stuart          Initial development
*/

public without sharing class AIAgentTriggerHandler {

    private static Boolean isBeforeInsertHandlerRunning = false;
    private static Boolean isBeforeUpdateHandlerRunning = false;

    public static void handleBeforeInsert(List<AIAgent__c> newAgents) {
        try {

            if (!isBeforeInsertHandlerRunning) {

                isBeforeInsertHandlerRunning = true;

                AIAssistGlobalUtility.generatePublicId(newAgents);
                AIAssistGlobalUtility.generateDeveloperName(newAgents);

            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIAgentTriggerHandler', 'handleBeforeInsert');
        }
    }

    public static void handleBeforeUpdate(Map<Id, AIAgent__c> oldAgentsById, Map<Id, AIAgent__c> newAgentsById) {
        try {

            if (!isBeforeUpdateHandlerRunning) {

                isBeforeUpdateHandlerRunning = true;

                if (newAgentsById == null || newAgentsById.isEmpty() || oldAgentsById == null) return;

                List<AIAgent__c> agentsWithNameChange = new List<AIAgent__c>(); // Agents whose Name changed and need DeveloperName__c regenerated.

                for (AIAgent__c newAgent : newAgentsById.values()) {

                    AIAgent__c oldAgent = oldAgentsById.get(newAgent.Id);
                    if (oldAgent == null) continue;

                    if (oldAgent.Name == newAgent.Name) continue; // No change in Name, skip to next agent.

                    newAgent.DeveloperName__c = null; // Clear so generateDeveloperName regenerates it from the new Name.
                    agentsWithNameChange.add(newAgent);

                }

                if (!agentsWithNameChange.isEmpty()) { AIAssistGlobalUtility.generateDeveloperName(agentsWithNameChange); }

            }

        } catch (Exception e) {
            AIPlatformLogManager.logException(e, 'AIAgentTriggerHandler', 'handleBeforeUpdate');
        }
    }
}