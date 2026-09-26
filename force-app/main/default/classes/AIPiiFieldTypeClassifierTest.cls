/*
Class Name: AIPiiFieldTypeClassifierTest

=================================================================
=================================================================

Description: Tests AIPiiFieldTypeClassifier by building AIPiiFieldType__mdt / AIPiiComplianceGroup__mdt
records in memory via AIAssistTestDataFactory, as Custom Metadata cannot be inserted via DML.

=================================================================
=================================================================
Applicable Classes:

AIPiiFieldTypeClassifier: Coverage 100%

Version      Date               Author                   Description
1.0          2026-09-15         Chandler Stuart          Initial development
*/

@IsTest private class AIPiiFieldTypeClassifierTest {

    // testScenario1: Each recognised field shape classifies to its expected PII type.
    // testScenario2: A field with a Compliance Group but no recognised shape (and no Field Type flagged as its fallback) classifies as Other.
    // testScenario3: A field with no recognised shape and no Compliance Group classifies as null (not PII).
    // testScenario4: Email is recognised ahead of Address even when both substrings are present (e.g. "EmailAddress").
    // testScenario5: A field with no recognised name/label shape but a Compliance Group matching a Field Type's ComplianceGroup__c (flagged IsComplianceGroupFallback__c) classifies via that Field Type.
    // testScenario6: A field of Salesforce's compound Address data type, whose name/label don't otherwise contain "address", classifies as Address via the DataTypeContains rule.
    // testScenario7: With no Field Type metadata cached at all, the real (empty) SOQL query path is exercised and classify falls through its "no metadata found" exception to null rather than throwing.
    // testScenario8: With Field Types cached but Compliance Groups left unseeded, the real Compliance Group SOQL query path is exercised; finding no rows, the fallback does not apply and the field classifies as Other.

    private static void setupFieldTypeMetadata() {

        AIPiiComplianceGroup__mdt healthInformationGroup = AIAssistTestDataFactory.createAIPiiComplianceGroup('Health Information', true);

        Map<Id, AIPiiComplianceGroup__mdt> complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>{
            healthInformationGroup.Id => healthInformationGroup
        };

        List<AIPiiFieldType__mdt> fieldTypes = new List<AIPiiFieldType__mdt>{
            AIAssistTestDataFactory.createAIPiiFieldType('name', AIAssistApplicationConstants.PII_MATCH_FIELD_API_NAME_EXACT, AIAssistApplicationConstants.PII_FIELD_TYPE_NAME, null, false, 1),
            AIAssistTestDataFactory.createAIPiiFieldType('email', AIAssistApplicationConstants.PII_MATCH_FIELD_NAME_OR_LABEL_CONTAINS, AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL, null, false, 2),
            AIAssistTestDataFactory.createAIPiiFieldType('phone', AIAssistApplicationConstants.PII_MATCH_FIELD_NAME_OR_LABEL_CONTAINS, AIAssistApplicationConstants.PII_FIELD_TYPE_PHONE, null, false, 3),
            AIAssistTestDataFactory.createAIPiiFieldType('ipaddress', AIAssistApplicationConstants.PII_MATCH_FIELD_NAME_OR_LABEL_CONTAINS, AIAssistApplicationConstants.PII_FIELD_TYPE_IP_ADDRESS, null, false, 4),
            AIAssistTestDataFactory.createAIPiiFieldType('address,street', AIAssistApplicationConstants.PII_MATCH_FIELD_NAME_OR_LABEL_CONTAINS, AIAssistApplicationConstants.PII_FIELD_TYPE_ADDRESS, null, false, 5),
            AIAssistTestDataFactory.createAIPiiFieldType('address', AIAssistApplicationConstants.PII_MATCH_FIELD_DATA_TYPE_CONTAINS, AIAssistApplicationConstants.PII_FIELD_TYPE_ADDRESS, null, false, 6),
            AIAssistTestDataFactory.createAIPiiFieldType('ssn,socialsecuritynumber', AIAssistApplicationConstants.PII_MATCH_FIELD_NAME_OR_LABEL_CONTAINS, AIAssistApplicationConstants.PII_FIELD_TYPE_SSN, null, false, 7),
            AIAssistTestDataFactory.createAIPiiFieldType('bankaccount', AIAssistApplicationConstants.PII_MATCH_FIELD_NAME_OR_LABEL_CONTAINS, AIAssistApplicationConstants.PII_FIELD_TYPE_BANK_ACCOUNT, null, false, 8),
            AIAssistTestDataFactory.createAIPiiFieldType('creditcard', AIAssistApplicationConstants.PII_MATCH_FIELD_NAME_OR_LABEL_CONTAINS, AIAssistApplicationConstants.PII_FIELD_TYPE_CREDIT_CARD, null, false, 9),
            AIAssistTestDataFactory.createAIPiiFieldType('dob,dateofbirth', AIAssistApplicationConstants.PII_MATCH_FIELD_NAME_OR_LABEL_CONTAINS, AIAssistApplicationConstants.PII_FIELD_TYPE_DATE_OF_BIRTH, null, false, 10),
            AIAssistTestDataFactory.createAIPiiFieldType('passport', AIAssistApplicationConstants.PII_MATCH_FIELD_NAME_OR_LABEL_CONTAINS, AIAssistApplicationConstants.PII_FIELD_TYPE_GOVERNMENT_ID, null, false, 11),
            AIAssistTestDataFactory.createAIPiiFieldType('medicalrecordnumber', AIAssistApplicationConstants.PII_MATCH_FIELD_NAME_OR_LABEL_CONTAINS, AIAssistApplicationConstants.PII_FIELD_TYPE_MEDICAL_RECORD, healthInformationGroup.Id, true, 12)
        };

        AIPiiFieldTypeClassifier.setFieldTypesForTest(fieldTypes);
        AIPiiFieldTypeClassifier.setComplianceGroupsForTest(complianceGroupsById);
    }

    @IsTest static void testScenario1() {

        setupFieldTypeMetadata();

        Test.startTest();
            Assert.areEqual(AIAssistApplicationConstants.PII_FIELD_TYPE_NAME, AIPiiFieldTypeClassifier.classify('Name', 'Full Name', 'string', 'Name'), 'Name should classify as Name.');
            Assert.areEqual(AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL, AIPiiFieldTypeClassifier.classify('Email__c', 'Email', 'email', 'Contact Information'), 'Email__c should classify as Email.');
            Assert.areEqual(AIAssistApplicationConstants.PII_FIELD_TYPE_PHONE, AIPiiFieldTypeClassifier.classify('Phone', 'Business Phone', 'phone', 'Contact Information'), 'Phone should classify as Phone.');
            Assert.areEqual(AIAssistApplicationConstants.PII_FIELD_TYPE_ADDRESS, AIPiiFieldTypeClassifier.classify('MailingStreet', 'Mailing Street', 'string', 'Communication Address'), 'MailingStreet should classify as Address.');
            Assert.areEqual(AIAssistApplicationConstants.PII_FIELD_TYPE_SSN, AIPiiFieldTypeClassifier.classify('SSN__c', 'Social Security Number', 'string', 'Government ID'), 'SSN__c should classify as SSN.');
            Assert.areEqual(AIAssistApplicationConstants.PII_FIELD_TYPE_BANK_ACCOUNT, AIPiiFieldTypeClassifier.classify('BankAccountNumber__c', 'Bank Account Number', 'string', 'Financial'), 'BankAccountNumber__c should classify as Bank Account.');
            Assert.areEqual(AIAssistApplicationConstants.PII_FIELD_TYPE_CREDIT_CARD, AIPiiFieldTypeClassifier.classify('CreditCardNumber__c', 'Credit Card Number', 'string', 'Financial'), 'CreditCardNumber__c should classify as Credit Card.');
            Assert.areEqual(AIAssistApplicationConstants.PII_FIELD_TYPE_DATE_OF_BIRTH, AIPiiFieldTypeClassifier.classify('DOB__c', 'Date of Birth', 'date', 'Personal Information'), 'DOB__c should classify as Date of Birth.');
            Assert.areEqual(AIAssistApplicationConstants.PII_FIELD_TYPE_IP_ADDRESS, AIPiiFieldTypeClassifier.classify('LastIPAddress__c', 'Last IP Address', 'string', 'Technical'), 'LastIPAddress__c should classify as IP Address.');
            Assert.areEqual(AIAssistApplicationConstants.PII_FIELD_TYPE_GOVERNMENT_ID, AIPiiFieldTypeClassifier.classify('PassportNumber__c', 'Passport Number', 'string', 'Government ID'), 'PassportNumber__c should classify as Government ID.');
        Test.stopTest();
    }

    @IsTest static void testScenario2() {

        setupFieldTypeMetadata();

        Test.startTest();
            String result = AIPiiFieldTypeClassifier.classify('CustomField__c', 'Custom Field', 'string', 'Confidential');
        Test.stopTest();

        Assert.areEqual(AIAssistApplicationConstants.PII_FIELD_TYPE_OTHER, result, 'A Compliance Group with no recognised field shape and no fallback Field Type should classify as Other.');
    }

    @IsTest static void testScenario3() {

        setupFieldTypeMetadata();

        Test.startTest();
            String result = AIPiiFieldTypeClassifier.classify('Description', 'Description', 'textarea', null);
        Test.stopTest();

        Assert.isNull(result, 'A field with no recognised shape and no Compliance Group should not be classified as PII.');
    }

    @IsTest static void testScenario4() {

        setupFieldTypeMetadata();

        Test.startTest();
            String result = AIPiiFieldTypeClassifier.classify('EmailAddress__c', 'Email Address', 'string', 'Contact Information');
        Test.stopTest();

        Assert.areEqual(AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL, result, 'Email should be recognised ahead of Address for a field whose name contains both substrings.');
    }

    @IsTest static void testScenario5() {

        setupFieldTypeMetadata();

        Test.startTest();
            String result = AIPiiFieldTypeClassifier.classify('PatientChart__c', 'Patient Chart', 'string', 'Health Information');
        Test.stopTest();

        Assert.areEqual(AIAssistApplicationConstants.PII_FIELD_TYPE_MEDICAL_RECORD, result, 'A Health Information Compliance Group with no recognised shape should classify via the Field Type flagged as that group\'s fallback.');
    }

    @IsTest static void testScenario6() {

        setupFieldTypeMetadata();

        Test.startTest();
            String result = AIPiiFieldTypeClassifier.classify('HomeLocation__c', 'Home Location', 'Address', 'Location Information');
        Test.stopTest();

        Assert.areEqual(AIAssistApplicationConstants.PII_FIELD_TYPE_ADDRESS, result, 'A field of the compound Address data type should classify as Address via the DataTypeContains rule even without an "address" keyword in its name or label.');
    }

    @IsTest static void testScenario7() {

        Test.startTest();
            String result = AIPiiFieldTypeClassifier.classify('Foo__c', 'Foo', 'string', 'SomeGroup');
        Test.stopTest();

        Assert.isNull(result, 'With no Field Type metadata cached at all, classify should fall through its "no metadata found" exception to null rather than throwing.');
    }

    @IsTest static void testScenario8() {

        Id healthInformationGroupId = AIAssistTestDataFactory.createAIPiiComplianceGroup('Health Information', true).Id;

        AIPiiFieldTypeClassifier.setFieldTypesForTest(new List<AIPiiFieldType__mdt>{
            AIAssistTestDataFactory.createAIPiiFieldType('medicalrecordnumber', AIAssistApplicationConstants.PII_MATCH_FIELD_NAME_OR_LABEL_CONTAINS, AIAssistApplicationConstants.PII_FIELD_TYPE_MEDICAL_RECORD, healthInformationGroupId, true, 1)
        });

        Test.startTest();
            String result = AIPiiFieldTypeClassifier.classify('PatientChart__c', 'Patient Chart', 'string', 'Health Information');
        Test.stopTest();

        Assert.areEqual(AIAssistApplicationConstants.PII_FIELD_TYPE_OTHER, result, 'With Compliance Groups left unseeded, the real (empty) Compliance Group query should find no match, so the fallback should not apply and the field should classify as Other.');
    }
}