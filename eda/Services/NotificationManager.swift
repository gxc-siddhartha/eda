//
//  NotificationManager.swift
//  eda
//
//  Created by Assistant on 22/07/25.
//

import Foundation
import UserNotifications
import SwiftUI
import os.log

// MARK: - Custom Error Types
enum NotificationManagerError: LocalizedError {
    case permissionDenied
    case permissionNotDetermined
    case invalidSemesterDates
    case schedulingFailed(String)
    case systemError(String)
    case noActiveSemester
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Notification permission denied by user"
        case .permissionNotDetermined:
            return "Notification permission not yet determined"
        case .invalidSemesterDates:
            return "Semester has invalid start or end dates"
        case .schedulingFailed(let details):
            return "Failed to schedule reminders: \(details)"
        case .systemError(let details):
            return "System error: \(details)"
        case .noActiveSemester:
            return "No active semester available"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            return "Enable notifications in Settings app"
        case .permissionNotDetermined:
            return "Grant notification permission when prompted"
        case .invalidSemesterDates:
            return "Check semester start and end dates"
        case .schedulingFailed:
            return "Try refreshing or restarting the app"
        case .systemError:
            return "Restart the app and try again"
        case .noActiveSemester:
            return "Select an active semester first"
        }
    }
}

// MARK: - Daily Reminder Configuration
struct DailyReminderTime {
    let hour: Int
    let minute: Int
    let message: String
    let identifier: String
    
    static let morningReminder = DailyReminderTime(
        hour: 9,
        minute: 0,
        message: "🌅 Good morning! Let's check what's going on today.",
        identifier: "morning-reminder"
    )
    
    static let afternoonReminder = DailyReminderTime(
        hour: 13,
        minute: 0,
        message: "🌇 Afternoon slugger! Check your attendance.",
        identifier: "afternoon-reminder"
    )
    
    static let eveningReminder = DailyReminderTime(
        hour: 18,
        minute: 0,
        message: "🌄 Evening! Wrap up your day.",
        identifier: "evening-reminder"
    )
    
    static let allReminders = [morningReminder, afternoonReminder, eveningReminder]
}

// MARK: - NotificationManager Implementation
@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    // MARK: - Dependencies
    private let notificationService: NotificationService
    private let logger = Logger(
        subsystem: "com.eda.app",
        category: "NotificationManager"
    )
    
    // MARK: - Constants
    private let schedulingWindowDays = 10  // Schedule 30 days ahead
    private let maintenanceIntervalDays = 7  // Perform maintenance weekly
    
    // MARK: - Published State
    @Published private(set) var isSchedulingInProgress = false
    @Published private(set) var lastMaintenanceDate: Date?
    @Published private(set) var currentSemesterId: UUID?
    
    // MARK: - Initialization
    private init(notificationService: NotificationService = NotificationService()) {
        self.notificationService = notificationService
        self.logger.info("🚀 NotificationManager initialized")
    }
    
    // MARK: - Permission Management
    
    /// Requests notification permission from user (call after first schedule creation)
    func requestPermissionAfterFirstSchedule() async throws -> Bool {
        logger.info("🔑 Requesting notification permission after first schedule")
        
        let status = await notificationService.getAuthorizationStatus()
        
        switch status {
        case .authorized:
            logger.info("✅ Permission already granted")
            return true
            
        case .denied:
            logger.warning("⚠️ Permission previously denied")
            throw NotificationManagerError.permissionDenied
            
        case .notDetermined:
            logger.debug("🔍 Permission not determined, requesting...")
            do {
                let granted = try await notificationService.requestAuthorization()
                return granted
            } catch {
                let wrappedError = wrapError(error, context: "requesting permission")
                throw wrappedError
            }
            
        case .provisional, .ephemeral:
            // Try to upgrade to full authorization
            logger.debug("🔄 Upgrading to full authorization")
            do {
                let granted = try await notificationService.requestAuthorization()
                return granted
            } catch {
                let wrappedError = wrapError(error, context: "upgrading permission")
                throw wrappedError
            }
            
        @unknown default:
            logger.warning("⚠️ Unknown authorization status: \(status.rawValue)")
            throw NotificationManagerError.systemError("Unknown authorization status")
        }
    }
    
    /// Checks current permission status
    func checkPermissionStatus() async -> UNAuthorizationStatus {
        let status = await notificationService.getAuthorizationStatus()
        logger.debug("📊 Current permission status: \(status.rawValue)")
        return status
    }
    
    // MARK: - Semester Operations
    
    /// Schedules daily reminders for the entire semester
    func scheduleRemindersForSemester(_ semester: Semester) async throws {
        guard let semesterId = semester.semesterId else {
            let error = NotificationManagerError.invalidSemesterDates
            logger.error("❌ \(error.localizedDescription)")
            throw error
        }
        
        logger.info("🗓️ Scheduling reminders for semester: \(semester.semesterName ?? "unknown")")
        
        // Validate permission first
        let status = await checkPermissionStatus()
        guard status == .authorized else {
            let error = status == .denied
                ? NotificationManagerError.permissionDenied
                : NotificationManagerError.permissionNotDetermined
            logger.warning("⚠️ Cannot schedule - permission status: \(status.rawValue)")
            throw error
        }
        
        // Validate semester dates
        guard let startDate = semester.semesterStartDate,
              let endDate = semester.semesterEndDate,
              startDate <= endDate else {
            let error = NotificationManagerError.invalidSemesterDates
            logger.error("❌ \(error.localizedDescription)")
            throw error
        }
        
        isSchedulingInProgress = true
        
        do {
            // Smart duplicate prevention - only reschedule if needed
            if await shouldRescheduleNotifications(for: semesterId, semester: semester) {
                logger.info("🔄 Rescheduling needed - cleaning up existing notifications")
                try await cancelRemindersForSemester(semesterId)
            } else {
                logger.info("✅ Valid notifications already exist - skipping reschedule")
                isSchedulingInProgress = false
                return
            }
            
            currentSemesterId = semesterId
            
            // Generate notification requests
            let requests = generateNotificationRequests(
                for: semester,
                startDate: startDate,
                endDate: endDate
            )
            
            logger.info("📅 Generated \(requests.count) notification requests")
            
            // Schedule notifications
            try await notificationService.scheduleNotifications(requests)
            
            // Update maintenance date
            lastMaintenanceDate = Date()
            
            logger.info("✅ Successfully scheduled reminders for semester: \(semester.semesterName ?? "unknown")")
            
        } catch {
            let wrappedError = wrapError(error, context: "scheduling semester reminders")
            logger.error("❌ Failed to schedule semester reminders: \(wrappedError.localizedDescription)")
            throw wrappedError
        }
        
        isSchedulingInProgress = false
    }
    
    /// Cancels all scheduled reminders
    func cancelAllReminders() async throws {
        logger.info("🗑️ Cancelling all reminders")
        
        do {
            try await notificationService.cancelAllNotifications()
            currentSemesterId = nil
            logger.info("✅ All reminders cancelled")
        } catch {
            let wrappedError = wrapError(error, context: "cancelling reminders")
            logger.error("❌ Failed to cancel reminders: \(wrappedError.localizedDescription)")
            throw wrappedError
        }
    }
    
    /// Cancels reminders for a specific semester
    func cancelRemindersForSemester(_ semesterId: UUID) async throws {
        logger.info("🗑️ Cancelling reminders for semester: \(semesterId.uuidString)")
        
        do {
            let pendingNotifications = await notificationService.getPendingNotifications()
            let semesterNotificationIds = pendingNotifications
                .filter { $0.identifier.contains(semesterId.uuidString) }
                .map { $0.identifier }
            
            if !semesterNotificationIds.isEmpty {
                try await notificationService.cancelNotifications(withIds: semesterNotificationIds)
                logger.info("✅ Cancelled \(semesterNotificationIds.count) reminders for semester")
            } else {
                logger.info("ℹ️ No reminders found for semester")
            }
            
            if currentSemesterId == semesterId {
                currentSemesterId = nil
            }
            
        } catch {
            let wrappedError = wrapError(error, context: "cancelling semester reminders")
            logger.error("❌ Failed to cancel semester reminders: \(wrappedError.localizedDescription)")
            throw wrappedError
        }
    }
    
    // MARK: - Maintenance Operations
    
    /// Performs weekly maintenance - cleanup old notifications and schedule new ones
    func performWeeklyMaintenance(for semester: Semester?) async throws {
        logger.info("🔧 Performing weekly maintenance")
        
        guard let semester = semester else {
            logger.warning("⚠️ No semester provided for maintenance")
            throw NotificationManagerError.noActiveSemester
        }
        
        // Check if maintenance is needed
        if let lastMaintenance = lastMaintenanceDate {
            let daysSinceLastMaintenance = Calendar.current.dateComponents([.day], from: lastMaintenance, to: Date()).day ?? 0
            if daysSinceLastMaintenance < maintenanceIntervalDays {
                logger.debug("🔍 Maintenance not needed yet (last: \(daysSinceLastMaintenance) days ago)")
                return
            }
        }
        
        do {
            // Get current pending notifications
            let pendingCount = await notificationService.getPendingNotificationCount()
            logger.debug("📊 Current pending notifications: \(pendingCount)")
            
            // Clean up past notifications and reschedule if needed
            try await scheduleRemindersForSemester(semester)
            
            logger.info("✅ Weekly maintenance completed")
            
        } catch {
            let wrappedError = wrapError(error, context: "performing maintenance")
            logger.error("❌ Maintenance failed: \(wrappedError.localizedDescription)")
            throw wrappedError
        }
    }
    
    /// Check if maintenance is needed and perform it
    func refreshRemindersIfNeeded(for semester: Semester?) async throws {
        guard let semester = semester else { return }
        
        if needsMaintenance() {
            try await performWeeklyMaintenance(for: semester)
        }
    }
    
    // MARK: - Query Operations
    
    /// Determines if notifications need to be rescheduled
    private func shouldRescheduleNotifications(for semesterId: UUID, semester: Semester) async -> Bool {
        let pendingNotifications = await notificationService.getPendingNotifications()
        let semesterNotifications = pendingNotifications.filter {
            $0.identifier.contains(semesterId.uuidString)
        }
        
        // No existing notifications - need to schedule
        if semesterNotifications.isEmpty {
            logger.debug("🔍 No existing notifications found - scheduling needed")
            return true
        }
        
        // Check if we have sufficient future coverage (at least 20 days ahead)
        let calendar = Calendar.current
        let twentyDaysFromNow = calendar.date(byAdding: .day, value: 10, to: Date()) ?? Date()
        
        let futureNotifications = semesterNotifications.compactMap { request -> Date? in
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let triggerDate = trigger.nextTriggerDate() else { return nil }
            return triggerDate > twentyDaysFromNow ? triggerDate : nil
        }
        
        // If we have fewer than 30 notifications covering the next 20+ days, reschedule
        if futureNotifications.count < 10 {
            logger.debug("🔍 Insufficient future coverage (\(futureNotifications.count) notifications) - rescheduling needed")
            return true
        }
        
        // Check if semester dates have changed (notifications might be outside new boundaries)
        guard let semesterStart = semester.semesterStartDate,
              let semesterEnd = semester.semesterEndDate else {
            logger.debug("🔍 Invalid semester dates - rescheduling needed")
            return true
        }
        
        // Verify existing notifications are within semester boundaries
        let invalidNotifications = semesterNotifications.filter { request in
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let triggerDate = trigger.nextTriggerDate() else { return true }
            return triggerDate < calendar.startOfDay(for: semesterStart) ||
                   triggerDate > calendar.startOfDay(for: semesterEnd)
        }
        
        if !invalidNotifications.isEmpty {
            logger.debug("🔍 Found \(invalidNotifications.count) notifications outside semester boundaries - rescheduling needed")
            return true
        }
        
        logger.debug("✅ Existing notifications are valid and sufficient - no rescheduling needed")
        return false
    }
    
    /// Gets the count of currently scheduled reminders for a specific semester
    func getScheduledReminderCountForSemester(_ semesterId: UUID) async -> Int {
        let pendingNotifications = await notificationService.getPendingNotifications()
        let semesterNotifications = pendingNotifications.filter {
            $0.identifier.contains(semesterId.uuidString)
        }
        let count = semesterNotifications.count
        logger.debug("📊 Semester \(semesterId.uuidString) has \(count) scheduled reminders")
        return count
    }
    
    /// Gets the count of currently scheduled reminders
    func getScheduledReminderCount() async -> Int {
        let count = await notificationService.getPendingNotificationCount()
        logger.debug("📊 Current scheduled reminder count: \(count)")
        return count
    }
    
    /// Checks if the system needs maintenance
    func needsMaintenance() -> Bool {
        guard let lastMaintenance = lastMaintenanceDate else {
            return true  // Never performed maintenance
        }
        
        let daysSinceLastMaintenance = Calendar.current.dateComponents([.day], from: lastMaintenance, to: Date()).day ?? 0
        return daysSinceLastMaintenance >= maintenanceIntervalDays
    }
    
    // MARK: - Private Helper Methods
    
    /// Generates notification requests for the semester (excluding Sundays)
    private func generateNotificationRequests(
        for semester: Semester,
        startDate: Date,
        endDate: Date
    ) -> [UNNotificationRequest] {
        let calendar = Calendar.current
        let now = Date()
        
        // Calculate scheduling range (from today to 30 days ahead or semester end, whichever is sooner)
        let schedulingStartDate = max(calendar.startOfDay(for: now), calendar.startOfDay(for: startDate))
        let thirtyDaysFromNow = calendar.date(byAdding: .day, value: schedulingWindowDays, to: now) ?? now
        let schedulingEndDate = min(thirtyDaysFromNow, endDate)
        
        logger.debug("📅 Scheduling range: \(schedulingStartDate) to \(schedulingEndDate)")
        
        var requests: [UNNotificationRequest] = []
        var currentDate = schedulingStartDate
        
        // Generate requests for each day in the range (excluding Sundays)
        while currentDate <= schedulingEndDate {
            let weekday = calendar.component(.weekday, from: currentDate)
            
            // Skip Sundays (weekday 1 = Sunday)
            if weekday == 1 {
                logger.debug("🔍 Skipping Sunday: \(currentDate)")
            } else {
                // Generate reminders for this day
                for reminderTime in DailyReminderTime.allReminders {
                    if let request = createNotificationRequest(
                        for: currentDate,
                        reminderTime: reminderTime,
                        semester: semester
                    ) {
                        requests.append(request)
                    }
                }
            }
            
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else {
                break
            }
            currentDate = nextDate
        }
        
        logger.debug("✅ Generated \(requests.count) notification requests (Sundays excluded)")
        return requests
    }
    
    /// Creates a single notification request
    private func createNotificationRequest(
        for date: Date,
        reminderTime: DailyReminderTime,
        semester: Semester
    ) -> UNNotificationRequest? {
        let calendar = Calendar.current
        
        // Create trigger date by combining the date with reminder time
        var triggerComponents = calendar.dateComponents([.year, .month, .day], from: date)
        triggerComponents.hour = reminderTime.hour
        triggerComponents.minute = reminderTime.minute
        triggerComponents.second = 0
        
        guard let triggerDate = calendar.date(from: triggerComponents) else {
            logger.warning("⚠️ Failed to create trigger date for \(date)")
            return nil
        }
        
        // Don't schedule notifications in the past
        if triggerDate <= Date() {
            logger.debug("🔍 Skipping past notification: \(triggerDate)")
            return nil
        }
        
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "eda"
        content.body = reminderTime.message
        content.sound = .default
        content.badge = 1
        
        // Create trigger
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: triggerComponents,
            repeats: false
        )
        
        // Create unique identifier
        let identifier = createNotificationIdentifier(
            semesterId: semester.semesterId ?? UUID(),
            date: date,
            reminderType: reminderTime.identifier
        )
        
        // Create request
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        logger.debug("📝 Created notification request: \(identifier) for \(triggerDate)")
        return request
    }
    
    /// Creates a unique notification identifier
    private func createNotificationIdentifier(
        semesterId: UUID,
        date: Date,
        reminderType: String
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)
        
        return "reminder-\(semesterId.uuidString)-\(dateString)-\(reminderType)"
    }
    
    /// Wraps errors into NotificationManagerError
    private func wrapError(_ error: Error, context: String) -> NotificationManagerError {
        if let managerError = error as? NotificationManagerError {
            return managerError
        }
        
        if let serviceError = error as? NotificationServiceError {
            switch serviceError {
            case .permissionDenied:
                return .permissionDenied
            case .permissionNotDetermined:
                return .permissionNotDetermined
            case .schedulingFailed(let details):
                return .schedulingFailed(details)
            case .systemError(let details):
                return .systemError(details)
            case .invalidNotificationData(let details):
                return .systemError("Invalid data in \(context): \(details)")
            }
        }
        
        return .systemError("Unknown error in \(context): \(error.localizedDescription)")
    }
}
