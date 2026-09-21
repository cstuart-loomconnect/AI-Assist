// Run with: SFDX: Execute Anonymous Apex with Editor Contents
// Creates AI PII Compliance Group, AI PII Data Masking Rule, and AI PII Field Type custom
// metadata records via the Metadata API instead of static customMetadata source files, so
// these records live only in the org and are never retrieved/committed into the repo
// (see the customMetadata ignore rules added to .forceignore).
//
// Metadata.Operations.enqueueDeployment() is asynchronous - after running, check
// Setup > Deployment Status for the deployment to complete before the records are queryable.

class PiiMetadataHelper {
    void addValue(Metadata.CustomMetadata cmd, String field, Object value) {
        Metadata.CustomMetadataValue cmdValue = new Metadata.CustomMetadataValue();
        cmdValue.field = field;
        cmdValue.value = value;
        cmd.values.add(cmdValue);
    }
}

PiiMetadataHelper helper = new PiiMetadataHelper();

Metadata.DeployContainer container = new Metadata.DeployContainer();

// ---------- AI PII Compliance Groups ----------

Metadata.CustomMetadata financialGroup = new Metadata.CustomMetadata();
financialGroup.fullName = 'AIPiiComplianceGroup__mdt.Financial_Information';
financialGroup.label = 'Financial Information';
helper.addValue(financialGroup, 'Active__c', true);
helper.addValue(
    financialGroup,
    'Description__c',
    'PII related to financial identifiers such as bank accounts and credit cards.'
);
container.addMetadata(financialGroup);

Metadata.CustomMetadata governmentGroup = new Metadata.CustomMetadata();
governmentGroup.fullName = 'AIPiiComplianceGroup__mdt.Government_Identifiers';
governmentGroup.label = 'Government Identifiers';
helper.addValue(governmentGroup, 'Active__c', true);
helper.addValue(
    governmentGroup,
    'Description__c',
    'Government-issued identification numbers, e.g. National Insurance and NHS numbers.'
);
container.addMetadata(governmentGroup);

Metadata.CustomMetadata healthGroup = new Metadata.CustomMetadata();
healthGroup.fullName = 'AIPiiComplianceGroup__mdt.Health_Information';
healthGroup.label = 'Health Information';
helper.addValue(healthGroup, 'Active__c', true);
helper.addValue(healthGroup, 'Description__c', 'Medical and health-related identifiers.');
container.addMetadata(healthGroup);

// ---------- AI PII Data Masking Rules ----------

Metadata.CustomMetadata maskDigits = new Metadata.CustomMetadata();
maskDigits.fullName = 'AIPiiDataMaskingRule__mdt.Mask_Digits';
maskDigits.label = 'Mask Digits';
helper.addValue(maskDigits, 'Active__c', true);
helper.addValue(maskDigits, 'Strategy__c', 'PatternReplace');
helper.addValue(maskDigits, 'ReplacementPattern__c', '\\d');
helper.addValue(maskDigits, 'ReplacementCharacterCount__c', 4);
container.addMetadata(maskDigits);

Metadata.CustomMetadata substituteFirstNames = new Metadata.CustomMetadata();
substituteFirstNames.fullName = 'AIPiiDataMaskingRule__mdt.Substitute_First_Names';
substituteFirstNames.label = 'Substitute Full Names';
helper.addValue(substituteFirstNames, 'Active__c', true);
helper.addValue(substituteFirstNames, 'Strategy__c', 'SubstituteFromList');
helper.addValue(substituteFirstNames, 'SubstituteValues__c', 'Alex Rivera,Jordan Chen,Sam Patel,Taylor Morgan,Morgan Reyes'); // Full "First Last" values - the Name Field Type masks the whole Name field, so a bare first name doesn't match its shape.
container.addMetadata(substituteFirstNames);

Metadata.CustomMetadata substituteEmails = new Metadata.CustomMetadata();
substituteEmails.fullName = 'AIPiiDataMaskingRule__mdt.Substitute_Emails';
substituteEmails.label = 'Substitute Emails';
helper.addValue(substituteEmails, 'Active__c', true);
helper.addValue(substituteEmails, 'Strategy__c', 'SubstituteFromList');
helper.addValue(substituteEmails, 'SubstituteValues__c', 'alex.rivera@example.com,jordan.chen@example.com,sam.patel@example.com,taylor.morgan@example.com,morgan.reyes@example.com');
container.addMetadata(substituteEmails);

Metadata.CustomMetadata substitutePhoneNumbers = new Metadata.CustomMetadata();
substitutePhoneNumbers.fullName = 'AIPiiDataMaskingRule__mdt.Substitute_Phone_Numbers';
substitutePhoneNumbers.label = 'Substitute Phone Numbers';
helper.addValue(substitutePhoneNumbers, 'Active__c', true);
helper.addValue(substitutePhoneNumbers, 'Strategy__c', 'SubstituteFromList');
helper.addValue(substitutePhoneNumbers, 'SubstituteValues__c', '555-010-0100,555-020-0200,555-030-0300,555-040-0400,555-050-0500');
container.addMetadata(substitutePhoneNumbers);

// ---------- AI PII Field Types ----------
// DisplayOrder__c is ascending, most specific shapes first so they aren't swallowed by broader ones.

Metadata.CustomMetadata emailType = new Metadata.CustomMetadata();
emailType.fullName = 'AIPiiFieldType__mdt.Email';
emailType.label = 'Email';
helper.addValue(emailType, 'Active__c', true);
helper.addValue(emailType, 'Keyword__c', 'email');
helper.addValue(emailType, 'MatchField__c', 'NameOrLabelContains');
helper.addValue(emailType, 'PIIFieldType__c', 'Email');
helper.addValue(emailType, 'DisplayOrder__c', 10);
helper.addValue(emailType, 'MaskingRule__c', 'Substitute_Emails');
container.addMetadata(emailType);

Metadata.CustomMetadata creditCardType = new Metadata.CustomMetadata();
creditCardType.fullName = 'AIPiiFieldType__mdt.Credit_Card';
creditCardType.label = 'Credit Card';
helper.addValue(creditCardType, 'Active__c', true);
helper.addValue(creditCardType, 'Keyword__c', 'creditcard,cardnumber');
helper.addValue(creditCardType, 'MatchField__c', 'NameOrLabelContains');
helper.addValue(creditCardType, 'PIIFieldType__c', 'Credit Card');
helper.addValue(creditCardType, 'DisplayOrder__c', 15);
helper.addValue(creditCardType, 'ComplianceGroup__c', 'Financial_Information');
helper.addValue(creditCardType, 'MaskingRule__c', 'Mask_Digits');
container.addMetadata(creditCardType);

Metadata.CustomMetadata phoneType = new Metadata.CustomMetadata();
phoneType.fullName = 'AIPiiFieldType__mdt.Phone';
phoneType.label = 'Phone';
helper.addValue(phoneType, 'Active__c', true);
helper.addValue(phoneType, 'Keyword__c', 'phone,mobile,telephone');
helper.addValue(phoneType, 'MatchField__c', 'NameOrLabelContains');
helper.addValue(phoneType, 'PIIFieldType__c', 'Phone');
helper.addValue(phoneType, 'DisplayOrder__c', 20);
helper.addValue(phoneType, 'MaskingRule__c', 'Substitute_Phone_Numbers');
container.addMetadata(phoneType);

Metadata.CustomMetadata niNumberType = new Metadata.CustomMetadata();
niNumberType.fullName = 'AIPiiFieldType__mdt.National_Insurance_Number';
niNumberType.label = 'National Insurance Number';
helper.addValue(niNumberType, 'Active__c', true);
helper.addValue(niNumberType, 'Keyword__c', 'nationalinsurancenumber,ninumber,nino');
helper.addValue(niNumberType, 'MatchField__c', 'NameOrLabelContains');
helper.addValue(niNumberType, 'PIIFieldType__c', 'National Insurance Number');
helper.addValue(niNumberType, 'DisplayOrder__c', 25);
helper.addValue(niNumberType, 'ComplianceGroup__c', 'Government_Identifiers');
helper.addValue(niNumberType, 'IsComplianceGroupFallback__c', true);
helper.addValue(niNumberType, 'MaskingRule__c', 'Mask_Digits');
container.addMetadata(niNumberType);

Metadata.CustomMetadata nhsNumberType = new Metadata.CustomMetadata();
nhsNumberType.fullName = 'AIPiiFieldType__mdt.NHS_Number';
nhsNumberType.label = 'NHS Number';
helper.addValue(nhsNumberType, 'Active__c', true);
helper.addValue(nhsNumberType, 'Keyword__c', 'nhsnumber');
helper.addValue(nhsNumberType, 'MatchField__c', 'NameOrLabelContains');
helper.addValue(nhsNumberType, 'PIIFieldType__c', 'NHS Number');
helper.addValue(nhsNumberType, 'DisplayOrder__c', 26);
helper.addValue(nhsNumberType, 'ComplianceGroup__c', 'Health_Information');
helper.addValue(nhsNumberType, 'IsComplianceGroupFallback__c', true);
helper.addValue(nhsNumberType, 'MaskingRule__c', 'Mask_Digits');
container.addMetadata(nhsNumberType);

Metadata.CustomMetadata bankAccountType = new Metadata.CustomMetadata();
bankAccountType.fullName = 'AIPiiFieldType__mdt.Bank_Account';
bankAccountType.label = 'Bank Account';
helper.addValue(bankAccountType, 'Active__c', true);
helper.addValue(bankAccountType, 'Keyword__c', 'bankaccount,routingnumber,iban,sortcode');
helper.addValue(bankAccountType, 'MatchField__c', 'NameOrLabelContains');
helper.addValue(bankAccountType, 'PIIFieldType__c', 'Bank Account');
helper.addValue(bankAccountType, 'DisplayOrder__c', 30);
helper.addValue(bankAccountType, 'ComplianceGroup__c', 'Financial_Information');
helper.addValue(bankAccountType, 'IsComplianceGroupFallback__c', true);
helper.addValue(bankAccountType, 'MaskingRule__c', 'Mask_Digits');
container.addMetadata(bankAccountType);

Metadata.CustomMetadata addressType = new Metadata.CustomMetadata();
addressType.fullName = 'AIPiiFieldType__mdt.Address';
addressType.label = 'Address';
helper.addValue(addressType, 'Active__c', true);
helper.addValue(addressType, 'Keyword__c', 'address');
helper.addValue(addressType, 'MatchField__c', 'DataTypeContains');
helper.addValue(addressType, 'PIIFieldType__c', 'Address');
helper.addValue(addressType, 'DisplayOrder__c', 90);
helper.addValue(addressType, 'MaskingRule__c', 'Mask_Digits'); // MaskingRule__c is required on this object - Mask_Digits' Strategy__c ('PatternReplace') doesn't match AIAssistApplicationConstants.PII_MASKING_STRATEGY_SUBSTITUTE_FROM_LIST, so this still falls through to the REDACTED fallback rather than a real substitution.
container.addMetadata(addressType);

Metadata.CustomMetadata nameType = new Metadata.CustomMetadata();
nameType.fullName = 'AIPiiFieldType__mdt.Name';
nameType.label = 'Name';
helper.addValue(nameType, 'Active__c', true);
helper.addValue(nameType, 'Keyword__c', 'name');
helper.addValue(nameType, 'MatchField__c', 'ApiNameExact');
helper.addValue(nameType, 'PIIFieldType__c', 'Name');
helper.addValue(nameType, 'DisplayOrder__c', 95);
helper.addValue(nameType, 'MaskingRule__c', 'Substitute_First_Names'); // The only Field Type wired to this rule so far - it was created above but nothing else references it.
container.addMetadata(nameType);

Id jobId = Metadata.Operations.enqueueDeployment(container, null);
System.debug('PII custom metadata deployment enqueued. Job Id: ' + jobId);
System.debug('Check Setup > Deployment Status for completion before querying the new records.');
