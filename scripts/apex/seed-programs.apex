// Seeds the core programs if they don't already exist. Idempotent - safe to re-run.
// Run with: sf apex run --file scripts/apex/seed-programs.apex --target-org <alias>
// Affiliates adapting this template should edit the map below with their own program names/descriptions.

Map<String, String> programs = new Map<String, String>{
    'Peer Support' => 'Peer-based recovery support, check-ins, and listening services.',
    'Advocacy Support' => 'Advocacy and systems navigation support for participants.',
    'Job Readiness' => 'Resume building, interview preparation, and job placement support.',
    'Recovery Planning' => 'Structured recovery planning and life-rebuilding goal setting.'
};

Set<String> existingNames = new Set<String>();
for (Program existing : [SELECT Name FROM Program WHERE Name IN :programs.keySet()]) {
    existingNames.add(existing.Name);
}

List<Program> toInsert = new List<Program>();
for (String programName : programs.keySet()) {
    if (!existingNames.contains(programName)) {
        toInsert.add(new Program(
            Name = programName,
            Summary = programs.get(programName),
            StartDate = Date.today(),
            Status = 'Active'
        ));
    }
}

if (!toInsert.isEmpty()) {
    insert toInsert;
    System.debug('Created ' + toInsert.size() + ' Program record(s).');
} else {
    System.debug('All programs already exist. No records created.');
}
