//
//  ScheduleRepository.swift
//  eda
//
//  Created by Siddhartha Srivastava on 12/07/25.
//

import CoreData
import Foundation
import os.log

// MARK: - Data Transfer Objects
struct ScheduleData {
    let startTime: Date
    let endTime: Date
    let day: String
    let location: String
}

// MARK: - Schedule Repository Error Types
enum ScheduleRepositoryError: LocalizedError {
    case scheduleNotFound(String)
    case subjectNotFound(String)
    case semesterNotFound(String)
    case invalidScheduleData(String)
    case coreDataError(String)
    case timeConflict(String)

    var errorDescription: String? {
        switch self {
        case .scheduleNotFound(let details):
            return "Schedule not found: \(details)"
        case .subjectNotFound(let details):
            return "Subject not found: \(details)"
        case .semesterNotFound(let details):
            return "Semester not found: \(details)"
        case .invalidScheduleData(let details):
            return "Invalid schedule data: \(details)"
        case .coreDataError(let details):
            return "Core Data error: \(details)"
        case .timeConflict(let details):
            return "Schedule time conflict: \(details)"
        }
    }
}

// MARK: - Core Data Repository Implementation
class ScheduleRepository {
    private let persistentContainer: NSPersistentContainer
    private let backgroundContext: NSManagedObjectContext
    private let logger = Logger(
        subsystem: "com.eda.app",
        category: "ScheduleRepository"
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

    // MARK: - Create Schedule
    func createSchedule(scheduleData: ScheduleData, for subject: Subject)
        async throws -> Schedule
    {
        self.logger.debug(
            "📅 Creating schedule for subject: \(subject.subjectName ?? "unknown")"
        )

        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    // Get subject in background context
                    guard
                        let backgroundSubject = try? self.backgroundContext
                            .existingObject(with: subject.objectID) as? Subject
                    else {
                        let error = ScheduleRepositoryError.subjectNotFound(
                            "Subject not found in background context"
                        )
                        self.logger.error("❌ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }

                    // Validate schedule data
                    guard scheduleData.endTime > scheduleData.startTime else {
                        let error = ScheduleRepositoryError.invalidScheduleData(
                            "End time must be after start time"
                        )
                        self.logger.error("❌ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }

                    // TODO: Check for time conflicts
                    // let hasConflict = try self.checkForTimeConflictSync(scheduleData, for: backgroundSubject)
                    // if hasConflict {
                    //     let error = ScheduleRepositoryError.timeConflict("Schedule conflicts with existing schedule")
                    //     continuation.resume(throwing: error)
                    //     return
                    // }

                    // Create new schedule
                    let newSchedule = Schedule(context: self.backgroundContext)
                    newSchedule.scheduleId = UUID()
                    newSchedule.scheduleStartTime = scheduleData.startTime
                    newSchedule.scheduleEndTime = scheduleData.endTime
                    newSchedule.scheduleDay = scheduleData.day
                    newSchedule.scheduleLocation = scheduleData.location
                    newSchedule.subject = backgroundSubject

                    // Save background context
                    try self.backgroundContext.save()

                    // Get object in main context
                    let mainContextSchedule =
                        try self.persistentContainer.viewContext.existingObject(
                            with: newSchedule.objectID
                        ) as! Schedule

                    self.logger.info(
                        "✅ Schedule created successfully for subject: \(backgroundSubject.subjectName ?? "unknown")"
                    )
                    continuation.resume(returning: mainContextSchedule)

                } catch let error as ScheduleRepositoryError {
                    continuation.resume(throwing: error)
                } catch {
                    let wrappedError = ScheduleRepositoryError.coreDataError(
                        "Failed to create schedule: \(error.localizedDescription)"
                    )
                    self.logger.error("❌ \(wrappedError.localizedDescription)")
                    continuation.resume(throwing: wrappedError)
                }
            }
        }
    }

    // MARK: - Update Schedule
    func updateSchedule(
        scheduleId: UUID,
        scheduleData: ScheduleData,
        for subject: Subject
    ) async throws -> Schedule {
        self.logger.debug("📝 Updating schedule: \(scheduleId.uuidString)")

        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    // Find schedule in background context
                    let scheduleFetchRequest: NSFetchRequest<Schedule> =
                        Schedule.fetchRequest()
                    scheduleFetchRequest.predicate = NSPredicate(
                        format: "scheduleId == %@",
                        scheduleId as CVarArg
                    )
                    scheduleFetchRequest.fetchLimit = 1

                    let schedules = try self.backgroundContext.fetch(
                        scheduleFetchRequest
                    )
                    guard let schedule = schedules.first else {
                        let error = ScheduleRepositoryError.scheduleNotFound(
                            "Schedule with ID \(scheduleId.uuidString) not found"
                        )
                        self.logger.error("❌ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }

                    // Get subject in background context
                    guard
                        let backgroundSubject = try? self.backgroundContext
                            .existingObject(with: subject.objectID) as? Subject
                    else {
                        let error = ScheduleRepositoryError.subjectNotFound(
                            "Subject not found in background context"
                        )
                        self.logger.error("❌ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }

                    // Validate schedule data
                    guard scheduleData.endTime > scheduleData.startTime else {
                        let error = ScheduleRepositoryError.invalidScheduleData(
                            "End time must be after start time"
                        )
                        self.logger.error("❌ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }

                    // TODO: Check for time conflicts (excluding current schedule)
                    // let hasConflict = try self.checkForTimeConflictSync(scheduleData, for: backgroundSubject, excluding: schedule)
                    // if hasConflict {
                    //     let error = ScheduleRepositoryError.timeConflict("Schedule conflicts with existing schedule")
                    //     continuation.resume(throwing: error)
                    //     return
                    // }

                    // Update schedule properties
                    schedule.scheduleStartTime = scheduleData.startTime
                    schedule.scheduleEndTime = scheduleData.endTime
                    schedule.scheduleDay = scheduleData.day
                    schedule.scheduleLocation = scheduleData.location
                    schedule.subject = backgroundSubject

                    // Save background context
                    try self.backgroundContext.save()

                    // Get object in main context
                    let mainContextSchedule =
                        try self.persistentContainer.viewContext.existingObject(
                            with: schedule.objectID
                        ) as! Schedule

                    self.logger.info(
                        "✅ Schedule updated successfully: \(scheduleId.uuidString)"
                    )
                    continuation.resume(returning: mainContextSchedule)

                } catch let error as ScheduleRepositoryError {
                    continuation.resume(throwing: error)
                } catch {
                    let wrappedError = ScheduleRepositoryError.coreDataError(
                        "Failed to update schedule: \(error.localizedDescription)"
                    )
                    self.logger.error("❌ \(wrappedError.localizedDescription)")
                    continuation.resume(throwing: wrappedError)
                }
            }
        }
    }

    // MARK: - Delete Schedule
    func deleteSchedule(scheduleId: UUID) async throws {
        self.logger.debug("🗑️ Deleting schedule: \(scheduleId.uuidString)")

        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    // Find schedule in background context
                    let fetchRequest: NSFetchRequest<Schedule> =
                        Schedule.fetchRequest()
                    fetchRequest.predicate = NSPredicate(
                        format: "scheduleId == %@",
                        scheduleId as CVarArg
                    )
                    fetchRequest.fetchLimit = 1

                    let schedules = try self.backgroundContext.fetch(
                        fetchRequest
                    )
                    guard let schedule = schedules.first else {
                        let error = ScheduleRepositoryError.scheduleNotFound(
                            "Schedule with ID \(scheduleId.uuidString) not found"
                        )
                        self.logger.warning("⚠️ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }

                    let subjectName =
                        schedule.subject?.subjectName ?? "Unknown Subject"

                    // Delete the schedule
                    self.backgroundContext.delete(schedule)

                    // Save background context
                    try self.backgroundContext.save()

                    self.logger.info(
                        "✅ Schedule deleted successfully for subject: \(subjectName)"
                    )
                    continuation.resume()

                } catch let error as ScheduleRepositoryError {
                    continuation.resume(throwing: error)
                } catch {
                    let wrappedError = ScheduleRepositoryError.coreDataError(
                        "Failed to delete schedule: \(error.localizedDescription)"
                    )
                    self.logger.error("❌ \(wrappedError.localizedDescription)")
                    continuation.resume(throwing: wrappedError)
                }
            }
        }
    }

    // MARK: - Get All Schedules for a Date
    func getAllSchedules(for date: Date, semester: Semester) async throws
        -> [Schedule]
    {
        self.logger.debug("📋 Fetching schedules for date: \(date)")

        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    // Get semester in background context
                    guard
                        let backgroundSemester = try? self.backgroundContext
                            .existingObject(with: semester.objectID)
                            as? Semester
                    else {
                        let error = ScheduleRepositoryError.semesterNotFound(
                            "Semester not found in background context"
                        )
                        self.logger.error("❌ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }

                    // Validate that the date is within semester range
                    guard
                        let semesterStartDate = backgroundSemester
                            .semesterStartDate,
                        let semesterEndDate = backgroundSemester.semesterEndDate
                    else {
                        let error = ScheduleRepositoryError.invalidScheduleData(
                            "Semester start or end date is missing"
                        )
                        self.logger.error("❌ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }

                    // Check if the requested date falls within semester date range
                    let calendar = Calendar.current
                    let dateOnly = calendar.startOfDay(for: date)
                    let startDateOnly = calendar.startOfDay(
                        for: semesterStartDate
                    )
                    let endDateOnly = calendar.startOfDay(for: semesterEndDate)

                    guard dateOnly >= startDateOnly && dateOnly <= endDateOnly
                    else {
                        self.logger.warning(
                            "⚠️ Requested date \(date) is outside semester range (\(semesterStartDate) - \(semesterEndDate))"
                        )
                        // Return empty array instead of error for dates outside semester range
                        continuation.resume(returning: [])
                        return
                    }

                    // Get day name from date
                    let formatter = DateFormatter()
                    formatter.dateFormat = "EEEE"  // Full day name (Monday, Tuesday, etc.)
                    let dayName = formatter.string(from: date)

                    let fetchRequest: NSFetchRequest<Schedule> =
                        Schedule.fetchRequest()
                    fetchRequest.predicate = NSPredicate(
                        format: "scheduleDay == %@ AND subject.semester == %@",
                        dayName,
                        backgroundSemester
                    )

                    // Sort by start time
                    fetchRequest.sortDescriptors = [
                        NSSortDescriptor(
                            key: "scheduleStartTime",
                            ascending: true
                        )
                    ]

                    let backgroundSchedules = try self.backgroundContext.fetch(
                        fetchRequest
                    )

                    // Convert to main context objects
                    let mainContextSchedules = try backgroundSchedules.map {
                        schedule in
                        try self.persistentContainer.viewContext.existingObject(
                            with: schedule.objectID
                        ) as! Schedule
                    }

                    self.logger.info(
                        "✅ Fetched \(mainContextSchedules.count) schedules for \(dayName) within semester range"
                    )
                    continuation.resume(returning: mainContextSchedules)

                } catch let error as ScheduleRepositoryError {
                    continuation.resume(throwing: error)
                } catch {
                    let wrappedError = ScheduleRepositoryError.coreDataError(
                        "Failed to fetch schedules: \(error.localizedDescription)"
                    )
                    self.logger.error("❌ \(wrappedError.localizedDescription)")
                    continuation.resume(throwing: wrappedError)
                }
            }
        }
    }

    func getCurrentlyActiveSchedule(for semester: Semester) async throws
        -> Schedule?
    {
        self.logger.debug(
            "🔍 Checking for currently active schedule in semester: \(semester.semesterName ?? "unknown")"
        )

        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    // Validate semester ID first
                    guard let semesterId = semester.semesterId else {
                        self.logger.error("❌ Semester ID is nil")
                        continuation.resume(returning: nil)
                        return
                    }

                    let now = Date()
                    let calendar = Calendar.current

                    // Fetch semester in background context
                    let semesterFetchRequest: NSFetchRequest<Semester> =
                        Semester.fetchRequest()
                    semesterFetchRequest.predicate = NSPredicate(
                        format: "semesterId == %@",
                        semesterId as CVarArg
                    )
                    semesterFetchRequest.fetchLimit = 1

                    let backgroundSemesters = try self.backgroundContext.fetch(
                        semesterFetchRequest
                    )

                    guard let backgroundSemester = backgroundSemesters.first
                    else {
                        self.logger.error(
                            "❌ Semester not found in background context"
                        )
                        continuation.resume(returning: nil)
                        return
                    }

                    // Validate that the current date is within semester range
                    guard
                        let semesterStartDate = backgroundSemester
                            .semesterStartDate,
                        let semesterEndDate = backgroundSemester.semesterEndDate
                    else {
                        self.logger.warning(
                            "⚠️ Semester start or end date is missing"
                        )
                        continuation.resume(returning: nil)
                        return
                    }

                    // Check if the current date falls within semester date range
                    let currentDateOnly = calendar.startOfDay(for: now)
                    let startDateOnly = calendar.startOfDay(
                        for: semesterStartDate
                    )
                    let endDateOnly = calendar.startOfDay(for: semesterEndDate)

                    guard
                        currentDateOnly >= startDateOnly
                            && currentDateOnly <= endDateOnly
                    else {
                        self.logger.info(
                            "ℹ️ Current date \(now) is outside semester range (\(semesterStartDate) - \(semesterEndDate))"
                        )
                        continuation.resume(returning: nil)
                        return
                    }

                    // Get current day name
                    let formatter = DateFormatter()
                    formatter.dateFormat = "EEEE"
                    let currentDay = formatter.string(from: now)

                    // Calculate current time in minutes
                    let currentHour = calendar.component(.hour, from: now)
                    let currentMinute = calendar.component(.minute, from: now)
                    let currentTotalMinutes = currentHour * 60 + currentMinute

                    // Fetch all schedules for current day in this semester
                    let scheduleFetchRequest: NSFetchRequest<Schedule> =
                        Schedule.fetchRequest()
                    scheduleFetchRequest.predicate = NSPredicate(
                        format: "scheduleDay == %@ AND subject.semester == %@",
                        currentDay,
                        backgroundSemester
                    )

                    let todaySchedules = try self.backgroundContext.fetch(
                        scheduleFetchRequest
                    )

                    // Find the currently active schedule
                    let activeSchedule = try self.findActiveSchedule(
                        from: todaySchedules,
                        currentTotalMinutes: currentTotalMinutes,
                        calendar: calendar
                    )

                    if let activeSchedule = activeSchedule {
                        self.logger.info(
                            "✅ Found active schedule: \(activeSchedule.subject?.subjectName ?? "unknown")"
                        )
                    } else {
                        self.logger.info(
                            "ℹ️ No currently active schedule found for semester: \(semester.semesterName ?? "unknown")"
                        )
                    }

                    continuation.resume(returning: activeSchedule)

                } catch {
                    self.logger.error(
                        "❌ Failed to check for active schedule: \(error.localizedDescription)"
                    )
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func findActiveSchedule(
        from schedules: [Schedule],
        currentTotalMinutes: Int,
        calendar: Calendar
    ) throws -> Schedule? {

        for schedule in schedules {
            guard let startTime = schedule.scheduleStartTime,
                let endTime = schedule.scheduleEndTime
            else {
                continue
            }

            // Calculate start time in minutes
            let startHour = calendar.component(.hour, from: startTime)
            let startMinute = calendar.component(.minute, from: startTime)
            let startTotalMinutes = startHour * 60 + startMinute

            // Calculate end time in minutes
            let endHour = calendar.component(.hour, from: endTime)
            let endMinute = calendar.component(.minute, from: endTime)
            let endTotalMinutes = endHour * 60 + endMinute

            // Check if current time falls within this schedule
            if currentTotalMinutes >= startTotalMinutes
                && currentTotalMinutes <= endTotalMinutes
            {
                // Convert to main context object
                let mainContextSchedule =
                    try persistentContainer.viewContext.existingObject(
                        with: schedule.objectID
                    ) as! Schedule

                return mainContextSchedule
            }
        }

        return nil
    }

    func getScheduleById(_ id: UUID) async throws -> Schedule? {
        self.logger.debug("🔍 Fetching schedule by ID: \(id.uuidString)")

        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    let fetchRequest: NSFetchRequest<Schedule> =
                        Schedule.fetchRequest()
                    fetchRequest.predicate = NSPredicate(
                        format: "scheduleId == %@",
                        id as CVarArg
                    )
                    fetchRequest.fetchLimit = 1

                    let backgroundSchedules = try self.backgroundContext.fetch(
                        fetchRequest
                    )

                    if let backgroundSchedule = backgroundSchedules.first {
                        let mainContextSchedule =
                            try self.persistentContainer.viewContext
                            .existingObject(with: backgroundSchedule.objectID)
                            as! Schedule

                        self.logger.info(
                            "✅ Found schedule: \(mainContextSchedule.subject?.subjectName ?? "unknown subject")"
                        )
                        continuation.resume(returning: mainContextSchedule)
                    } else {
                        self.logger.info(
                            "ℹ️ No schedule found with ID: \(id.uuidString)"
                        )
                        continuation.resume(returning: nil)
                    }

                } catch {
                    let wrappedError = ScheduleRepositoryError.coreDataError(
                        "Failed to fetch schedule by ID: \(error.localizedDescription)"
                    )
                    self.logger.error("❌ \(wrappedError.localizedDescription)")
                    continuation.resume(throwing: wrappedError)
                }
            }
        }
    }

    func getAllSchedulesForSubject(_ subjectId: UUID) async throws -> [Schedule]
    {
        self.logger.debug(
            "📚 Fetching all schedules for subject: \(subjectId.uuidString)"
        )

        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    let fetchRequest: NSFetchRequest<Schedule> =
                        Schedule.fetchRequest()
                    fetchRequest.predicate = NSPredicate(
                        format: "subject.subjectId == %@",
                        subjectId as CVarArg
                    )

                    // Sort by day and start time
                    fetchRequest.sortDescriptors = [
                        NSSortDescriptor(key: "scheduleDay", ascending: true),
                        NSSortDescriptor(
                            key: "scheduleStartTime",
                            ascending: true
                        ),
                    ]

                    let backgroundSchedules = try self.backgroundContext.fetch(
                        fetchRequest
                    )

                    // Convert to main context objects
                    let mainContextSchedules = try backgroundSchedules.map {
                        schedule in
                        try self.persistentContainer.viewContext.existingObject(
                            with: schedule.objectID
                        ) as! Schedule
                    }

                    self.logger.info(
                        "✅ Fetched \(mainContextSchedules.count) schedules for subject"
                    )
                    continuation.resume(returning: mainContextSchedules)

                } catch {
                    let wrappedError = ScheduleRepositoryError.coreDataError(
                        "Failed to fetch schedules for subject: \(error.localizedDescription)"
                    )
                    self.logger.error("❌ \(wrappedError.localizedDescription)")
                    continuation.resume(throwing: wrappedError)
                }
            }
        }
    }

    // MARK: - Time Conflict Checking
    func checkForTimeConflict(
        scheduleData: ScheduleData,
        in semester: Semester,
        excluding excludedScheduleId: UUID? = nil
    ) async throws -> Bool {
        self.logger.debug(
            "🔍 Checking for time conflicts on \(scheduleData.day)"
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
                        let error = ScheduleRepositoryError.semesterNotFound(
                            "Semester not found in background context"
                        )
                        continuation.resume(throwing: error)
                        return
                    }

                    let fetchRequest: NSFetchRequest<Schedule> =
                        Schedule.fetchRequest()

                    var predicateComponents: [NSPredicate] = []
                    predicateComponents.append(
                        NSPredicate(
                            format: "scheduleDay == %@",
                            scheduleData.day
                        )
                    )
                    predicateComponents.append(
                        NSPredicate(
                            format: "subject.semester == %@",
                            backgroundSemester
                        )
                    )

                    if let excludedId = excludedScheduleId {
                        predicateComponents.append(
                            NSPredicate(
                                format: "scheduleId != %@",
                                excludedId as CVarArg
                            )
                        )
                    }

                    fetchRequest.predicate = NSCompoundPredicate(
                        andPredicateWithSubpredicates: predicateComponents
                    )

                    let existingSchedules = try self.backgroundContext.fetch(
                        fetchRequest
                    )

                    // Check for time overlaps
                    let hasConflict = existingSchedules.contains { schedule in
                        guard let existingStart = schedule.scheduleStartTime,
                            let existingEnd = schedule.scheduleEndTime
                        else {
                            return false
                        }

                        // Check if time ranges overlap
                        return
                            !(scheduleData.endTime <= existingStart
                            || scheduleData.startTime >= existingEnd)
                    }

                    self.logger.debug(
                        "📊 Time conflict check result: \(hasConflict)"
                    )
                    continuation.resume(returning: hasConflict)

                } catch {
                    let wrappedError = ScheduleRepositoryError.coreDataError(
                        "Failed to check for time conflict: \(error.localizedDescription)"
                    )
                    self.logger.error("❌ \(wrappedError.localizedDescription)")
                    continuation.resume(throwing: wrappedError)
                }
            }
        }
    }
}
