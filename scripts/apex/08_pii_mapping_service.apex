// Run with: SFDX: Execute Anonymous Apex with Editor Contents
// Exercises AIPiiMappingService end to end: creates a throwaway AIConversation__c, adds a few
// real/fake PII pairings, then reads them back through the forward and reverse lookups.
// Also verifies the AIPIIMapping__c row's MappingJson__c persists correctly and that
// re-adding an already-mapped real value is a no-op.

AIConversation__c conversation = new AIConversation__c(
    Channel__c = 'Record Page Chat',
    Status__c = 'Active'
);
insert conversation;
System.debug('Created test Conversation: ' + conversation.Id);

// Add a couple of PII mappings and confirm the calls report success.
Boolean added1 = AIPiiMappingService.addMapping(conversation.Id, 'john.doe@acme.com', 'fake.user1@example.com');
Boolean added2 = AIPiiMappingService.addMapping(conversation.Id, '555-123-4567', '555-000-0001');
System.debug('addMapping (email) returned: ' + added1);
System.debug('addMapping (phone) returned: ' + added2);

// Re-adding the same real value should no-op and return false.
Boolean addedDuplicate = AIPiiMappingService.addMapping(conversation.Id, 'john.doe@acme.com', 'a-different-fake-value@example.com');
System.debug('addMapping (duplicate real value) returned (expect false): ' + addedDuplicate);

// Forward lookups: real value -> fake value.
System.debug('getFakeValueForRealValue(email) (expect fake.user1@example.com): ' + AIPiiMappingService.getFakeValueForRealValue(conversation.Id, 'john.doe@acme.com'));
System.debug('getFakeValueForRealValue(phone) (expect 555-000-0001): ' + AIPiiMappingService.getFakeValueForRealValue(conversation.Id, '555-123-4567'));
System.debug('getFakeValueForRealValue(unknown) (expect null): ' + AIPiiMappingService.getFakeValueForRealValue(conversation.Id, 'no-such-value'));

// Reverse lookups: fake value -> real value.
System.debug('getRealValueForFakeValue(email) (expect john.doe@acme.com): ' + AIPiiMappingService.getRealValueForFakeValue(conversation.Id, 'fake.user1@example.com'));
System.debug('getRealValueForFakeValue(phone) (expect 555-123-4567): ' + AIPiiMappingService.getRealValueForFakeValue(conversation.Id, '555-000-0001'));

// Full mapping for the conversation.
System.debug('getMapping (expect 2 entries): ' + AIPiiMappingService.getMapping(conversation.Id));

// Confirm exactly one AIPIIMapping__c row exists for the conversation (no LIMIT 1 here -
// a regression that re-inserts instead of updating on a second pairing would still show up).
List<AIPIIMapping__c> mappingRecords = [SELECT Id, MappingJson__c FROM AIPIIMapping__c WHERE AIConversation__c = :conversation.Id];
System.debug('AIPIIMapping__c row count (expect 1): ' + mappingRecords.size());
System.debug('Persisted AIPIIMapping__c.MappingJson__c: ' + mappingRecords[0].MappingJson__c);

// Edge cases: null/blank inputs should be handled gracefully (no exceptions, sensible defaults).
System.debug('getFakeValueForRealValue(null conversationId) (expect null): ' + AIPiiMappingService.getFakeValueForRealValue(null, 'john.doe@acme.com'));
System.debug('addMapping(blank realValue) (expect false): ' + AIPiiMappingService.addMapping(conversation.Id, '', 'fake@example.com'));

// Clean up the test data.
delete mappingRecords;
delete conversation;
System.debug('Cleaned up test Conversation and AIPIIMapping__c record.');
