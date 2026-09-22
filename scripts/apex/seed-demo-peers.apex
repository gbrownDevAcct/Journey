// Seeds a variety of demo Peers spanning intake through completion, plus a
// Probation Officer agency/contact for the court-mandated ones. Idempotent by
// Peer last name - safe to re-run. Depends on seed-programs.apex and
// seed-care-plan-catalog.apex having already run.
// Run with: sf apex run --file scripts/apex/seed-demo-peers.apex --target-org <alias>

Id peerRecordTypeId = [SELECT Id FROM RecordType WHERE SobjectType = 'Account' AND Name = 'Peer' LIMIT 1].Id;
Id peerSupportCaseRecordTypeId = [SELECT Id FROM RecordType WHERE SobjectType = 'Case' AND DeveloperName = 'LIR' LIMIT 1].Id;

Map<String, Id> programIdByName = new Map<String, Id>();
for (Program p : [SELECT Id, Name FROM Program]) {
    programIdByName.put(p.Name, p.Id);
}
Map<String, Id> templateIdByName = new Map<String, Id>();
for (CarePlanTemplate t : [SELECT Id, Name FROM CarePlanTemplate]) {
    templateIdByName.put(t.Name, t.Id);
}

// ---- Probation Officer agency + contact ----
Id agencyId;
List<Account> existingAgency = [SELECT Id FROM Account WHERE Name = 'County Probation Department' AND RecordTypeId != :peerRecordTypeId LIMIT 1];
if (!existingAgency.isEmpty()) {
    agencyId = existingAgency[0].Id;
} else {
    Account agency = new Account(Name = 'County Probation Department');
    insert agency;
    agencyId = agency.Id;
}

Id poContactId;
List<Contact> existingPO = [SELECT Id FROM Contact WHERE LastName = 'Reyes' AND FirstName = 'Dana' AND AccountId = :agencyId LIMIT 1];
if (!existingPO.isEmpty()) {
    poContactId = existingPO[0].Id;
} else {
    Contact po = new Contact(FirstName = 'Dana', LastName = 'Reyes', AccountId = agencyId, Title = 'Probation Officer');
    insert po;
    poContactId = po.Id;
}

// ---- Helper: find or create a Peer Person Account ----
Map<String, Id> peerIdByLastName = new Map<String, Id>();
for (Account a : [SELECT Id, LastName FROM Account WHERE RecordTypeId = :peerRecordTypeId AND LastName IN ('Webb','Ortiz','Boyd','Price','Lowe')]) {
    peerIdByLastName.put(a.LastName, a.Id);
}

List<Account> peersToInsert = new List<Account>();
Map<String, Account> peerDefs = new Map<String, Account>{
    'Webb' => new Account(FirstName = 'Marcus', LastName = 'Webb', RecordTypeId = peerRecordTypeId,
        PersonBirthdate = Date.valueOf('1988-04-12'), PersonGenderIdentity = 'Male', JRNY_RaceEthnicity__pc = 'Black or African American'),
    'Ortiz' => new Account(FirstName = 'Danielle', LastName = 'Ortiz', RecordTypeId = peerRecordTypeId,
        PersonBirthdate = Date.valueOf('1993-11-02'), PersonGenderIdentity = 'Female', JRNY_RaceEthnicity__pc = 'Hispanic or Latino'),
    'Boyd' => new Account(FirstName = 'Terrence', LastName = 'Boyd', RecordTypeId = peerRecordTypeId,
        PersonBirthdate = Date.valueOf('1979-02-20'), PersonGenderIdentity = 'Male', JRNY_RaceEthnicity__pc = 'White'),
    'Price' => new Account(FirstName = 'Angela', LastName = 'Price', RecordTypeId = peerRecordTypeId,
        PersonBirthdate = Date.valueOf('1985-07-30'), PersonGenderIdentity = 'Female', JRNY_RaceEthnicity__pc = 'Two or More Races'),
    'Lowe' => new Account(FirstName = 'Kevin', LastName = 'Lowe', RecordTypeId = peerRecordTypeId,
        PersonBirthdate = Date.valueOf('1991-09-15'), PersonGenderIdentity = 'Male', JRNY_RaceEthnicity__pc = 'American Indian or Alaska Native')
};
for (String lastName : peerDefs.keySet()) {
    if (!peerIdByLastName.containsKey(lastName)) {
        peersToInsert.add(peerDefs.get(lastName));
    }
}
if (!peersToInsert.isEmpty()) {
    insert peersToInsert;
    for (Account a : peersToInsert) {
        peerIdByLastName.put(a.LastName, a.Id);
    }
}

// Need each Peer's Contact Id (Case/ApplicationForm/ProgramEnrollment reference Contact, not Account)
Map<String, Id> peerContactIdByLastName = new Map<String, Id>();
for (Account a : [SELECT Id, PersonContactId FROM Account WHERE Id IN :peerIdByLastName.values()]) {
    for (String lastName : peerIdByLastName.keySet()) {
        if (peerIdByLastName.get(lastName) == a.Id) {
            peerContactIdByLastName.put(lastName, a.PersonContactId);
        }
    }
}

// ---- Court Orders for the two court-mandated peers ----
Map<String, Id> courtOrderIdByLastName = new Map<String, Id>();
for (JRNY_Court_Order__c co : [SELECT Id, Participant__c FROM JRNY_Court_Order__c WHERE Participant__c IN :peerIdByLastName.values()]) {
    for (String lastName : peerIdByLastName.keySet()) {
        if (peerIdByLastName.get(lastName) == co.Participant__c) {
            courtOrderIdByLastName.put(lastName, co.Id);
        }
    }
}
List<JRNY_Court_Order__c> courtOrdersToInsert = new List<JRNY_Court_Order__c>();
if (!courtOrderIdByLastName.containsKey('Ortiz')) {
    courtOrdersToInsert.add(new JRNY_Court_Order__c(
        Participant__c = peerIdByLastName.get('Ortiz'), Issuing_Court__c = 'County District Court',
        Judge_Name__c = 'Hon. A. Sample', Docket_Number__c = '2026-CR-04471',
        Order_Date__c = Date.valueOf('2026-06-01'), Probation_Officer__c = poContactId
    ));
}
if (!courtOrderIdByLastName.containsKey('Boyd')) {
    courtOrdersToInsert.add(new JRNY_Court_Order__c(
        Participant__c = peerIdByLastName.get('Boyd'), Issuing_Court__c = 'County District Court',
        Judge_Name__c = 'Hon. A. Sample', Docket_Number__c = '2026-CR-03108',
        Order_Date__c = Date.valueOf('2026-05-10'), Probation_Officer__c = poContactId
    ));
}
if (!courtOrdersToInsert.isEmpty()) {
    insert courtOrdersToInsert;
    for (JRNY_Court_Order__c co : courtOrdersToInsert) {
        for (String lastName : peerIdByLastName.keySet()) {
            if (peerIdByLastName.get(lastName) == co.Participant__c) {
                courtOrderIdByLastName.put(lastName, co.Id);
            }
        }
    }
}

// ---- Cases (Peer Support Case record type; Contact set here auto-creates the Case Participant via flow) ----
Map<String, Id> caseIdByLastName = new Map<String, Id>();
for (Case c : [SELECT Id, ContactId FROM Case WHERE ContactId IN :peerContactIdByLastName.values() AND RecordTypeId = :peerSupportCaseRecordTypeId]) {
    for (String lastName : peerContactIdByLastName.keySet()) {
        if (peerContactIdByLastName.get(lastName) == c.ContactId) {
            caseIdByLastName.put(lastName, c.Id);
        }
    }
}
List<Case> casesToInsert = new List<Case>();
for (String lastName : new List<String>{ 'Ortiz', 'Boyd', 'Price', 'Lowe' }) {
    if (!caseIdByLastName.containsKey(lastName)) {
        casesToInsert.add(new Case(
            RecordTypeId = peerSupportCaseRecordTypeId,
            ContactId = peerContactIdByLastName.get(lastName),
            Subject = 'Peer Support - ' + lastName,
            Origin = 'Web',
            Priority = 'Medium'
        ));
    }
}
if (!casesToInsert.isEmpty()) {
    insert casesToInsert;
    for (Case c : casesToInsert) {
        for (String lastName : peerContactIdByLastName.keySet()) {
            if (peerContactIdByLastName.get(lastName) == c.ContactId) {
                caseIdByLastName.put(lastName, c.Id);
            }
        }
    }
}

// ---- Application Forms ----
// lastName => [program, stage]
Map<String, List<String>> applicationDefs = new Map<String, List<String>>{
    'Webb' => new List<String>{ 'Peer Support', 'Submitted' },
    'Ortiz' => new List<String>{ 'Peer Support', 'Approved' },
    'Price' => new List<String>{ 'Peer Support', 'Approved' },
    'Lowe' => new List<String>{ 'Peer Support', 'Approved' }
};
Set<String> existingApplicants = new Set<String>();
for (ApplicationForm af : [SELECT ContactId FROM ApplicationForm WHERE ContactId IN :peerContactIdByLastName.values()]) {
    for (String lastName : peerContactIdByLastName.keySet()) {
        if (peerContactIdByLastName.get(lastName) == af.ContactId) {
            existingApplicants.add(lastName);
        }
    }
}
List<ApplicationForm> applicationsToInsert = new List<ApplicationForm>();
for (String lastName : applicationDefs.keySet()) {
    if (!existingApplicants.contains(lastName)) {
        List<String> refs = applicationDefs.get(lastName);
        applicationsToInsert.add(new ApplicationForm(
            ContactId = peerContactIdByLastName.get(lastName),
            ReferenceRecordId = programIdByName.get(refs[0]),
            Stage = refs[1],
            UsageType = 'Program',
            SubmissionDate = Date.today().addMonths(-3)
        ));
    }
}
// Boyd applies to two programs (mandated Peer Support + elective Job Readiness)
if (!existingApplicants.contains('Boyd')) {
    applicationsToInsert.add(new ApplicationForm(
        ContactId = peerContactIdByLastName.get('Boyd'), ReferenceRecordId = programIdByName.get('Peer Support'),
        Stage = 'Approved', UsageType = 'Program', SubmissionDate = Date.today().addMonths(-4)
    ));
    applicationsToInsert.add(new ApplicationForm(
        ContactId = peerContactIdByLastName.get('Boyd'), ReferenceRecordId = programIdByName.get('Job Readiness'),
        Stage = 'Approved', UsageType = 'Program', SubmissionDate = Date.today().addMonths(-2)
    ));
}
if (!applicationsToInsert.isEmpty()) {
    insert applicationsToInsert;
}

// ---- Program Enrollments ----
Set<String> existingEnrollmentKeys = new Set<String>();
for (ProgramEnrollment pe : [SELECT ContactId, ProgramId FROM ProgramEnrollment WHERE ContactId IN :peerContactIdByLastName.values()]) {
    existingEnrollmentKeys.add(pe.ContactId + '-' + pe.ProgramId);
}
List<ProgramEnrollment> enrollmentsToInsert = new List<ProgramEnrollment>();

// Webb: applied only, no enrollment yet.

// Ortiz: court-mandated, in progress, on-site
Id ortizPeerSupportId = programIdByName.get('Peer Support');
if (!existingEnrollmentKeys.contains(peerContactIdByLastName.get('Ortiz') + '-' + ortizPeerSupportId)) {
    enrollmentsToInsert.add(new ProgramEnrollment(
        ContactId = peerContactIdByLastName.get('Ortiz'), ProgramId = ortizPeerSupportId,
        Status = 'In Progress', StartDate = Date.today().addMonths(-3), ApplicationDate = Date.today().addMonths(-4),
        JRNY_Enrollment_Source__c = 'Court-Mandated', JRNY_Residency_Status__c = 'On-Site',
        JRNY_Court_Order__c = courtOrderIdByLastName.get('Ortiz'),
        SessionsAttendedCount = 10, SessionsAbsentCount = 1
    ));
}

// Boyd: court-mandated, in progress, approved off-site, multi-program
Id boydPeerSupportId = programIdByName.get('Peer Support');
Id boydJobReadinessId = programIdByName.get('Job Readiness');
if (!existingEnrollmentKeys.contains(peerContactIdByLastName.get('Boyd') + '-' + boydPeerSupportId)) {
    enrollmentsToInsert.add(new ProgramEnrollment(
        ContactId = peerContactIdByLastName.get('Boyd'), ProgramId = boydPeerSupportId,
        Status = 'In Progress', StartDate = Date.today().addMonths(-4), ApplicationDate = Date.today().addMonths(-5),
        JRNY_Enrollment_Source__c = 'Court-Mandated', JRNY_Residency_Status__c = 'Approved Off-Site',
        JRNY_Court_Order__c = courtOrderIdByLastName.get('Boyd'),
        JRNY_Offsite_Approved_By__c = poContactId, JRNY_Offsite_Approved_Date__c = Date.today().addMonths(-1),
        SessionsAttendedCount = 14, SessionsAbsentCount = 2
    ));
}
if (!existingEnrollmentKeys.contains(peerContactIdByLastName.get('Boyd') + '-' + boydJobReadinessId)) {
    enrollmentsToInsert.add(new ProgramEnrollment(
        ContactId = peerContactIdByLastName.get('Boyd'), ProgramId = boydJobReadinessId,
        Status = 'In Progress', StartDate = Date.today().addMonths(-2), ApplicationDate = Date.today().addMonths(-2),
        JRNY_Enrollment_Source__c = 'Self-Referred',
        SessionsAttendedCount = 6, SessionsAbsentCount = 0
    ));
}

// Price: completed
Id pricePeerSupportId = programIdByName.get('Peer Support');
if (!existingEnrollmentKeys.contains(peerContactIdByLastName.get('Price') + '-' + pricePeerSupportId)) {
    enrollmentsToInsert.add(new ProgramEnrollment(
        ContactId = peerContactIdByLastName.get('Price'), ProgramId = pricePeerSupportId,
        Status = 'Completed', StartDate = Date.today().addMonths(-8), EndDate = Date.today().addMonths(-1),
        ApplicationDate = Date.today().addMonths(-9), JRNY_Enrollment_Source__c = 'Self-Referred',
        JRNY_Residency_Status__c = 'Discharged',
        SessionsAttendedCount = 30, SessionsAbsentCount = 2
    ));
}

// Lowe: withdrawn
Id lowePeerSupportId = programIdByName.get('Peer Support');
if (!existingEnrollmentKeys.contains(peerContactIdByLastName.get('Lowe') + '-' + lowePeerSupportId)) {
    enrollmentsToInsert.add(new ProgramEnrollment(
        ContactId = peerContactIdByLastName.get('Lowe'), ProgramId = lowePeerSupportId,
        Status = 'Withdrawn', StartDate = Date.today().addMonths(-5), EndDate = Date.today().addMonths(-3),
        ApplicationDate = Date.today().addMonths(-6), JRNY_Enrollment_Source__c = 'Self-Referred',
        JRNY_Residency_Status__c = 'Discharged',
        SessionsAttendedCount = 5, SessionsAbsentCount = 6
    ));
}

if (!enrollmentsToInsert.isEmpty()) {
    insert enrollmentsToInsert;
}

// ---- Care Plans (Peer Support, for everyone with a Case) ----
Map<String, String> carePlanStatusByLastName = new Map<String, String>{
    'Ortiz' => 'Active', 'Boyd' => 'Active', 'Price' => 'Completed', 'Lowe' => 'Cancelled'
};
Set<Id> existingCarePlanCaseIds = new Set<Id>();
for (CarePlan cp : [SELECT CaseId FROM CarePlan WHERE CaseId IN :caseIdByLastName.values()]) {
    existingCarePlanCaseIds.add(cp.CaseId);
}
List<CarePlan> carePlansToInsert = new List<CarePlan>();
for (String lastName : carePlanStatusByLastName.keySet()) {
    Id caseId = caseIdByLastName.get(lastName);
    if (!existingCarePlanCaseIds.contains(caseId)) {
        carePlansToInsert.add(new CarePlan(
            Name = lastName + ' - Peer Support Care Plan',
            CaseId = caseId,
            ParticipantId = peerContactIdByLastName.get(lastName),
            CarePlanTemplateId = templateIdByName.get('Peer Support - Standard Care Plan'),
            Status = carePlanStatusByLastName.get(lastName),
            StartDate = Date.today().addMonths(-3)
        ));
    }
}
if (!carePlansToInsert.isEmpty()) {
    insert carePlansToInsert;
}

System.debug('Peers created: ' + peersToInsert.size());
System.debug('Court Orders created: ' + courtOrdersToInsert.size());
System.debug('Cases created: ' + casesToInsert.size());
System.debug('Application Forms created: ' + applicationsToInsert.size());
System.debug('Program Enrollments created: ' + enrollmentsToInsert.size());
System.debug('Care Plans created: ' + carePlansToInsert.size());
