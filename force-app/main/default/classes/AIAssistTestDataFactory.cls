/*
Class Name: AIAssistTestDataFactory

=================================================================
=================================================================

Description: A collection of methods that build (and optionally insert) records used across the
AI Assist test suite.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-06     Chandler Stuart          Initial development
*/

@IsTest public class AIAssistTestDataFactory {

    public static List<User> createStandardUsers(String userType, Integer numberOfUsers, Boolean shouldDoInsert) {

        List<User> users = new List<User>();
        Id standardProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id;

        for (Integer i = 0; i < numberOfUsers; i++) {

            String uniqueName = 'aiassist' + DateTime.now().getTime() + i + Math.abs(Crypto.getRandomInteger());

            users.add(new User(
                FirstName = 'AI',
                LastName = 'Assist Tester',
                Email = uniqueName + '@example.com',
                Username = uniqueName + '@example.com.aiassisttest',
                Alias = 'aiat' + Math.mod(i, 10000),
                TimeZoneSidKey = 'GMT',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                ProfileId = standardProfileId,
                AIAssistUserType__c = userType
            ));
        }

        if (shouldDoInsert && !users.isEmpty()) {
            System.runAs(new User(Id = UserInfo.getUserId())) { insert users; }
        }

        return users;
    }
}