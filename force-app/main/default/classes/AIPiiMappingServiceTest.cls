/*
Class Name: AIPiiMappingServiceTest

=================================================================
=================================================================

Description: Testing utility for the AIPiiMappingService storage layer.

=================================================================
=================================================================
Applicable Classes:

AIPiiMappingService: Coverage 100%

Version      Date               Author                   Description
1.0          2026-09-15         Chandler Stuart          Initial development
1.1          2026-09-27         Chandler Stuart          Deferred-write scenarios.
*/

@IsTest private class AIPiiMappingServiceTest {

    // testScenario1: getMapping returns an empty map when no mapping record exists yet for the conversation.
    // testScenario2: addMapping creates the mapping record, and getMapping/getFakeValueForRealValue/getRealValueForFakeValue reflect the new pairing without a re-query.
    // testScenario3: addMapping for a real value that's already mapped is a no-op - the stored fake value doesn't change and no extra record is created.
    // testScenario4: addMapping for a second real value appends to the same mapping record rather than creating a new one.
    // testScenario5: While deferring, addMapping on a new conversation does no DML but is readable from the cache - processCachedPIIMappings then inserts one record holding every pairing, and a second save is a no-op.
    // testScenario6: While deferring, addMapping on a conversation with an existing record does no DML - processCachedPIIMappings updates that same record rather than inserting another, and writes are immediate again once the flag is set back to false.

    private static Id createConversationId() {
        Id agentId = AIAssistTestDataFactory.createAIAgents(1, true)[0].Id;
        return AIAssistTestDataFactory.createAIConversations(agentId, 1, true)[0].Id;
    }

    @IsTest static void testScenario1() {

        Id conversationId = createConversationId();

        Test.startTest();
            Map<String, String> mapping = AIPiiMappingService.getMapping(conversationId);
        Test.stopTest();

        Assert.isTrue(mapping.isEmpty(), 'getMapping should return an empty map when no mapping record exists yet.');
    }

    @IsTest static void testScenario2() {

        Id conversationId = createConversationId();

        Test.startTest();
            AIPiiMappingService.addMapping(conversationId, 'Jane Doe', 'Alex Rivera');
        Test.stopTest();

        Assert.areEqual('Alex Rivera', AIPiiMappingService.getFakeValueForRealValue(conversationId, 'Jane Doe'), 'The fake value should be retrievable by real value.');
        Assert.areEqual('Jane Doe', AIPiiMappingService.getRealValueForFakeValue(conversationId, 'Alex Rivera'), 'The real value should be retrievable by fake value.');

        Integer mappingCount = [SELECT COUNT() FROM AIPIIMapping__c WHERE AIConversation__c = :conversationId];
        Assert.areEqual(1, mappingCount, 'A first mapping should create exactly one mapping record.');
    }

    @IsTest static void testScenario3() {

        Id conversationId = createConversationId();
        AIPiiMappingService.addMapping(conversationId, 'Jane Doe', 'Alex Rivera');

        Test.startTest();
            AIPiiMappingService.addMapping(conversationId, 'Jane Doe', 'Someone Else');
        Test.stopTest();

        Assert.areEqual('Alex Rivera', AIPiiMappingService.getFakeValueForRealValue(conversationId, 'Jane Doe'), 'Re-adding an already-mapped real value should not change its stored fake value.');

        Integer mappingCount = [SELECT COUNT() FROM AIPIIMapping__c WHERE AIConversation__c = :conversationId];
        Assert.areEqual(1, mappingCount, 'Re-adding an already-mapped real value should not create an extra mapping record.');
    }

    @IsTest static void testScenario4() {

        Id conversationId = createConversationId();
        AIPiiMappingService.addMapping(conversationId, 'Jane Doe', 'Alex Rivera');

        Test.startTest();
            AIPiiMappingService.addMapping(conversationId, 'John Smith', 'Jordan Chen');
        Test.stopTest();

        Integer mappingCount = [SELECT COUNT() FROM AIPIIMapping__c WHERE AIConversation__c = :conversationId];
        Assert.areEqual(1, mappingCount, 'A second pairing for the same conversation should append to the existing mapping record.');

        Map<String, String> mapping = AIPiiMappingService.getMapping(conversationId);
        Assert.areEqual(2, mapping.size(), 'Both pairings should be present in the mapping.');
        Assert.areEqual('Alex Rivera', mapping.get('Jane Doe'), 'The first pairing should still be present.');
        Assert.areEqual('Jordan Chen', mapping.get('John Smith'), 'The second pairing should be present.');
    }

    @IsTest static void testScenario5() {

        Id conversationId = createConversationId();
        Integer countWhileDeferred;

        Test.startTest();
            AIPiiMappingService.isDeferringWrites = true;
            AIPiiMappingService.addMapping(conversationId, 'Jane Doe', 'Alex Rivera');
            AIPiiMappingService.addMapping(conversationId, 'John Smith', 'Jordan Chen');
            countWhileDeferred = [SELECT COUNT() FROM AIPIIMapping__c WHERE AIConversation__c = :conversationId];
            Assert.areEqual('Jane Doe', AIPiiMappingService.getRealValueForFakeValue(conversationId, 'Alex Rivera'), 'A deferred pairing should still be readable from the cache.');
            AIPiiMappingService.isDeferringWrites = false;
            AIPiiMappingService.processCachedPIIMappings();
            AIPiiMappingService.processCachedPIIMappings(); // Nothing pending - should be a harmless no-op.
        Test.stopTest();

        Assert.areEqual(0, countWhileDeferred, 'No mapping record should be written while deferring.');

        List<AIPIIMapping__c> saved = [SELECT MappingJson__c FROM AIPIIMapping__c WHERE AIConversation__c = :conversationId];
        Assert.areEqual(1, saved.size(), 'processCachedPIIMappings should insert exactly one record for the conversation.');
        Map<String, Object> savedPairs = (Map<String, Object>) JSON.deserializeUntyped(saved[0].MappingJson__c);
        Assert.areEqual(2, savedPairs.size(), 'Both deferred pairings should be saved.');
        Assert.areEqual('Jordan Chen', savedPairs.get('John Smith'), 'The saved JSON should carry each pairing.');
    }

    @IsTest static void testScenario6() {

        Id conversationId = createConversationId();
        AIPiiMappingService.addMapping(conversationId, 'Jane Doe', 'Alex Rivera'); // Written immediately - not deferring yet.
        Id existingMappingId = [SELECT Id FROM AIPIIMapping__c WHERE AIConversation__c = :conversationId].Id;
        String jsonWhileDeferred;

        Test.startTest();
            AIPiiMappingService.isDeferringWrites = true;
            AIPiiMappingService.addMapping(conversationId, 'John Smith', 'Jordan Chen');
            jsonWhileDeferred = [SELECT MappingJson__c FROM AIPIIMapping__c WHERE Id = :existingMappingId].MappingJson__c;
            AIPiiMappingService.isDeferringWrites = false;
            AIPiiMappingService.processCachedPIIMappings();
            AIPiiMappingService.addMapping(conversationId, 'Sam Lee', 'Casey Park'); // No longer deferring - written immediately.
        Test.stopTest();

        Assert.isFalse(jsonWhileDeferred.contains('John Smith'), 'The existing record should not be updated while deferring.');

        List<AIPIIMapping__c> saved = [SELECT Id, MappingJson__c FROM AIPIIMapping__c WHERE AIConversation__c = :conversationId];
        Assert.areEqual(1, saved.size(), 'processCachedPIIMappings should update the existing record, not insert another.');
        Assert.areEqual(existingMappingId, saved[0].Id, 'The original mapping record should be the one updated.');
        Map<String, Object> savedPairs = (Map<String, Object>) JSON.deserializeUntyped(saved[0].MappingJson__c);
        Assert.areEqual(3, savedPairs.size(), 'The original, deferred and post-save pairings should all be stored.');
    }
}