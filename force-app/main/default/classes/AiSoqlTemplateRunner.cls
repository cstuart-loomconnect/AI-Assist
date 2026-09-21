/*
Class Name: AiSoqlTemplateRunner

=================================================================
=================================================================

Description: Safely runs a Data Source's SOQL template, thin and single-purpose.

Flow:
[1] Reject a blank template.
[2] Bind values via Database.queryWithBinds() - never string concatenation.
[3] Run under the given AccessLevel (defaults to USER_MODE).

=================================================================
=================================================================

Version      Date           Author                   Description
1.0          2026-09-21     Chandler Stuart          Initial development
*/

public without sharing class AiSoqlTemplateRunner {

    public static List<SObject> run(String soqlTemplate, Map<String, Object> bindValues, AccessLevel accessLevel) {
        try {

            if (String.isBlank(soqlTemplate)) return new List<SObject>();

            return Database.queryWithBinds(soqlTemplate, bindValues == null ? new Map<String, Object>() : bindValues, accessLevel == null ? System.AccessLevel.USER_MODE : accessLevel);

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AiSoqlTemplateRunner', 'run');
            return new List<SObject>();
        }
    }

}