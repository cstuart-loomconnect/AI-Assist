/*
Class Name: AIConsoleSoqlBuilderService

=================================================================
=================================================================

Description: The describe calls behind the New Data Source modal's SOQL Builder (aiSoqlBuilder) and the
"Valid query" check shown in both Builder and Write SOQL modes.

- getQueryObjects: for a Bound source, the bound object itself plus every object that looks up to it
  (so the query can filter on :recordId); for an Unbound source, every queryable record object.
- getFields: an object's fields, plus one level of parent fields (Contact.Name, Contact.Email) for its
  lookups, each flagged when AIPiiFieldRegistry treats it as PII.
- checkSoql: runs the query with LIMIT 0 in USER_MODE (so syntax, fields and access are all checked
  without returning data) and generates the Input Schema from its binds.

The Builder itself composes the SOQL in the browser; the server only ever validates it.

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-29     Chandler Stuart          Initial development
*/

public with sharing class AIConsoleSoqlBuilderService {

    private static final Set<String> SKIPPED_SUFFIXES = new Set<String>{ 'History', 'Share', 'Feed', 'ChangeEvent', '__hd', '__History', '__Share', '__Feed' };
    private static final Integer MAX_PARENT_LOOKUPS = 15;

    public static List<AIConsoleDataStructure.QueryObjectOption> getQueryObjects(String boundObject, String bindingType) {

        List<AIConsoleDataStructure.QueryObjectOption> options = new List<AIConsoleDataStructure.QueryObjectOption>();

        if (bindingType != AIConsoleConstants.BINDING_BOUND || String.isBlank(boundObject)) {
            for (AIConsoleDataStructure.Option option : AIConsoleWizardService.getObjectOptions()) {
                AIConsoleDataStructure.QueryObjectOption objectOption = new AIConsoleDataStructure.QueryObjectOption();
                objectOption.apiName = option.value;
                objectOption.label = option.label;
                options.add(objectOption);
            }
            return options;
        }

        Schema.SObjectType parentType = Schema.getGlobalDescribe().get(boundObject);
        if (parentType == null) throw new AIConsoleDataStructure.AIConsoleException(boundObject + ' isn\'t an object in this org.');
        Schema.DescribeSObjectResult parent = parentType.getDescribe();

        AIConsoleDataStructure.QueryObjectOption self = new AIConsoleDataStructure.QueryObjectOption();
        self.apiName = parent.getName();
        self.label = parent.getLabel() + ' (this record)';
        self.relationshipField = 'Id';
        self.relationshipLabel = parent.getLabel() + ' ID';
        self.isBoundObject = true;
        options.add(self);

        List<AIConsoleDataStructure.QueryObjectOption> children = new List<AIConsoleDataStructure.QueryObjectOption>();
        Set<String> seen = new Set<String>();

        for (Schema.ChildRelationship relationship : parent.getChildRelationships()) {

            if (relationship.isDeprecatedAndHidden() || relationship.getRelationshipName() == null) continue;

            Schema.DescribeSObjectResult child = relationship.getChildSObject().getDescribe();
            if (!child.isQueryable() || !child.isAccessible() || isSkipped(child.getName())) continue;

            Schema.DescribeFieldResult field = relationship.getField().getDescribe();
            String key = child.getName() + '.' + field.getName();
            if (seen.contains(key)) continue;
            seen.add(key);

            AIConsoleDataStructure.QueryObjectOption option = new AIConsoleDataStructure.QueryObjectOption();
            option.apiName = child.getName();
            option.label = child.getLabel();
            option.relationshipField = field.getName();
            option.relationshipLabel = field.getLabel().removeEnd(' ID') + ' (' + field.getName() + ')';
            children.add(option);
        }

        children.sort(new ObjectLabelOrder());
        options.addAll(children);
        return options;
    }

    public static List<AIConsoleDataStructure.FieldOption> getFields(String objectApiName) {

        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        if (objectType == null) throw new AIConsoleDataStructure.AIConsoleException(objectApiName + ' isn\'t an object in this org.');

        Map<String, String> piiTypes = safePiiTypes(objectApiName);
        List<AIConsoleDataStructure.FieldOption> fields = new List<AIConsoleDataStructure.FieldOption>();
        Integer lookupsExpanded = 0;

        for (Schema.SObjectField field : objectType.getDescribe().fields.getMap().values()) {

            Schema.DescribeFieldResult describe = field.getDescribe();
            if (!describe.isAccessible()) continue;

            fields.add(toFieldOption(describe.getName(), describe, piiTypes.containsKey(describe.getName())));

            // One level of parent fields for single-target lookups: the name, and any email or phone (the usual PII).
            Boolean isSingleLookup = describe.getType() == Schema.DisplayType.REFERENCE && describe.getReferenceTo().size() == 1 && describe.getRelationshipName() != null;
            if (!isSingleLookup || lookupsExpanded >= MAX_PARENT_LOOKUPS) continue;
            lookupsExpanded++;

            Schema.DescribeSObjectResult parent = describe.getReferenceTo()[0].getDescribe();
            if (!parent.isAccessible()) continue;
            Map<String, String> parentPii = safePiiTypes(parent.getName());

            for (Schema.SObjectField parentField : parent.fields.getMap().values()) {
                Schema.DescribeFieldResult parentDescribe = parentField.getDescribe();
                Boolean isUseful = parentDescribe.isNameField() || parentDescribe.getType() == Schema.DisplayType.EMAIL || parentDescribe.getType() == Schema.DisplayType.PHONE;
                if (!isUseful || !parentDescribe.isAccessible()) continue;

                AIConsoleDataStructure.FieldOption option = toFieldOption(describe.getRelationshipName() + '.' + parentDescribe.getName(), parentDescribe, parentPii.containsKey(parentDescribe.getName()) || parentDescribe.isNameField() && parent.getName() == 'Contact');
                option.label = parent.getLabel() + ' ' + parentDescribe.getLabel().replace(parent.getLabel() + ' ', '');
                option.isSortable = false;
                option.isFilterable = false;
                fields.add(option);
            }
        }

        fields.sort(new FieldLabelOrder());
        return fields;
    }

    public static AIConsoleDataStructure.SoqlCheck checkSoql(String soql, String targetObject, String bindingType) {

        AIConsoleDataStructure.SoqlCheck check = new AIConsoleDataStructure.SoqlCheck();

        if (String.isBlank(soql) || !soql.trim().toUpperCase().startsWith('SELECT')) {
            check.message = 'Write a SELECT query.';
            return check;
        }

        String query = soql.trim();
        String fromObject = query.replaceAll('(?is)^.*?\\bFROM\\s+([A-Za-z0-9_]+).*$', '$1');

        try {
            String probe = Pattern.compile('(?i)\\bLIMIT\\s+\\d+').matcher(query).find() ? query.replaceFirst('(?i)\\bLIMIT\\s+\\d+', 'LIMIT 0') : query + ' LIMIT 0';
            Database.queryWithBinds(probe, AIConsoleLibraryService.bindsFor(query, null), AccessLevel.USER_MODE);
            check.isValid = true;
            check.message = 'Valid query';
            check.notes.add('Valid query. Every field exists on ' + fromObject + '.');
        } catch (Exception ex) {
            check.message = ex.getMessage().left(300);
            return check;
        }

        List<String> binds = AIConsoleLibraryService.bindNames(query);
        if (bindingType == AIConsoleConstants.BINDING_BOUND) {
            check.notes.add(binds.contains('recordId') ? 'Filtered to the open record with :recordId.' : 'Bound sources should filter with :recordId - this one doesn\'t use the open record.');
        }

        String selectPart = query.replaceAll('(?is)^\\s*SELECT\\s+(.*?)\\s+FROM\\s.*$', '$1');
        Map<String, String> piiTypes = safePiiTypes(fromObject);
        for (String rawField : selectPart.split(',')) {
            String fieldName = rawField.trim();
            Boolean isPii = fieldName.contains('.') ? isParentPii(fromObject, fieldName) : piiTypes.containsKey(fieldName);
            if (isPii) check.piiFields.add(fieldName);
        }
        check.notes.add(check.piiFields.isEmpty() ? 'No PII fields selected.' : 'PII fields selected: ' + String.join(check.piiFields, ', ') + '. They’re masked before the AI sees them.');

        check.inputSchema = buildInputSchema(binds);
        return check;
    }

    // {"type":"object","properties":{"recordId":{"type":"string"}},"required":["recordId"]} - recordId is filled in automatically for bound sources; every other bind is asked of the AI.
    public static String buildInputSchema(List<String> binds) {

        Map<String, Object> properties = new Map<String, Object>();
        List<String> required = new List<String>();

        for (String bind : binds) {
            properties.put(bind, new Map<String, Object>{ 'type' => 'string' });
            required.add(bind);
        }

        return JSON.serializePretty(new Map<String, Object>{ 'type' => 'object', 'properties' => properties, 'required' => required });
    }

    // =============================================================
    // Helpers
    // =============================================================

    private static AIConsoleDataStructure.FieldOption toFieldOption(String apiName, Schema.DescribeFieldResult describe, Boolean isPii) {
        AIConsoleDataStructure.FieldOption option = new AIConsoleDataStructure.FieldOption();
        option.apiName = apiName;
        option.label = describe.getLabel();
        option.dataType = String.valueOf(describe.getType());
        option.isPii = isPii == true;
        option.isDate = describe.getType() == Schema.DisplayType.DATE || describe.getType() == Schema.DisplayType.DATETIME;
        option.isSortable = describe.isSortable();
        option.isFilterable = describe.isFilterable();
        return option;
    }

    private static Boolean isParentPii(String fromObject, String path) {
        try {
            Schema.SObjectType objectType = Schema.getGlobalDescribe().get(fromObject);
            String relationshipName = path.substringBefore('.');
            for (Schema.SObjectField field : objectType.getDescribe().fields.getMap().values()) {
                Schema.DescribeFieldResult describe = field.getDescribe();
                if (describe.getRelationshipName() == relationshipName && describe.getReferenceTo().size() == 1) {
                    String parentName = describe.getReferenceTo()[0].getDescribe().getName();
                    return safePiiTypes(parentName).containsKey(path.substringAfter('.')) || (parentName == 'Contact' && path.substringAfter('.') == 'Name');
                }
            }
        } catch (Exception ex) {
            return false;
        }
        return false;
    }

    private static Map<String, String> safePiiTypes(String objectApiName) {
        try {
            Map<String, String> types = AIPiiFieldRegistry.getPiiFieldTypes(objectApiName);
            return types == null ? new Map<String, String>() : types;
        } catch (Exception ex) {
            return new Map<String, String>();
        }
    }

    private static Boolean isSkipped(String objectName) {
        for (String suffix : SKIPPED_SUFFIXES) {
            if (objectName.endsWith(suffix)) return true;
        }
        return false;
    }

    private class ObjectLabelOrder implements Comparator<AIConsoleDataStructure.QueryObjectOption> {
        public Integer compare(AIConsoleDataStructure.QueryObjectOption left, AIConsoleDataStructure.QueryObjectOption right) {
            return left.label.compareTo(right.label);
        }
    }

    private class FieldLabelOrder implements Comparator<AIConsoleDataStructure.FieldOption> {
        public Integer compare(AIConsoleDataStructure.FieldOption left, AIConsoleDataStructure.FieldOption right) {
            return left.label.compareTo(right.label);
        }
    }
}