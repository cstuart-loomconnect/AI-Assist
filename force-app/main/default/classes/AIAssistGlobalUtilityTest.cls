/*
Class Name: AIAssistGlobalUtilityTest

=================================================================
=================================================================

Description: This class contains unit tests for the AIAssistGlobalUtility class, the shared utility used
across the AI Assist Platform to automatically stamp records with stable external identifiers and
sanitised developer names as they flow through the application.

=================================================================
=================================================================
Applicable Classes:

AIAssistGlobalUtility: Coverage 100%

Version      Date           Author                   Description
1.0          2026-09-06     Chandler Stuart          Initial development
*/

@IsTest private class AIAssistGlobalUtilityTest {

    // testScenario1: generatePublicId stamps a UUID style PublicId__c onto a record that does not have one.
    // testScenario2: generatePublicId leaves an already populated PublicId__c untouched.
    // testScenario3: generatePublicId logs an exception when a record cannot be processed.
    // testScenario4: generateDeveloperName derives DeveloperName__c from Name, replacing non-alphanumerics with underscores.
    // testScenario5: generateDeveloperName leaves an already populated DeveloperName__c untouched.
    // testScenario6: generateDeveloperName logs an exception when a record cannot be processed.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsApplicationActive__c = true;
        settings.DisableExceptionLogging__c = false;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        AIModelConfiguration__c record = new AIModelConfiguration__c(Name = 'Test Model');

        Test.startTest();
            AIAssistGlobalUtility.generatePublicId(new List<SObject>{ record });
        Test.stopTest();

        String publicId = (String) record.get('PublicId__c');

        Assert.isNotNull(publicId, 'PublicId__c should be populated.');
        Assert.isTrue(Pattern.matches('[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}', publicId), 'PublicId__c should match the UUID format.');
    }

    @IsTest static void testScenario2() {

        AIModelConfiguration__c record = new AIModelConfiguration__c(Name = 'Test Model', PublicId__c = 'existing-public-id');

        Test.startTest();
            AIAssistGlobalUtility.generatePublicId(new List<SObject>{ record });
        Test.stopTest();

        Assert.areEqual('existing-public-id', record.get('PublicId__c'), 'An existing PublicId__c should not be overwritten.');
    }

    @IsTest static void testScenario3() {

        Test.startTest();
            AIAssistGlobalUtility.generatePublicId(new List<SObject>{ null });
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'AIAssistGlobalUtility' AND MethodName__c = 'generatePublicId'], 'An exception should be logged when a record cannot be processed.');
    }

    @IsTest static void testScenario4() {

        AIModelConfiguration__c record = new AIModelConfiguration__c(Name = 'My Model 123!!');

        Test.startTest();
            AIAssistGlobalUtility.generateDeveloperName(new List<SObject>{ record });
        Test.stopTest();

        Assert.areEqual('My_Model_123', record.get('DeveloperName__c'), 'DeveloperName__c should be derived from Name with non-alphanumerics replaced by underscores and no leading or trailing underscore.');
    }

    @IsTest static void testScenario5() {

        AIModelConfiguration__c record = new AIModelConfiguration__c(Name = 'My Model', DeveloperName__c = 'Existing_Name');

        Test.startTest();
            AIAssistGlobalUtility.generateDeveloperName(new List<SObject>{ record });
        Test.stopTest();

        Assert.areEqual('Existing_Name', record.get('DeveloperName__c'), 'An existing DeveloperName__c should not be overwritten.');
    }

    @IsTest static void testScenario6() {

        Test.startTest();
            AIAssistGlobalUtility.generateDeveloperName(new List<SObject>{ null });
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'AIAssistGlobalUtility' AND MethodName__c = 'generateDeveloperName'], 'An exception should be logged when a record cannot be processed.');
    }
}