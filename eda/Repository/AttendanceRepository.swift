//
//  AttendanceRepository.swift
//  eda
//
//  Created by Siddhartha Srivastava on 13/07/25.
//

import CoreData
import Foundation
import os.log

// MARK: - Data Transfer Objects
struct AttendanceData {
    let attendanceType: String
    let attendancePresent: String
    let attendanceEvent: String
    let attendanceDate: Date
}

// MARK: - Attendance Repository Error Types
enum AttendanceRepositoryError: LocalizedError {
    case attendanceNotFound(String)
    case scheduleNotFound(String)
    case subjectNotFound(String)
    case invalidAttendanceData(String)
    case coreDataError(String)
    case duplicateAttendance(String)
    
    var errorDescription: String? {
        switch self {
        case .attendanceNotFound(let details):
            return "Attendance not found: \(details)"
        case .scheduleNotFound(let details):
            return "Schedule not found: \(details)"
        case .subjectNotFound(let details):
            return "Subject not found: \(details)"
        case .invalidAttendanceData(let details):
            return "Invalid attendance data: \(details)"
        case .coreDataError(let details):
            return "Core Data error: \(details)"
        case .duplicateAttendance(let details):
            return "Duplicate attendance: \(details)"
        }
    }
}

// MARK: - Core Data Repository Implementation
class AttendanceRepository {
    private let persistentContainer: NSPersistentContainer
    private let backgroundContext: NSManagedObjectContext
    private let logger = Logger(subsystem: "com.eda.app", category: "AttendanceRepository")
    
    init(persistentContainer: NSPersistentContainer = PersistenceController.shared.container) {
        self.persistentContainer = persistentContainer
        self.backgroundContext = persistentContainer.newBackgroundContext()
        self.backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
    
    // MARK: - Create Attendance
    func createAttendance(attendanceData: AttendanceData, for schedule: Schedule) async throws -> Attendance {
        self.logger.debug("📋 Creating attendance for schedule: \(schedule.scheduleId?.uuidString ?? "unknown")")
        
        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    // Get schedule in background context
                    guard let backgroundSchedule = try? self.backgroundContext.existingObject(with: schedule.objectID) as? Schedule else {
                        let error = AttendanceRepositoryError.scheduleNotFound("Schedule not found in background context")
                        self.logger.error("❌ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    // Validate attendance data
                    guard !attendanceData.attendanceType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        let error = AttendanceRepositoryError.invalidAttendanceData("Attendance type cannot be empty")
                        self.logger.error("❌ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    guard !attendanceData.attendancePresent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        let error = AttendanceRepositoryError.invalidAttendanceData("Attendance present status cannot be empty")
                        self.logger.error("❌ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }
                    
    
                    // Check for duplicate attendance for the same schedule and date (regardless of event)
                    let calendar = Calendar.current
                    let startOfDay = calendar.startOfDay(for: attendanceData.attendanceDate)
                    let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

                    let duplicateCheckRequest: NSFetchRequest<Attendance> = Attendance.fetchRequest()
                    duplicateCheckRequest.predicate = NSPredicate(
                        format: "schedule == %@ AND attendanceDate >= %@ AND attendanceDate < %@",
                        backgroundSchedule,
                        startOfDay as NSDate,
                        endOfDay as NSDate
                    )
                    duplicateCheckRequest.fetchLimit = 1

                    let existingAttendance = try self.backgroundContext.fetch(duplicateCheckRequest)
                    if !existingAttendance.isEmpty {
                        let error = AttendanceRepositoryError.duplicateAttendance("Attendance already exists for this schedule on this date")
                        self.logger.error("❌ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }                
                    
                    
                    // Create new attendance
                    let newAttendance = Attendance(context: self.backgroundContext)
                    newAttendance.attendanceId = UUID()
                    newAttendance.attendanceType = attendanceData.attendanceType.trimmingCharacters(in: .whitespacesAndNewlines)
                    newAttendance.attendancePresence = attendanceData.attendancePresent.trimmingCharacters(in: .whitespacesAndNewlines)
                    newAttendance.attendanceEvent = attendanceData.attendanceEvent.trimmingCharacters(in: .whitespacesAndNewlines)
                    newAttendance.attendanceDate = attendanceData.attendanceDate
                    newAttendance.schedule = backgroundSchedule
                    
                    // Save background context
                    try self.backgroundContext.save()
                    
                    // Get object in main context
                    let mainContextAttendance = try self.persistentContainer.viewContext.existingObject(with: newAttendance.objectID) as! Attendance
                    
                    self.logger.info("✅ Attendance created successfully for schedule: \(backgroundSchedule.scheduleId?.uuidString ?? "unknown")")
                    continuation.resume(returning: mainContextAttendance)
                    
                } catch let error as AttendanceRepositoryError {
                    continuation.resume(throwing: error)
                } catch {
                    let wrappedError = AttendanceRepositoryError.coreDataError("Failed to create attendance: \(error.localizedDescription)")
                    self.logger.error("❌ \(wrappedError.localizedDescription)")
                    continuation.resume(throwing: wrappedError)
                }
            }
        }
    }
    
    // MARK: - Update Attendance
    func updateAttendance(attendanceId: UUID, attendanceData: AttendanceData) async throws -> Attendance {
        self.logger.debug("📝 Updating attendance: \(attendanceId.uuidString)")
        
        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    // Find attendance in background context
                    let attendanceFetchRequest: NSFetchRequest<Attendance> = Attendance.fetchRequest()
                    attendanceFetchRequest.predicate = NSPredicate(format: "attendanceId == %@", attendanceId as CVarArg)
                    attendanceFetchRequest.fetchLimit = 1
                    
                    let attendances = try self.backgroundContext.fetch(attendanceFetchRequest)
                    guard let attendance = attendances.first else {
                        let error = AttendanceRepositoryError.attendanceNotFound("Attendance with ID \(attendanceId.uuidString) not found")
                        self.logger.error("❌ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    // Validate attendance data
                    guard !attendanceData.attendanceType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        let error = AttendanceRepositoryError.invalidAttendanceData("Attendance type cannot be empty")
                        self.logger.error("❌ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    guard !attendanceData.attendancePresent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        let error = AttendanceRepositoryError.invalidAttendanceData("Attendance present status cannot be empty")
                        self.logger.error("❌ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    // Check for duplicate attendance for the same schedule and event (excluding current attendance)
                    if let schedule = attendance.schedule {
                        let duplicateCheckRequest: NSFetchRequest<Attendance> = Attendance.fetchRequest()
                        duplicateCheckRequest.predicate = NSPredicate(
                            format: "schedule == %@ AND attendanceEvent == %@ AND attendanceId != %@ ",
                            schedule,
                            attendanceData.attendanceEvent,
                            attendanceId as CVarArg
                        )
                        duplicateCheckRequest.fetchLimit = 1
                        
                        let existingAttendance = try self.backgroundContext.fetch(duplicateCheckRequest)
                        if !existingAttendance.isEmpty {
                            let error = AttendanceRepositoryError.duplicateAttendance("Attendance already exists for this schedule and event")
                            self.logger.error("❌ \(error.localizedDescription)")
                            continuation.resume(throwing: error)
                            return
                        }
                    }
                    
                    // Update attendance properties
                    attendance.attendanceType = attendanceData.attendanceType.trimmingCharacters(in: .whitespacesAndNewlines)
                    attendance.attendancePresence = attendanceData.attendancePresent.trimmingCharacters(in: .whitespacesAndNewlines)
                    attendance.attendanceEvent = attendanceData.attendanceEvent.trimmingCharacters(in: .whitespacesAndNewlines)
                    attendance.attendanceDate = attendanceData.attendanceDate
                    
                    // Save background context
                    try self.backgroundContext.save()
                    
                    // Get object in main context
                    let mainContextAttendance = try self.persistentContainer.viewContext.existingObject(with: attendance.objectID) as! Attendance
                    
                    self.logger.info("✅ Attendance updated successfully: \(attendanceId.uuidString)")
                    continuation.resume(returning: mainContextAttendance)
                    
                } catch let error as AttendanceRepositoryError {
                    continuation.resume(throwing: error)
                } catch {
                    let wrappedError = AttendanceRepositoryError.coreDataError("Failed to update attendance: \(error.localizedDescription)")
                    self.logger.error("❌ \(wrappedError.localizedDescription)")
                    continuation.resume(throwing: wrappedError)
                }
            }
        }
    }
    
    // MARK: - Delete Attendance
    func deleteAttendance(attendanceId: UUID) async throws {
        self.logger.debug("🗑️ Deleting attendance: \(attendanceId.uuidString)")
        
        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    // Find attendance in background context
                    let fetchRequest: NSFetchRequest<Attendance> = Attendance.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "attendanceId == %@", attendanceId as CVarArg)
                    fetchRequest.fetchLimit = 1
                    
                    let attendances = try self.backgroundContext.fetch(fetchRequest)
                    guard let attendance = attendances.first else {
                        let error = AttendanceRepositoryError.attendanceNotFound("Attendance with ID \(attendanceId.uuidString) not found")
                        self.logger.warning("⚠️ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    let scheduleId = attendance.schedule?.scheduleId?.uuidString ?? "Unknown Schedule"
                    
                    // Delete the attendance
                    self.backgroundContext.delete(attendance)
                    
                    // Save background context
                    try self.backgroundContext.save()
                    
                    self.logger.info("✅ Attendance deleted successfully for schedule: \(scheduleId)")
                    continuation.resume()
                    
                } catch let error as AttendanceRepositoryError {
                    continuation.resume(throwing: error)
                } catch {
                    let wrappedError = AttendanceRepositoryError.coreDataError("Failed to delete attendance: \(error.localizedDescription)")
                    self.logger.error("❌ \(wrappedError.localizedDescription)")
                    continuation.resume(throwing: wrappedError)
                }
            }
        }
    }
    
    // MARK: - Get All Attendance for Subject
    func getAllAttendance(for subject: Subject) async throws -> [Attendance] {
        self.logger.debug("📚 Fetching all attendance for subject: \(subject.subjectName ?? "unknown")")
        
        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    // Get subject in background context
                    guard let backgroundSubject = try? self.backgroundContext.existingObject(with: subject.objectID) as? Subject else {
                        let error = AttendanceRepositoryError.subjectNotFound("Subject not found in background context")
                        self.logger.error("❌ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    let fetchRequest: NSFetchRequest<Attendance> = Attendance.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "schedule.subject == %@", backgroundSubject)
                    
                    // Sort by attendance date and type
                    fetchRequest.sortDescriptors = [
                        NSSortDescriptor(key: "attendanceDate", ascending: false), // Most recent first
                        NSSortDescriptor(key: "attendanceType", ascending: true)
                    ]
                    
                    let backgroundAttendances = try self.backgroundContext.fetch(fetchRequest)
                    
                    // Convert to main context objects
                    let mainContextAttendances = try backgroundAttendances.map { attendance in
                        try self.persistentContainer.viewContext.existingObject(with: attendance.objectID) as! Attendance
                    }
                    
                    self.logger.info("✅ Fetched \(mainContextAttendances.count) attendance records for subject")
                    continuation.resume(returning: mainContextAttendances)
                    
                } catch let error as AttendanceRepositoryError {
                    continuation.resume(throwing: error)
                } catch {
                    let wrappedError = AttendanceRepositoryError.coreDataError("Failed to fetch attendance for subject: \(error.localizedDescription)")
                    self.logger.error("❌ \(wrappedError.localizedDescription)")
                    continuation.resume(throwing: wrappedError)
                }
            }
        }
    }
    
    // MARK: - Get All Attendance for Date and Subject
    func getAllAttendanceForDate(_ date: Date, subject: Subject) async throws -> [Attendance] {
        self.logger.debug("📅 Fetching attendance for date: \(date) and subject: \(subject.subjectName ?? "unknown")")
        
        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    // Get subject in background context
                    guard let backgroundSubject = try? self.backgroundContext.existingObject(with: subject.objectID) as? Subject else {
                        let error = AttendanceRepositoryError.subjectNotFound("Subject not found in background context")
                        self.logger.error("❌ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    // Get semester from subject and validate date range
                    guard let semester = backgroundSubject.semester else {
                        let error = AttendanceRepositoryError.subjectNotFound("Subject has no associated semester")
                        self.logger.error("❌ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    // Validate that the date is within semester range
                    guard let semesterStartDate = semester.semesterStartDate,
                          let semesterEndDate = semester.semesterEndDate else {
                        let error = AttendanceRepositoryError.invalidAttendanceData("Semester start or end date is missing")
                        self.logger.error("❌ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    // Check if the requested date falls within semester date range
                    let calendar = Calendar.current
                    let dateOnly = calendar.startOfDay(for: date)
                    let startDateOnly = calendar.startOfDay(for: semesterStartDate)
                    let endDateOnly = calendar.startOfDay(for: semesterEndDate)
                    
                    guard dateOnly >= startDateOnly && dateOnly <= endDateOnly else {
                        self.logger.warning("⚠️ Requested date \(date) is outside semester range (\(semesterStartDate) - \(semesterEndDate))")
                        // Return empty array instead of error for dates outside semester range
                        continuation.resume(returning: [])
                        return
                    }
                    
                    // Create date range for the specific day (start of day to end of day)
                    let startOfDay = calendar.startOfDay(for: date)
                    let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
                    
                    let fetchRequest: NSFetchRequest<Attendance> = Attendance.fetchRequest()
                    fetchRequest.predicate = NSPredicate(
                        format: "schedule.subject == %@ AND attendanceDate >= %@ AND attendanceDate < %@",
                        backgroundSubject,
                        startOfDay as NSDate,
                        endOfDay as NSDate
                    )
                    
                    // Sort by attendance date and type
                    fetchRequest.sortDescriptors = [
                        NSSortDescriptor(key: "attendanceDate", ascending: true),
                        NSSortDescriptor(key: "attendanceType", ascending: true)
                    ]
                    
                    let backgroundAttendances = try self.backgroundContext.fetch(fetchRequest)
                    
                    // Convert to main context objects
                    let mainContextAttendances = try backgroundAttendances.map { attendance in
                        try self.persistentContainer.viewContext.existingObject(with: attendance.objectID) as! Attendance
                    }
                    
                    self.logger.info("✅ Fetched \(mainContextAttendances.count) attendance records for \(date) and subject within semester range")
                    continuation.resume(returning: mainContextAttendances)
                    
                } catch let error as AttendanceRepositoryError {
                    continuation.resume(throwing: error)
                } catch {
                    let wrappedError = AttendanceRepositoryError.coreDataError("Failed to fetch attendance for date and subject: \(error.localizedDescription)")
                    self.logger.error("❌ \(wrappedError.localizedDescription)")
                    continuation.resume(throwing: wrappedError)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    func getAttendanceById(_ id: UUID) async throws -> Attendance? {
        self.logger.debug("🔍 Fetching attendance by ID: \(id.uuidString)")
        
        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    let fetchRequest: NSFetchRequest<Attendance> = Attendance.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "attendanceId == %@", id as CVarArg)
                    fetchRequest.fetchLimit = 1
                    
                    let backgroundAttendances = try self.backgroundContext.fetch(fetchRequest)
                    
                    if let backgroundAttendance = backgroundAttendances.first {
                        let mainContextAttendance = try self.persistentContainer.viewContext.existingObject(with: backgroundAttendance.objectID) as! Attendance
                        
                        self.logger.info("✅ Found attendance: \(mainContextAttendance.attendanceEvent ?? "unknown event")")
                        continuation.resume(returning: mainContextAttendance)
                    } else {
                        self.logger.info("ℹ️ No attendance found with ID: \(id.uuidString)")
                        continuation.resume(returning: nil)
                    }
                    
                } catch {
                    let wrappedError = AttendanceRepositoryError.coreDataError("Failed to fetch attendance by ID: \(error.localizedDescription)")
                    self.logger.error("❌ \(wrappedError.localizedDescription)")
                    continuation.resume(throwing: wrappedError)
                }
            }
        }
    }
    
    func getAllAttendanceForSchedule(_ scheduleId: UUID) async throws -> [Attendance] {
        self.logger.debug("📋 Fetching all attendance for schedule: \(scheduleId.uuidString)")
        
        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    let fetchRequest: NSFetchRequest<Attendance> = Attendance.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "schedule.scheduleId == %@", scheduleId as CVarArg)
                    
                    // Sort by attendance date and type
                    fetchRequest.sortDescriptors = [
                        NSSortDescriptor(key: "attendanceDate", ascending: false), // Most recent first
                        NSSortDescriptor(key: "attendanceType", ascending: true)
                    ]
                    
                    let backgroundAttendances = try self.backgroundContext.fetch(fetchRequest)
                    
                    // Convert to main context objects
                    let mainContextAttendances = try backgroundAttendances.map { attendance in
                        try self.persistentContainer.viewContext.existingObject(with: attendance.objectID) as! Attendance
                    }
                    
                    self.logger.info("✅ Fetched \(mainContextAttendances.count) attendance records for schedule")
                    continuation.resume(returning: mainContextAttendances)
                    
                } catch {
                    let wrappedError = AttendanceRepositoryError.coreDataError("Failed to fetch attendance for schedule: \(error.localizedDescription)")
                    self.logger.error("❌ \(wrappedError.localizedDescription)")
                    continuation.resume(throwing: wrappedError)
                }
            }
        }
    }
    
    // MARK: - Get Attendance for Date Range
    func getAttendanceForDateRange(startDate: Date, endDate: Date, subject: Subject) async throws -> [Attendance] {
        self.logger.debug("📊 Fetching attendance for date range: \(startDate) to \(endDate) and subject: \(subject.subjectName ?? "unknown")")
        
        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    // Get subject in background context
                    guard let backgroundSubject = try? self.backgroundContext.existingObject(with: subject.objectID) as? Subject else {
                        let error = AttendanceRepositoryError.subjectNotFound("Subject not found in background context")
                        self.logger.error("❌ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    // Ensure start date is before end date
                    guard startDate <= endDate else {
                        let error = AttendanceRepositoryError.invalidAttendanceData("Start date must be before or equal to end date")
                        self.logger.error("❌ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    // Create date range (start of start date to end of end date)
                    let calendar = Calendar.current
                    let startOfRange = calendar.startOfDay(for: startDate)
                    let endOfRange = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate))!
                    
                    let fetchRequest: NSFetchRequest<Attendance> = Attendance.fetchRequest()
                    fetchRequest.predicate = NSPredicate(
                        format: "schedule.subject == %@ AND attendanceDate >= %@ AND attendanceDate < %@",
                        backgroundSubject,
                        startOfRange as NSDate,
                        endOfRange as NSDate
                    )
                    
                    // Sort by attendance date and type
                    fetchRequest.sortDescriptors = [
                        NSSortDescriptor(key: "attendanceDate", ascending: true),
                        NSSortDescriptor(key: "attendanceType", ascending: true)
                    ]
                    
                    let backgroundAttendances = try self.backgroundContext.fetch(fetchRequest)
                    
                    // Convert to main context objects
                    let mainContextAttendances = try backgroundAttendances.map { attendance in
                        try self.persistentContainer.viewContext.existingObject(with: attendance.objectID) as! Attendance
                    }
                    
                    self.logger.info("✅ Fetched \(mainContextAttendances.count) attendance records for date range")
                    continuation.resume(returning: mainContextAttendances)
                    
                } catch let error as AttendanceRepositoryError {
                    continuation.resume(throwing: error)
                } catch {
                    let wrappedError = AttendanceRepositoryError.coreDataError("Failed to fetch attendance for date range: \(error.localizedDescription)")
                    self.logger.error("❌ \(wrappedError.localizedDescription)")
                    continuation.resume(throwing: wrappedError)
                }
            }
        }
    }
}
