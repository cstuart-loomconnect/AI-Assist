// Demo script: forces one good example of each exception/log type handled by
// AIPlatformLogManager, so AIPlatformLogEvent__e records land for a demo of
// the resulting AIPlatformLog__c (or equivalent) records.
//
// Covers:
//   1. logException - NullPointerException
//   2. logException - DmlException (caught, re-logged manually)
//   3. logException - ListException (index out of bounds)
//   4. logExceptions(SaveResult) - a bulk insert with several failures
//   5. logExceptions(DeleteResult) - a bulk delete with several failures
//   6. logExceptions(UpsertResult) - a bulk upsert with several failures
//   7. logCustomMessage - a manual/business-rule log entry

// 1. NullPointerException
try {
    Account nullAccount = null;
    System.debug(nullAccount.Name); // forces NPE
} catch (Exception e) {
    AIPlatformLogManager.logException(e, 'DemoScript', 'forceNullPointerException');
}

// 2. DmlException
try {
    insert new Account(); // missing required Name field
} catch (Exception e) {
    AIPlatformLogManager.logException(e, 'DemoScript', 'forceDmlException');
}

// 3. ListException
try {
    List<String> emptyList = new List<String>();
    System.debug(emptyList[0]); // forces List index out of bounds
} catch (Exception e) {
    AIPlatformLogManager.logException(e, 'DemoScript', 'forceListException');
}

// 4. Bulk SaveResult failure (10 Accounts, 3 with no Name so they fail)
Set<Integer> saveFailureIndexes = new Set<Integer>{ 1, 4, 8 }; // 0-based positions that fail
List<Account> accountsToInsert = new List<Account>();
for (Integer i = 0; i < 10; i++) {
    accountsToInsert.add(
        saveFailureIndexes.contains(i)
            ? new Account() // will fail - Name is required
            : new Account(Name = 'AI Assist Demo Account ' + i)
    );
}
List<Database.SaveResult> saveResults = Database.insert(accountsToInsert, false);
AIPlatformLogManager.logExceptions(saveResults, 'DemoScript', 'forceSaveResultFailure');

// 5. Bulk DeleteResult failure (10 Accounts deleted, 3 pre-deleted for real up front
Set<Integer> deleteFailureIndexes = new Set<Integer>{ 2, 5, 9 }; // 0-based positions that fail
List<Account> accountsToDelete = new List<Account>();
for (Integer i = 0; i < 10; i++) {
    Account acc = accountsToInsert[i].Id != null
        ? accountsToInsert[i]
        : new Account(Name = 'AI Assist Demo Delete Account ' + i);
    if (acc.Id == null) {
        insert acc;
    }
    if (deleteFailureIndexes.contains(i)) {
        delete acc; // delete it for real first so the batch delete below fails on it
    }
    accountsToDelete.add(new Account(Id = acc.Id));
}
List<Database.DeleteResult> deleteResults = Database.delete(accountsToDelete, false);
AIPlatformLogManager.logExceptions(deleteResults, 'DemoScript', 'forceDeleteResultFailure');

// 6. Bulk UpsertResult failure (10 Accounts, 3 with fake/invalid Ids so they fail
Set<Integer> upsertFailureIndexes = new Set<Integer>{ 0, 3, 7 }; // 0-based positions that fail
List<Account> accountsToUpsert = new List<Account>();
for (Integer i = 0; i < 10; i++) {
    accountsToUpsert.add(
        upsertFailureIndexes.contains(i)
            ? new Account(Id = '001000000000000AAA', Name = 'Invalid Id Upsert ' + i) // fake/invalid Id
            : new Account(Name = 'AI Assist Demo Upsert Account ' + i)
    );
}
List<Database.UpsertResult> upsertResults = Database.upsert(accountsToUpsert, false);
AIPlatformLogManager.logExceptions(upsertResults, 'DemoScript', 'forceUpsertResultFailure');

// 7. Custom business-rule log message (no exception thrown, just a manual log entry)
AIPlatformLogManager.logCustomMessage('Demo: AI response blocked by content policy','User prompt matched a restricted-content violation rule during a scripted demo run. No exception was thrown - this is a manual audit log entry.','DemoScript','forceCustomMessage',UserInfo.getUserId());

System.debug('Forced 7 AIPlatformLogEvent__e entries for demo purposes.');
