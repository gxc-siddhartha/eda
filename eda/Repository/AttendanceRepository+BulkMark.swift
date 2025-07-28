//
//  AttendanceRepository+BulkOperations.swift
//  eda
//
//  Bulk attendance operations for efficient batch processing
//

import CoreData
import Foundation
import os.log

// MARK: - Bulk Operation Data Models

struct BulkAttendanceRequest {
    let schedule: Schedule
    let attendanceData: AttendanceData
    let requestId: UUID = UUID() // For tracking individual requests
}

struct BulkAttendanceResult {
    let totalRequests: Int
    let successfulCreations: [Attendance]
    let failures: [BulkAttendanceFailure]
    let skippedDuplicates: [BulkAttendanceRequest]
    
    var successCount: Int { successfulCreations.count }
    var failureCount: Int { failures.count }
    var skippedCount: Int { skippedDuplicates.count }
    var isFullSuccess: Bool { failureCount == 0 && skippedCount == 0 }
    var hasPartialSuccess: Bool { successCount > 0 && (failureCount > 0 || skippedCount > 0) }
}

struct BulkAttendanceFailure {
    let request: BulkAttendanceRequest
    let error: AttendanceRepositoryError
    let canRetry: Bool
    
    init(request: BulkAttendanceRequest, error: AttendanceRepositoryError) {
        self.request = request
        self.error = error
        // Determine if this error is retryable
        self.canRetry = {
            switch error {
            case .duplicateAttendance, .invalidAttendanceData:
                return false // These won't fix themselves
            case .attendanceNotFound, .subjectNotFound, .coreDataError:
                return true // Might work on retry
            }
        }()
    }
}

// MARK: - Repository Extension

extension AttendanceRepository {
    
    /// Creates multiple attendance records in a single batch operation
    /// - Parameter requests: Array of bulk attendance requests
    /// - Returns: Detailed result of the bulk operation
    func createBulkAttendance(_ requests: [BulkAttendanceRequest]) async throws -> BulkAttendanceResult {
        logger.info("📦 Starting bulk attendance creation for \(requests.count) requests")
        
        guard !requests.isEmpty else {
            return BulkAttendanceResult(
                totalRequests: 0,
                successfulCreations: [],
                failures: [],
                skippedDuplicates: []
            )
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    let result = try self.performBulkAttendanceCreation(requests)
                    continuation.resume(returning: result)
                } catch {
                    let wrappedError = self.wrapBulkError(error, context: "bulk attendance creation")
                    continuation.resume(throwing: wrappedError)
                }
            }
        }
    }
    
    /// Validates all requests before processing any
    /// - Parameter requests: Array of bulk attendance requests
    /// - Returns: Validation result with categorized requests
    private func validateBulkRequests(_ requests: [BulkAttendanceRequest]) throws -> (
        valid: [BulkAttendanceRequest],
        duplicates: [BulkAttendanceRequest],
        invalid: [BulkAttendanceFailure]
    ) {
        var validRequests: [BulkAttendanceRequest] = []
        var duplicates: [BulkAttendanceRequest] = []
        var invalidRequests: [BulkAttendanceFailure] = []
        
        for request in requests {
            do {
                // Validate request data
                try self.validateBulkAttendanceRequest(request)
                
                // Check for duplicates
                if try self.isDuplicateAttendance(request) {
                    duplicates.append(request)
                    self.logger.debug("⚠️ Duplicate found: \(request.schedule.subject?.subjectName ?? "unknown")")
                } else {
                    validRequests.append(request)
                }
                
            } catch let error as AttendanceRepositoryError {
                let failure = BulkAttendanceFailure(request: request, error: error)
                invalidRequests.append(failure)
                self.logger.warning("❌ Invalid request: \(error.localizedDescription)")
            } catch {
                let wrappedError = AttendanceRepositoryError.coreDataError("Validation error: \(error.localizedDescription)")
                let failure = BulkAttendanceFailure(request: request, error: wrappedError)
                invalidRequests.append(failure)
            }
        }
        
        logger.debug("📊 Validation complete: \(validRequests.count) valid, \(duplicates.count) duplicates, \(invalidRequests.count) invalid")
        
        return (valid: validRequests, duplicates: duplicates, invalid: invalidRequests)
    }
    
    /// Performs the actual bulk creation after validation
    private func performBulkAttendanceCreation(_ requests: [BulkAttendanceRequest]) throws -> BulkAttendanceResult {
        // Step 1: Validate all requests
        let validation = try validateBulkRequests(requests)
        
        var successfulCreations: [Attendance] = []
        var failures = validation.invalid
        
        // Step 2: Process valid requests
        for request in validation.valid {
            do {
                let attendance = try createSingleAttendanceInBatch(request)
                successfulCreations.append(attendance)
                logger.debug("✅ Created: \(request.schedule.subject?.subjectName ?? "unknown")")
                
            } catch let error as AttendanceRepositoryError {
                let failure = BulkAttendanceFailure(request: request, error: error)
                failures.append(failure)
                logger.error("❌ Failed to create: \(error.localizedDescription)")
            } catch {
                let wrappedError = AttendanceRepositoryError.coreDataError("Creation error: \(error.localizedDescription)")
                let failure = BulkAttendanceFailure(request: request, error: wrappedError)
                failures.append(failure)
            }
        }
        
        // Step 3: Save all changes at once (atomic operation)
        if !successfulCreations.isEmpty {
            try backgroundContext.save()
            logger.info("💾 Saved \(successfulCreations.count) attendance records")
        }
        
        // Step 4: Convert to main context objects
        let mainContextAttendances = try successfulCreations.map { attendance in
            try persistentContainer.viewContext.existingObject(with: attendance.objectID) as! Attendance
        }
        
        let result = BulkAttendanceResult(
            totalRequests: requests.count,
            successfulCreations: mainContextAttendances,
            failures: failures,
            skippedDuplicates: validation.duplicates
        )
        
        logger.info("🎉 Bulk operation complete: \(result.successCount) created, \(result.failureCount) failed, \(result.skippedCount) skipped")
        
        return result
    }
    
    /// Creates a single attendance record within a batch operation
    private func createSingleAttendanceInBatch(_ request: BulkAttendanceRequest) throws -> Attendance {
        // Get schedule in background context
        guard let backgroundSchedule = try? backgroundContext.existingObject(with: request.schedule.objectID) as? Schedule,
              let backgroundSubject = backgroundSchedule.subject else {
            throw AttendanceRepositoryError.subjectNotFound("Schedule or subject not found in background context")
        }
        
        // Create attendance
        let attendance = Attendance(context: backgroundContext)
        attendance.attendanceId = UUID()
        attendance.attendanceType = request.attendanceData.attendanceType.trimmingCharacters(in: .whitespacesAndNewlines)
        attendance.attendancePresence = request.attendanceData.attendancePresent.trimmingCharacters(in: .whitespacesAndNewlines)
        attendance.attendanceEvent = request.attendanceData.attendanceEvent.trimmingCharacters(in: .whitespacesAndNewlines)
        attendance.attendanceDate = request.attendanceData.attendanceDate
        attendance.attendanceStartTime = request.attendanceData.attendanceStartTime
        attendance.attendanceEndTime = request.attendanceData.attendanceEndTime
        attendance.attendanceLocation = request.attendanceData.attendanceLocation?.trimmingCharacters(in: .whitespacesAndNewlines)
        attendance.subject = backgroundSubject
        
        return attendance
    }
    
    /// Validates a single bulk attendance request
    private func validateBulkAttendanceRequest(_ request: BulkAttendanceRequest) throws {
        let data = request.attendanceData
        
        // Validate attendance type
        guard !data.attendanceType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AttendanceRepositoryError.invalidAttendanceData("Attendance type cannot be empty")
        }
        
        // Validate presence status
        guard !data.attendancePresent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AttendanceRepositoryError.invalidAttendanceData("Attendance presence status cannot be empty")
        }
        
        // Validate time order
        guard data.attendanceStartTime < data.attendanceEndTime else {
            throw AttendanceRepositoryError.invalidAttendanceData("Start time must be before end time")
        }
        
        // Validate string lengths
        guard data.attendanceType.count <= 50 else {
            throw AttendanceRepositoryError.invalidAttendanceData("Attendance type too long")
        }
        
        guard data.attendanceEvent.count <= 100 else {
            throw AttendanceRepositoryError.invalidAttendanceData("Event description too long")
        }
        
        if let location = data.attendanceLocation {
            guard location.count <= 100 else {
                throw AttendanceRepositoryError.invalidAttendanceData("Location too long")
            }
        }
    }
    
    /// Checks if attendance already exists for the given request
    private func isDuplicateAttendance(_ request: BulkAttendanceRequest) throws -> Bool {
        guard let backgroundSchedule = try? backgroundContext.existingObject(with: request.schedule.objectID) as? Schedule,
              let backgroundSubject = backgroundSchedule.subject else {
            return false
        }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: request.attendanceData.attendanceDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let fetchRequest: NSFetchRequest<Attendance> = Attendance.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "subject == %@ AND attendanceDate >= %@ AND attendanceDate < %@ AND attendanceStartTime == %@",
            backgroundSubject,
            startOfDay as NSDate,
            endOfDay as NSDate,
            request.attendanceData.attendanceStartTime as NSDate
        )
        fetchRequest.fetchLimit = 1
        
        let existingAttendance = try backgroundContext.fetch(fetchRequest)
        return !existingAttendance.isEmpty
    }
    
    /// Wraps bulk operation errors
    private func wrapBulkError(_ error: Error, context: String) -> AttendanceRepositoryError {
        if let repoError = error as? AttendanceRepositoryError {
            return repoError
        }
        return AttendanceRepositoryError.coreDataError("Bulk operation failed in \(context): \(error.localizedDescription)")
    }
}

// MARK: - Convenience Methods

extension AttendanceRepository {
    
    /// Creates attendance for today's pending schedules with default "Present" status
    /// - Parameter schedules: Array of schedules to mark as present
    /// - Returns: Bulk operation result
    func markAllPresent(schedules: [Schedule]) async throws -> BulkAttendanceResult {
        let requests = schedules.map { schedule in
            let attendanceData = AttendanceData(
                attendanceType: "Theory", // Default type
                attendancePresent: "Present",
                attendanceEvent: "",
                attendanceDate: Date(),
                attendanceStartTime: schedule.scheduleStartTime ?? Date(),
                attendanceEndTime: schedule.scheduleEndTime ?? Date(),
                attendanceLocation: schedule.scheduleLocation
            )
            return BulkAttendanceRequest(schedule: schedule, attendanceData: attendanceData)
        }
        
        return try await createBulkAttendance(requests)
    }
    
    /// Gets today's schedules that don't have attendance marked yet
    /// - Parameter semester: Current semester
    /// - Returns: Array of unmarked schedules for today
    func getTodaysPendingSchedules(for semester: Semester) async throws -> [Schedule] {
        logger.debug("📅 Fetching today's pending schedules for semester: \(semester.semesterName ?? "unknown")")
        
        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    guard let backgroundSemester = try? self.backgroundContext.existingObject(with: semester.objectID) as? Semester else {
                        continuation.resume(throwing: AttendanceRepositoryError.subjectNotFound("Semester not found"))
                        return
                    }
                    
                    // Get today's day name
                    let formatter = DateFormatter()
                    formatter.dateFormat = "EEEE"
                    let todayName = formatter.string(from: Date())
                    
                    // Fetch today's schedules
                    let scheduleRequest: NSFetchRequest<Schedule> = Schedule.fetchRequest()
                    scheduleRequest.predicate = NSPredicate(
                        format: "scheduleDay == %@ AND subject.semester == %@",
                        todayName,
                        backgroundSemester
                    )
                    scheduleRequest.sortDescriptors = [
                        NSSortDescriptor(key: "scheduleStartTime", ascending: true)
                    ]
                    
                    let todaysSchedules = try self.backgroundContext.fetch(scheduleRequest)
                    
                    // Filter out schedules that already have attendance
                    var pendingSchedules: [Schedule] = []
                    let today = Date()
                    let calendar = Calendar.current
                    let startOfToday = calendar.startOfDay(for: today)
                    let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
                    
                    for schedule in todaysSchedules {
                        guard let subject = schedule.subject else { continue }
                        
                        // Check if attendance exists for this schedule today
                        let attendanceRequest: NSFetchRequest<Attendance> = Attendance.fetchRequest()
                        attendanceRequest.predicate = NSPredicate(
                            format: "subject == %@ AND attendanceDate >= %@ AND attendanceDate < %@ AND attendanceStartTime == %@",
                            subject,
                            startOfToday as NSDate,
                            endOfToday as NSDate,
                            schedule.scheduleStartTime! as NSDate
                        )
                        attendanceRequest.fetchLimit = 1
                        
                        let existingAttendance = try self.backgroundContext.fetch(attendanceRequest)
                        if existingAttendance.isEmpty {
                            pendingSchedules.append(schedule)
                        }
                    }
                    
                    // Convert to main context
                    let mainContextSchedules = try pendingSchedules.map { schedule in
                        try self.persistentContainer.viewContext.existingObject(with: schedule.objectID) as! Schedule
                    }
                    
                    self.logger.info("✅ Found \(mainContextSchedules.count) pending schedules for today")
                    continuation.resume(returning: mainContextSchedules)
                    
                } catch {
                    let wrappedError = AttendanceRepositoryError.coreDataError("Failed to fetch pending schedules: \(error.localizedDescription)")
                    continuation.resume(throwing: wrappedError)
                }
            }
        }
    }
}
