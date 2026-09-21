// Seeds the Goal Definition and Benefit catalogs, then builds one primary
// Care Plan Template per Program with its associated goals and benefits.
// Idempotent - safe to re-run. Templates are left in Draft status - Care Plan
// Templates cannot be edited or deleted once Published, so publishing is a
// deliberate separate step once the content has been reviewed.
// Run with: sf apex run --file scripts/apex/seed-care-plan-catalog.apex --target-org <alias>
// Affiliates adapting this template should edit the maps below.

// ---- 1. Look up existing Programs ----
Map<String, Id> programIdByName = new Map<String, Id>();
for (Program p : [SELECT Id, Name FROM Program]) {
    programIdByName.put(p.Name, p.Id);
}

// ---- 2a. Top-level Goal Definitions (one per category) ----
Set<String> topLevelGoalNames = new Set<String>{
    'Recovery & Sobriety',
    'Housing & Stability',
    'Employment & Income',
    'Advocacy & Systems Navigation',
    'Social & Family Support',
    'Life Skills & Independence'
};

Map<String, Id> goalIdByName = new Map<String, Id>();
for (GoalDefinition g : [SELECT Id, Name FROM GoalDefinition WHERE Name IN :topLevelGoalNames]) {
    goalIdByName.put(g.Name, g.Id);
}
List<GoalDefinition> topLevelGoalsToInsert = new List<GoalDefinition>();
for (String goalName : topLevelGoalNames) {
    if (!goalIdByName.containsKey(goalName)) {
        topLevelGoalsToInsert.add(new GoalDefinition(
            Name = goalName,
            Category = goalName,
            Type = 'Strategic',
            Status = 'Active'
        ));
    }
}
if (!topLevelGoalsToInsert.isEmpty()) {
    insert topLevelGoalsToInsert;
    for (GoalDefinition g : topLevelGoalsToInsert) {
        goalIdByName.put(g.Name, g.Id);
    }
}

// ---- 2b. Intermediate Goal Definitions (reusable catalog, each nested under a top-level goal) ----
// name => parent top-level goal name
Map<String, String> goalCategoryByName = new Map<String, String>{
    'Maintain Sobriety' => 'Recovery & Sobriety',
    'Attend Weekly Peer Check-Ins' => 'Recovery & Sobriety',
    'Complete Individualized Recovery Plan Review' => 'Recovery & Sobriety',
    'Build a Personal Support Network' => 'Social & Family Support',
    'Access Public Benefits and Entitlements' => 'Advocacy & Systems Navigation',
    'Resolve Outstanding Legal Matter' => 'Advocacy & Systems Navigation',
    'Complete Resume and Job Application Materials' => 'Employment & Income',
    'Secure Stable Employment' => 'Employment & Income',
    'Secure Stable Housing' => 'Housing & Stability',
    'Develop Household Management Skills' => 'Life Skills & Independence',
    'Learn Meal Planning and Budgeting' => 'Life Skills & Independence',
    'Complete a Life Skills or Home Economics Course' => 'Life Skills & Independence'
};

Map<String, Id> existingIntermediateGoalIds = new Map<String, Id>();
List<GoalDefinition> intermediateGoalsToUpdate = new List<GoalDefinition>();
for (GoalDefinition g : [SELECT Id, Name, ParentGoalId, Type FROM GoalDefinition WHERE Name IN :goalCategoryByName.keySet()]) {
    existingIntermediateGoalIds.put(g.Name, g.Id);
    Id expectedParentId = goalIdByName.get(goalCategoryByName.get(g.Name));
    if (g.ParentGoalId != expectedParentId || g.Type != 'Individual') {
        g.ParentGoalId = expectedParentId;
        g.Type = 'Individual';
        intermediateGoalsToUpdate.add(g);
    }
}
if (!intermediateGoalsToUpdate.isEmpty()) {
    update intermediateGoalsToUpdate;
}

List<GoalDefinition> goalsToInsert = new List<GoalDefinition>();
for (String goalName : goalCategoryByName.keySet()) {
    if (!existingIntermediateGoalIds.containsKey(goalName)) {
        goalsToInsert.add(new GoalDefinition(
            Name = goalName,
            Category = goalCategoryByName.get(goalName),
            Type = 'Individual',
            ParentGoalId = goalIdByName.get(goalCategoryByName.get(goalName)),
            Status = 'Active'
        ));
    }
}
if (!goalsToInsert.isEmpty()) {
    insert goalsToInsert;
    for (GoalDefinition g : goalsToInsert) {
        goalIdByName.put(g.Name, g.Id);
    }
}
for (String goalName : existingIntermediateGoalIds.keySet()) {
    goalIdByName.put(goalName, existingIntermediateGoalIds.get(goalName));
}

// ---- 3a. Unit of Measure (Benefit Type requires one) ----
Id sessionUnitId;
List<UnitOfMeasure> existingUnits = [SELECT Id FROM UnitOfMeasure WHERE Name = 'Session' LIMIT 1];
if (!existingUnits.isEmpty()) {
    sessionUnitId = existingUnits[0].Id;
} else {
    UnitOfMeasure sessionUnit = new UnitOfMeasure(Name = 'Session', UnitCode = 'SESSION');
    insert sessionUnit;
    sessionUnitId = sessionUnit.Id;
}

// ---- 3b. Benefit Types (reusable catalog) ----
Set<String> benefitTypeNames = new Set<String>{
    'Peer Support Services', 'Advocacy Services', 'Employment Services',
    'Recovery Planning Services', 'Life Skills Services'
};
Map<String, Id> benefitTypeIdByName = new Map<String, Id>();
for (BenefitType bt : [SELECT Id, Name FROM BenefitType WHERE Name IN :benefitTypeNames]) {
    benefitTypeIdByName.put(bt.Name, bt.Id);
}
List<BenefitType> benefitTypesToInsert = new List<BenefitType>();
for (String btName : benefitTypeNames) {
    if (!benefitTypeIdByName.containsKey(btName)) {
        benefitTypesToInsert.add(new BenefitType(
            Name = btName,
            UnitofMeasureId = sessionUnitId,
            ProcessType = 'ProgramManagement'
        ));
    }
}
if (!benefitTypesToInsert.isEmpty()) {
    insert benefitTypesToInsert;
    for (BenefitType bt : benefitTypesToInsert) {
        benefitTypeIdByName.put(bt.Name, bt.Id);
    }
}

// ---- 4. Benefits (tied to a Benefit Type + Program) ----
// name => [benefitType, program]
Map<String, List<String>> benefitDefs = new Map<String, List<String>>{
    'Weekly Peer Check-In' => new List<String>{ 'Peer Support Services', 'Peer Support' },
    'Recovery Coaching Session' => new List<String>{ 'Peer Support Services', 'Peer Support' },
    'Benefits Enrollment Assistance' => new List<String>{ 'Advocacy Services', 'Advocacy Support' },
    'Legal Navigation Consultation' => new List<String>{ 'Advocacy Services', 'Advocacy Support' },
    'Resume and Interview Coaching' => new List<String>{ 'Employment Services', 'Job Readiness' },
    'Job Placement Assistance' => new List<String>{ 'Employment Services', 'Job Readiness' },
    'Recovery Plan Development Session' => new List<String>{ 'Recovery Planning Services', 'Recovery Planning' },
    'Home Economics Workshop' => new List<String>{ 'Life Skills Services', 'Recovery Planning' },
    'Budgeting and Meal Planning Session' => new List<String>{ 'Life Skills Services', 'Recovery Planning' }
};
Map<String, Id> benefitIdByName = new Map<String, Id>();
for (Benefit b : [SELECT Id, Name FROM Benefit WHERE Name IN :benefitDefs.keySet()]) {
    benefitIdByName.put(b.Name, b.Id);
}
List<Benefit> benefitsToInsert = new List<Benefit>();
for (String bName : benefitDefs.keySet()) {
    if (!benefitIdByName.containsKey(bName)) {
        List<String> refs = benefitDefs.get(bName);
        benefitsToInsert.add(new Benefit(
            Name = bName,
            BenefitTypeId = benefitTypeIdByName.get(refs[0]),
            ProgramId = programIdByName.get(refs[1]),
            UnitId = sessionUnitId,
            IsActive = true,
            BenefitStatus = 'Active'
        ));
    }
}
if (!benefitsToInsert.isEmpty()) {
    insert benefitsToInsert;
    for (Benefit b : benefitsToInsert) {
        benefitIdByName.put(b.Name, b.Id);
    }
}

// ---- 5. Care Plan Templates (one primary Draft template per Program) ----
Map<String, String> templateDefs = new Map<String, String>{
    'Peer Support - Standard Care Plan' => 'Peer Support',
    'Advocacy Support - Standard Care Plan' => 'Advocacy Support',
    'Job Readiness - Standard Care Plan' => 'Job Readiness',
    'Recovery Planning - Standard Care Plan' => 'Recovery Planning'
};
Map<String, Id> templateIdByName = new Map<String, Id>();
for (CarePlanTemplate t : [SELECT Id, Name FROM CarePlanTemplate WHERE Name IN :templateDefs.keySet()]) {
    templateIdByName.put(t.Name, t.Id);
}
List<CarePlanTemplate> templatesToInsert = new List<CarePlanTemplate>();
for (String tName : templateDefs.keySet()) {
    if (!templateIdByName.containsKey(tName)) {
        templatesToInsert.add(new CarePlanTemplate(
            Name = tName,
            Status = 'Draft'
        ));
    }
}
if (!templatesToInsert.isEmpty()) {
    insert templatesToInsert;
    for (CarePlanTemplate t : templatesToInsert) {
        templateIdByName.put(t.Name, t.Id);
    }
}

// ---- 6. Link goals to templates by Program ----
// Each list includes the relevant top-level goal(s) alongside their intermediate children,
// so the hierarchy is visible on the Care Plan Template itself, not just in the catalog.
Map<String, List<String>> goalsByProgram = new Map<String, List<String>>{
    'Peer Support' => new List<String>{
        'Recovery & Sobriety', 'Maintain Sobriety', 'Attend Weekly Peer Check-Ins',
        'Social & Family Support', 'Build a Personal Support Network'
    },
    'Advocacy Support' => new List<String>{
        'Advocacy & Systems Navigation', 'Access Public Benefits and Entitlements', 'Resolve Outstanding Legal Matter'
    },
    'Job Readiness' => new List<String>{
        'Employment & Income', 'Complete Resume and Job Application Materials', 'Secure Stable Employment'
    },
    'Recovery Planning' => new List<String>{
        'Housing & Stability', 'Secure Stable Housing',
        'Recovery & Sobriety', 'Complete Individualized Recovery Plan Review',
        'Life Skills & Independence', 'Develop Household Management Skills',
        'Learn Meal Planning and Budgeting', 'Complete a Life Skills or Home Economics Course'
    }
};

Set<String> existingGoalLinks = new Set<String>();
for (CarePlanTemplateGoal cptg : [SELECT CarePlanTemplateId, GoalDefinitionId FROM CarePlanTemplateGoal]) {
    existingGoalLinks.add(cptg.CarePlanTemplateId + '-' + cptg.GoalDefinitionId);
}

List<CarePlanTemplateGoal> goalLinksToInsert = new List<CarePlanTemplateGoal>();
for (String templateName : templateDefs.keySet()) {
    String programName = templateDefs.get(templateName);
    Id templateId = templateIdByName.get(templateName);
    for (String goalName : goalsByProgram.get(programName)) {
        Id goalId = goalIdByName.get(goalName);
        String key = templateId + '-' + goalId;
        if (!existingGoalLinks.contains(key)) {
            goalLinksToInsert.add(new CarePlanTemplateGoal(
                CarePlanTemplateId = templateId,
                GoalDefinitionId = goalId,
                Priority = 'Medium'
            ));
        }
    }
}
if (!goalLinksToInsert.isEmpty()) {
    insert goalLinksToInsert;
}

// ---- 7. Link benefits to templates by Program ----
Set<String> existingBenefitLinks = new Set<String>();
for (CarePlanTemplateBenefit cptb : [SELECT CarePlanTemplateId, BenefitId FROM CarePlanTemplateBenefit]) {
    existingBenefitLinks.add(cptb.CarePlanTemplateId + '-' + cptb.BenefitId);
}

List<CarePlanTemplateBenefit> benefitLinksToInsert = new List<CarePlanTemplateBenefit>();
for (String benefitName : benefitDefs.keySet()) {
    String programName = benefitDefs.get(benefitName)[1];
    for (String templateName : templateDefs.keySet()) {
        if (templateDefs.get(templateName) == programName) {
            Id templateId = templateIdByName.get(templateName);
            Id benefitId = benefitIdByName.get(benefitName);
            String key = templateId + '-' + benefitId;
            if (!existingBenefitLinks.contains(key)) {
                benefitLinksToInsert.add(new CarePlanTemplateBenefit(
                    CarePlanTemplateId = templateId,
                    BenefitId = benefitId,
                    Priority = 'Medium'
                ));
            }
        }
    }
}
if (!benefitLinksToInsert.isEmpty()) {
    insert benefitLinksToInsert;
}

System.debug('Top-Level Goal Definitions inserted: ' + topLevelGoalsToInsert.size());
System.debug('Intermediate Goal Definitions inserted: ' + goalsToInsert.size());
System.debug('Intermediate Goal Definitions updated (hierarchy backfill): ' + intermediateGoalsToUpdate.size());
System.debug('Benefit Types inserted: ' + benefitTypesToInsert.size());
System.debug('Benefits inserted: ' + benefitsToInsert.size());
System.debug('Care Plan Templates inserted: ' + templatesToInsert.size());
System.debug('Goal links inserted: ' + goalLinksToInsert.size());
System.debug('Benefit links inserted: ' + benefitLinksToInsert.size());
