//
//  NotificationService.swift
//  eda
//
//  Created by Siddhartha on 22/07/25.
//

import Foundation
import UserNotifications
import os.log

// MARK: - Custom Error Types
enum NotificationServiceError: LocalizedError {
    case permissionDenied
    case permissionNotDetermined
    case schedulingFailed(String)
    case systemError(String)
    case invalidNotificationData(String)
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Notification permission denied by user"
        case .permissionNotDetermined:
            return "Notification permission not yet determined"
        case .schedulingFailed(let details):
            return "Failed to schedule notifications: \(details)"
        case .systemError(let details):
            return "System error: \(details)"
        case .invalidNotificationData(let details):
            return "Invalid notification data: \(details)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            return "Enable notifications in Settings app"
        case .permissionNotDetermined:
            return "Grant notification permission when prompted"
        case .schedulingFailed:
            return "Try refreshing or restarting the app"
        case .systemError:
            return "Restart the app and try again"
        case .invalidNotificationData:
            return "Check notification content and try again"
        }
    }
}

// MARK: - NotificationService Implementation
class NotificationService {
    private let logger = Logger(
        subsystem: "com.eda.app",
        category: "NotificationService"
    )
    
    private let notificationCenter: UNUserNotificationCenter
    
    // MARK: - Initialization
    init(notificationCenter: UNUserNotificationCenter = UNUserNotificationCenter.current()) {
        self.notificationCenter = notificationCenter
        self.logger.info("🚀 NotificationService initialized")
    }
    
    // MARK: - Authorization Management
    
    /// Requests notification authorization from user
    /// - Returns: Boolean indicating if permission was granted
    func requestAuthorization() async throws -> Bool {
        logger.debug("🔍 Requesting notification authorization")
        
        do {
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            
            if granted {
                logger.info("✅ Notification authorization granted")
            } else {
                logger.warning("⚠️ Notification authorization denied by user")
                throw NotificationServiceError.permissionDenied
            }
            
            return granted
            
        } catch {
            let wrappedError = wrapError(error, context: "requesting authorization")
            logger.error("❌ Failed to request authorization: \(wrappedError.localizedDescription)")
            throw wrappedError
        }
    }
    
    /// Gets current authorization status
    /// - Returns: Current UNAuthorizationStatus
    func getAuthorizationStatus() async -> UNAuthorizationStatus {
        logger.debug("🔍 Checking authorization status")
        
        let settings = await notificationCenter.notificationSettings()
        let status = settings.authorizationStatus
        
        logger.debug("📊 Authorization status: \(status.rawValue)")
        return status
    }
    
    // MARK: - Scheduling Operations
    
    /// Schedules multiple notification requests
    /// - Parameter requests: Array of UNNotificationRequest objects
    func scheduleNotifications(_ requests: [UNNotificationRequest]) async throws {
        guard !requests.isEmpty else {
            logger.warning("⚠️ No notification requests to schedule")
            return
        }
        
        logger.info("📅 Scheduling \(requests.count) notifications")
        
        // Validate authorization first
        let status = await getAuthorizationStatus()
        guard status == .authorized else {
            let error = status == .denied
                ? NotificationServiceError.permissionDenied
                : NotificationServiceError.permissionNotDetermined
            logger.error("❌ Cannot schedule - authorization status: \(status.rawValue)")
            throw error
        }
        
        // Schedule each request individually to catch specific failures
        var successCount = 0
        var errors: [Error] = []
        
        for request in requests {
            do {
                try await notificationCenter.add(request)
                successCount += 1
                logger.debug("✅ Scheduled notification: \(request.identifier)")
            } catch {
                let wrappedError = wrapError(error, context: "scheduling notification \(request.identifier)")
                errors.append(wrappedError)
                logger.error("❌ Failed to schedule \(request.identifier): \(wrappedError.localizedDescription)")
            }
        }
        
        logger.info("📊 Scheduling complete: \(successCount)/\(requests.count) successful")
        
        // If no notifications were scheduled successfully, throw error
        if successCount == 0 && !errors.isEmpty {
            throw NotificationServiceError.schedulingFailed(
                "Failed to schedule any notifications. First error: \(errors.first?.localizedDescription ?? "Unknown")"
            )
        }
    }
    
    // MARK: - Cancellation Operations
    
    /// Cancels specific notifications by their identifiers
    /// - Parameter ids: Array of notification identifiers to cancel
    func cancelNotifications(withIds ids: [String]) async throws {
        guard !ids.isEmpty else {
            logger.warning("⚠️ No notification IDs provided for cancellation")
            return
        }
        
        logger.info("🗑️ Cancelling \(ids.count) notifications")
        
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ids)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: ids)
        
        logger.debug("✅ Cancelled notifications: \(ids.joined(separator: ", "))")
    }
    
    /// Cancels all scheduled and delivered notifications
    func cancelAllNotifications() async throws {
        logger.info("🗑️ Cancelling all notifications")
        
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.removeAllDeliveredNotifications()
        
        logger.info("✅ All notifications cancelled")
    }
    
    // MARK: - Query Operations
    
    /// Gets all pending notification requests
    /// - Returns: Array of pending UNNotificationRequest objects
    func getPendingNotifications() async -> [UNNotificationRequest] {
        logger.debug("🔍 Fetching pending notifications")
        
        let requests = await notificationCenter.pendingNotificationRequests()
        
        logger.debug("📊 Found \(requests.count) pending notifications")
        return requests
    }
    
    /// Gets all delivered notifications
    /// - Returns: Array of delivered UNNotification objects
    func getDeliveredNotifications() async -> [UNNotification] {
        logger.debug("🔍 Fetching delivered notifications")
        
        let notifications = await notificationCenter.deliveredNotifications()
        
        logger.debug("📊 Found \(notifications.count) delivered notifications")
        return notifications
    }
    
    /// Gets count of pending notifications
    /// - Returns: Number of pending notifications
    func getPendingNotificationCount() async -> Int {
        let requests = await getPendingNotifications()
        return requests.count
    }
    
    // MARK: - Private Helper Methods
    
    /// Wraps system errors into our custom error types
    private func wrapError(_ error: Error, context: String) -> NotificationServiceError {
        if let serviceError = error as? NotificationServiceError {
            return serviceError
        }
        
        if let nsError = error as NSError? {
            switch nsError.code {
            case UNError.notificationsNotAllowed.rawValue:
                return .permissionDenied
            case UNError.attachmentInvalidURL.rawValue,
                 UNError.attachmentUnrecognizedType.rawValue:
                return .invalidNotificationData(nsError.localizedDescription)
            default:
                return .systemError("System error in \(context): \(nsError.localizedDescription)")
            }
        }
        
        return .systemError("Unknown error in \(context): \(error.localizedDescription)")
    }
}
