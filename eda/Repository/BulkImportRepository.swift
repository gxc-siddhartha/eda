import CoreData
import Foundation
import SwiftCSV
import os.log

// MARK: - Bulk Import Repository Error Types
enum BulkImportRepositoryError: LocalizedError {
    case csvParsingError(String)
    case semesterNotFound(String)
    case coreDataError(String)
    case invalidRowData(String, Int)  // message, row number

    var errorDescription: String? {
        switch self {
        case .csvParsingError(let details):
            return "CSV parsing error: \(details)"
        case .semesterNotFound(let details):
            return "Semester not found: \(details)"
        case .coreDataError(let details):
            return "Core Data error: \(details)"
        case .invalidRowData(let details, let rowNumber):
            return "Invalid data in row \(rowNumber): \(details)"
        }
    }
}

// MARK: - Bulk Import Result
struct BulkImportResult {
    let totalRows: Int
    let successfulImports: Int
    let skippedRows: Int
    let errors: [BulkImportRowError]
}

struct BulkImportRowError {
    let rowNumber: Int
    let error: Error
    let rowData: [String: String]
}

/// Repository responsible for bulk-importing data into Core Data
class BulkImportRepository {
    private let persistentContainer: NSPersistentContainer
    private let backgroundContext: NSManagedObjectContext
    private let logger = Logger(
        subsystem: "com.eda.app",
        category: "BulkImportRepository"
    )

    init(
        persistentContainer: NSPersistentContainer = PersistenceController
            .shared.container
    ) {
        self.persistentContainer = persistentContainer
        self.backgroundContext = persistentContainer.newBackgroundContext()
        self.backgroundContext.mergePolicy =
            NSMergeByPropertyObjectTrumpMergePolicy
    }

    /// Bulk imports subjects from CSV content into the given semester.
    ///
    /// - Parameters:
    ///   - content: CSV file content as string
    ///   - fileName: Original filename for logging purposes
    ///   - semester: The Semester entity to which all imported subjects will belong.
    ///
    /// CSV must have headers: `Name`, `Teacher`, `Color`, and optionally `Icon`.
    /// Subject IDs are generated via `UUID()` during import.
    ///
    /// - Returns: BulkImportResult containing statistics about the import operation
    func bulkImportSubjects(
        content: String,
        fileName: String,
        for semester: Semester
    ) async throws -> BulkImportResult {
        self.logger.info(
            "🚀 Starting bulk subject import from: \(fileName) for semester: \(semester.semesterName ?? "unknown")"
        )

        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    // Get semester in background context
                    guard
                        let backgroundSemester = try? self.backgroundContext
                            .existingObject(with: semester.objectID)
                            as? Semester
                    else {
                        let error = BulkImportRepositoryError.semesterNotFound(
                            "Semester not found in background context"
                        )
                        self.logger.error("❌ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }

                    // Parse CSV from content string
                    let csv: NamedCSV
                    do {
                        csv = try NamedCSV(string: content)
                    } catch {
                        let wrappedError =
                            BulkImportRepositoryError.csvParsingError(
                                "Failed to parse CSV: \(error.localizedDescription)"
                            )
                        self.logger.error(
                            "❌ \(wrappedError.localizedDescription)"
                        )
                        continuation.resume(throwing: wrappedError)
                        return
                    }

                    let rows = csv.rows
                    self.logger.debug(
                        "📊 Found \(rows.count) subject rows to process"
                    )

                    var successfulImports = 0
                    var skippedRows = 0
                    var errors: [BulkImportRowError] = []

                    // Process each row
                    for (index, row) in rows.enumerated() {
                        let rowNumber = index + 1  // 1-based for user-friendly error reporting

                        do {
                            // Extract and validate required fields
                            guard
                                let name = row["Name"]?.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ), !name.isEmpty
                            else {
                                throw BulkImportRepositoryError.invalidRowData(
                                    "Missing or empty 'Name' field",
                                    rowNumber
                                )
                            }

                            guard
                                let teacher = row["Teacher"]?
                                    .trimmingCharacters(
                                        in: .whitespacesAndNewlines
                                    ), !teacher.isEmpty
                            else {
                                throw BulkImportRepositoryError.invalidRowData(
                                    "Missing or empty 'Teacher' field",
                                    rowNumber
                                )
                            }

                            guard
                                let color = row["Color"]?.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ), !color.isEmpty
                            else {
                                throw BulkImportRepositoryError.invalidRowData(
                                    "Missing or empty 'Color' field",
                                    rowNumber
                                )
                            }

                            // Icon is optional
                            let icon = row["Icon"]?.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )

                            // Check for duplicate subject name in the same semester
                            let isDuplicate =
                                try self.checkForDuplicateSubjectNameSync(
                                    name,
                                    in: backgroundSemester
                                )
                            if isDuplicate {
                                self.logger.warning(
                                    "⚠️ Skipping duplicate subject '\(name)' in row \(rowNumber)"
                                )
                                skippedRows += 1
                                continue
                            }

                            // Create new subject directly in background context
                            let newSubject = Subject(
                                context: self.backgroundContext
                            )
                            newSubject.subjectName = name.capitalized
                            newSubject.subjectTeacher = teacher.capitalized
                            newSubject.subjectColor = color
                            newSubject.subjectIcon = icon
                            newSubject.subjectId = UUID()
                            newSubject.semester = backgroundSemester

                            successfulImports += 1
                            self.logger.debug(
                                "✅ Processed subject '\(name)' (row \(rowNumber))"
                            )

                        } catch {
                            self.logger.warning(
                                "⚠️ Error processing row \(rowNumber): \(error.localizedDescription)"
                            )
                            errors.append(
                                BulkImportRowError(
                                    rowNumber: rowNumber,
                                    error: error,
                                    rowData: row
                                )
                            )
                        }
                    }

                    // Save all changes at once
                    if successfulImports > 0 {
                        do {
                            try self.backgroundContext.save()
                            self.logger.info(
                                "💾 Saved \(successfulImports) subjects to Core Data"
                            )
                        } catch {
                            let wrappedError =
                                BulkImportRepositoryError.coreDataError(
                                    "Failed to save subjects: \(error.localizedDescription)"
                                )
                            self.logger.error(
                                "❌ \(wrappedError.localizedDescription)"
                            )
                            continuation.resume(throwing: wrappedError)
                            return
                        }
                    }

                    let result = BulkImportResult(
                        totalRows: rows.count,
                        successfulImports: successfulImports,
                        skippedRows: skippedRows,
                        errors: errors
                    )

                    self.logger.info(
                        "🎉 Subject bulk import completed: \(successfulImports) imported, \(skippedRows) skipped, \(errors.count) errors"
                    )
                    continuation.resume(returning: result)

                } catch let error as BulkImportRepositoryError {
                    continuation.resume(throwing: error)
                } catch {
                    let wrappedError = BulkImportRepositoryError.coreDataError(
                        "Unexpected error during subject bulk import: \(error.localizedDescription)"
                    )
                    self.logger.error("❌ \(wrappedError.localizedDescription)")
                    continuation.resume(throwing: wrappedError)
                }
            }
        }
    }

    /// Bulk imports schedules from CSV content into the given semester.
    ///
    /// - Parameters:
    ///   - content: CSV file content as string
    ///   - fileName: Original filename for logging purposes
    ///   - semester: The Semester entity to which all imported schedules will belong.
    ///
    /// CSV must have headers: `Subject Name`, `Day`, `Start Time`, `End Time`, and optionally `Location`.
    /// Schedule IDs are generated via `UUID()` during import.
    /// Times should be in format "HH:mm" (e.g., "09:30", "14:15")
    ///
    /// - Returns: BulkImportResult containing statistics about the import operation
    func bulkImportSchedules(
        content: String,
        fileName: String,
        for semester: Semester
    ) async throws -> BulkImportResult {
        self.logger.info(
            "🗓️ Starting schedule bulk import from: \(fileName) for semester: \(semester.semesterName ?? "unknown")"
        )

        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    // Get semester in background context
                    guard
                        let backgroundSemester = try? self.backgroundContext
                            .existingObject(with: semester.objectID)
                            as? Semester
                    else {
                        let error = BulkImportRepositoryError.semesterNotFound(
                            "Semester not found in background context"
                        )
                        self.logger.error("❌ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }

                    // Parse CSV from content string
                    let csv: NamedCSV
                    do {
                        csv = try NamedCSV(string: content)
                    } catch {
                        let wrappedError =
                            BulkImportRepositoryError.csvParsingError(
                                "Failed to parse CSV: \(error.localizedDescription)"
                            )
                        self.logger.error(
                            "❌ \(wrappedError.localizedDescription)"
                        )
                        continuation.resume(throwing: wrappedError)
                        return
                    }

                    let rows = csv.rows
                    self.logger.debug(
                        "📊 Found \(rows.count) schedule rows to process"
                    )

                    var successfulImports = 0
                    var skippedRows = 0
                    var errors: [BulkImportRowError] = []

                    // Create date formatter for time parsing
                    let timeFormatter = DateFormatter()
                    timeFormatter.dateFormat = "HH:mm"
                    timeFormatter.timeZone = TimeZone.current

                    // Process each row
                    for (index, row) in rows.enumerated() {
                        let rowNumber = index + 1  // 1-based for user-friendly error reporting

                        do {
                            // Extract and validate required fields
                            guard
                                let subjectName = row["Subject Name"]?
                                    .trimmingCharacters(
                                        in: .whitespacesAndNewlines
                                    ), !subjectName.isEmpty
                            else {
                                throw BulkImportRepositoryError.invalidRowData(
                                    "Missing or empty 'Subject Name' field",
                                    rowNumber
                                )
                            }

                            guard
                                let day = row["Day"]?.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ), !day.isEmpty
                            else {
                                throw BulkImportRepositoryError.invalidRowData(
                                    "Missing or empty 'Day' field",
                                    rowNumber
                                )
                            }

                            guard
                                let startTimeString = row["Start Time"]?
                                    .trimmingCharacters(
                                        in: .whitespacesAndNewlines
                                    ), !startTimeString.isEmpty
                            else {
                                throw BulkImportRepositoryError.invalidRowData(
                                    "Missing or empty 'Start Time' field",
                                    rowNumber
                                )
                            }

                            guard
                                let endTimeString = row["End Time"]?
                                    .trimmingCharacters(
                                        in: .whitespacesAndNewlines
                                    ), !endTimeString.isEmpty
                            else {
                                throw BulkImportRepositoryError.invalidRowData(
                                    "Missing or empty 'End Time' field",
                                    rowNumber
                                )
                            }

                            // Location is optional
                            let location =
                                row["Location"]?.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ) ?? ""

                            // Parse start and end times
                            guard
                                let startTime = timeFormatter.date(
                                    from: startTimeString
                                )
                            else {
                                throw BulkImportRepositoryError.invalidRowData(
                                    "Invalid Start Time format '\(startTimeString)'. Use HH:mm format (e.g., 09:30)",
                                    rowNumber
                                )
                            }

                            guard
                                let endTime = timeFormatter.date(
                                    from: endTimeString
                                )
                            else {
                                throw BulkImportRepositoryError.invalidRowData(
                                    "Invalid End Time format '\(endTimeString)'. Use HH:mm format (e.g., 14:15)",
                                    rowNumber
                                )
                            }

                            // Validate that end time is after start time
                            if endTime <= startTime {
                                throw BulkImportRepositoryError.invalidRowData(
                                    "End time must be after start time",
                                    rowNumber
                                )
                            }

                            // Find the subject by name in the semester
                            let subjectFetchRequest: NSFetchRequest<Subject> =
                                Subject.fetchRequest()
                            subjectFetchRequest.predicate = NSCompoundPredicate(
                                andPredicateWithSubpredicates: [
                                    NSPredicate(
                                        format: "subjectName ==[c] %@",
                                        subjectName
                                    ),
                                    NSPredicate(
                                        format: "semester == %@",
                                        backgroundSemester
                                    ),
                                ])
                            subjectFetchRequest.fetchLimit = 1

                            let matchingSubjects = try self.backgroundContext
                                .fetch(subjectFetchRequest)
                            guard let subject = matchingSubjects.first else {
                                self.logger.warning(
                                    "⚠️ Skipping schedule for unknown subject '\(subjectName)' in row \(rowNumber)"
                                )
                                skippedRows += 1
                                continue
                            }

                            // Check for duplicate schedule (same subject, day, and start time)
                            let isDuplicate =
                                try self.checkForDuplicateScheduleSync(
                                    subject: subject,
                                    day: day,
                                    startTime: startTime
                                )
                            if isDuplicate {
                                self.logger.warning(
                                    "⚠️ Skipping duplicate schedule for '\(subjectName)' on \(day) at \(startTimeString) in row \(rowNumber)"
                                )
                                skippedRows += 1
                                continue
                            }

                            // Create new schedule directly in background context
                            let newSchedule = Schedule(
                                context: self.backgroundContext
                            )
                            newSchedule.scheduleId = UUID()
                            newSchedule.scheduleDay = day.capitalized
                            newSchedule.scheduleStartTime = startTime
                            newSchedule.scheduleEndTime = endTime
                            newSchedule.scheduleLocation =
                                location.isEmpty ? nil : location
                            newSchedule.subject = subject

                            successfulImports += 1
                            self.logger.debug(
                                "✅ Processed schedule for '\(subjectName)' on \(day) (row \(rowNumber))"
                            )

                        } catch {
                            self.logger.warning(
                                "⚠️ Error processing schedule row \(rowNumber): \(error.localizedDescription)"
                            )
                            errors.append(
                                BulkImportRowError(
                                    rowNumber: rowNumber,
                                    error: error,
                                    rowData: row
                                )
                            )
                        }
                    }

                    // Save all changes at once
                    if successfulImports > 0 {
                        do {
                            try self.backgroundContext.save()
                            self.logger.info(
                                "💾 Saved \(successfulImports) schedules to Core Data"
                            )
                        } catch {
                            let wrappedError =
                                BulkImportRepositoryError.coreDataError(
                                    "Failed to save schedules: \(error.localizedDescription)"
                                )
                            self.logger.error(
                                "❌ \(wrappedError.localizedDescription)"
                            )
                            continuation.resume(throwing: wrappedError)
                            return
                        }
                    }

                    let result = BulkImportResult(
                        totalRows: rows.count,
                        successfulImports: successfulImports,
                        skippedRows: skippedRows,
                        errors: errors
                    )

                    self.logger.info(
                        "🎉 Schedule bulk import completed: \(successfulImports) imported, \(skippedRows) skipped, \(errors.count) errors"
                    )
                    continuation.resume(returning: result)

                } catch let error as BulkImportRepositoryError {
                    continuation.resume(throwing: error)
                } catch {
                    let wrappedError = BulkImportRepositoryError.coreDataError(
                        "Unexpected error during schedule bulk import: \(error.localizedDescription)"
                    )
                    self.logger.error("❌ \(wrappedError.localizedDescription)")
                    continuation.resume(throwing: wrappedError)
                }
            }
        }
    }

    // MARK: - Search Methods

    /// Gets subjects by subject name, optionally scoped to a specific semester
    ///
    /// - Parameters:
    ///   - name: The subject name to search for (case-insensitive)
    ///   - semester: Optional semester to scope the search. If nil, searches across all semesters
    ///
    /// - Returns: Array of subjects matching the name criteria
    func getSubjectsByName(_ name: String, in semester: Semester? = nil)
        async throws -> [Subject]
    {
        self.logger.debug("🔍 Searching for subjects with name: \(name)")

        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    let fetchRequest: NSFetchRequest<Subject> =
                        Subject.fetchRequest()

                    var predicateComponents: [NSPredicate] = []
                    predicateComponents.append(
                        NSPredicate(
                            format: "subjectName ==[c] %@",
                            name.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    )

                    // Add semester filter if provided
                    if let semester = semester {
                        guard
                            let backgroundSemester = try? self.backgroundContext
                                .existingObject(with: semester.objectID)
                                as? Semester
                        else {
                            let error =
                                BulkImportRepositoryError.semesterNotFound(
                                    "Semester not found in background context"
                                )
                            self.logger.error("❌ \(error.localizedDescription)")
                            continuation.resume(throwing: error)
                            return
                        }
                        predicateComponents.append(
                            NSPredicate(
                                format: "semester == %@",
                                backgroundSemester
                            )
                        )
                    }

                    fetchRequest.predicate = NSCompoundPredicate(
                        andPredicateWithSubpredicates: predicateComponents
                    )

                    // Sort by semester name, then by subject name
                    fetchRequest.sortDescriptors = [
                        NSSortDescriptor(
                            key: "semester.semesterName",
                            ascending: true
                        ),
                        NSSortDescriptor(key: "subjectName", ascending: true),
                    ]

                    let backgroundSubjects = try self.backgroundContext.fetch(
                        fetchRequest
                    )

                    // Convert to main context objects
                    let mainContextSubjects = try backgroundSubjects.map {
                        subject in
                        try self.persistentContainer.viewContext.existingObject(
                            with: subject.objectID
                        ) as! Subject
                    }

                    self.logger.info(
                        "✅ Found \(mainContextSubjects.count) subjects with name '\(name)'"
                    )
                    continuation.resume(returning: mainContextSubjects)

                } catch let error as BulkImportRepositoryError {
                    continuation.resume(throwing: error)
                } catch {
                    let wrappedError = BulkImportRepositoryError.coreDataError(
                        "Failed to fetch subjects by name: \(error.localizedDescription)"
                    )
                    self.logger.error("❌ \(wrappedError.localizedDescription)")
                    continuation.resume(throwing: wrappedError)
                }
            }
        }
    }

    /// Gets subjects by partial name match, optionally scoped to a specific semester
    ///
    /// - Parameters:
    ///   - partialName: The partial subject name to search for (case-insensitive)
    ///   - semester: Optional semester to scope the search. If nil, searches across all semesters
    ///
    /// - Returns: Array of subjects containing the partial name
    func getSubjectsByPartialName(
        _ partialName: String,
        in semester: Semester? = nil
    ) async throws -> [Subject] {
        self.logger.debug(
            "🔍 Searching for subjects containing: '\(partialName)'"
        )

        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    let fetchRequest: NSFetchRequest<Subject> =
                        Subject.fetchRequest()

                    var predicateComponents: [NSPredicate] = []
                    predicateComponents.append(
                        NSPredicate(
                            format: "subjectName CONTAINS[c] %@",
                            partialName.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                        )
                    )

                    // Add semester filter if provided
                    if let semester = semester {
                        guard
                            let backgroundSemester = try? self.backgroundContext
                                .existingObject(with: semester.objectID)
                                as? Semester
                        else {
                            let error =
                                BulkImportRepositoryError.semesterNotFound(
                                    "Semester not found in background context"
                                )
                            self.logger.error("❌ \(error.localizedDescription)")
                            continuation.resume(throwing: error)
                            return
                        }
                        predicateComponents.append(
                            NSPredicate(
                                format: "semester == %@",
                                backgroundSemester
                            )
                        )
                    }

                    fetchRequest.predicate = NSCompoundPredicate(
                        andPredicateWithSubpredicates: predicateComponents
                    )

                    // Sort by semester name, then by subject name
                    fetchRequest.sortDescriptors = [
                        NSSortDescriptor(
                            key: "semester.semesterName",
                            ascending: true
                        ),
                        NSSortDescriptor(key: "subjectName", ascending: true),
                    ]

                    let backgroundSubjects = try self.backgroundContext.fetch(
                        fetchRequest
                    )

                    // Convert to main context objects
                    let mainContextSubjects = try backgroundSubjects.map {
                        subject in
                        try self.persistentContainer.viewContext.existingObject(
                            with: subject.objectID
                        ) as! Subject
                    }

                    self.logger.info(
                        "✅ Found \(mainContextSubjects.count) subjects containing '\(partialName)'"
                    )
                    continuation.resume(returning: mainContextSubjects)

                } catch let error as BulkImportRepositoryError {
                    continuation.resume(throwing: error)
                } catch {
                    let wrappedError = BulkImportRepositoryError.coreDataError(
                        "Failed to fetch subjects by partial name: \(error.localizedDescription)"
                    )
                    self.logger.error("❌ \(wrappedError.localizedDescription)")
                    continuation.resume(throwing: wrappedError)
                }
            }
        }
    }

    // MARK: - Private Helper Methods

    private func checkForDuplicateScheduleSync(
        subject: Subject,
        day: String,
        startTime: Date
    ) throws -> Bool {
        let fetchRequest: NSFetchRequest<Schedule> = Schedule.fetchRequest()
        fetchRequest.predicate = NSCompoundPredicate(
            andPredicateWithSubpredicates: [
                NSPredicate(format: "subject == %@", subject),
                NSPredicate(
                    format: "scheduleDay ==[c] %@",
                    day.trimmingCharacters(in: .whitespacesAndNewlines)
                ),
                NSPredicate(
                    format: "scheduleStartTime == %@",
                    startTime as CVarArg
                ),
            ])
        fetchRequest.fetchLimit = 1

        let existingSchedules = try backgroundContext.fetch(fetchRequest)
        return !existingSchedules.isEmpty
    }

    private func checkForDuplicateSubjectNameSync(
        _ name: String,
        in semester: Semester
    ) throws -> Bool {
        let fetchRequest: NSFetchRequest<Subject> = Subject.fetchRequest()
        fetchRequest.predicate = NSCompoundPredicate(
            andPredicateWithSubpredicates: [
                NSPredicate(
                    format: "subjectName ==[c] %@",
                    name.trimmingCharacters(in: .whitespacesAndNewlines)
                ),
                NSPredicate(format: "semester == %@", semester),
            ])
        fetchRequest.fetchLimit = 1

        let existingSubjects = try backgroundContext.fetch(fetchRequest)
        return !existingSubjects.isEmpty
    }
}
