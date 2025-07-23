//
//  NotificationViewModelExtensions.swift
//  eda
//
//  Created by Assistant on 22/07/25.
//

import Foundation
import SwiftUI
import os.log

// MARK: - SemesterViewModel Notification Extensions
extension SemesterViewModel {
    
    /// Schedules notifications when a semester is selected
    /// Call this at the END of selectSemester() method
    func scheduleNotificationsForSelectedSemester(_ semester: Semester) async {
        logger.debug("🔔 Setting up notifications for semester: \(semester.semesterName ?? "unknown")")
        
        do {
            try await NotificationManager.shared.scheduleRemindersForSemester(semester)
            logger.info("✅ Successfully scheduled notifications for semester")
        } catch {
            logger.error("❌ Failed to schedule notifications: \(error.localizedDescription)")
            // Don't throw - semester selection succeeded, notifications are a bonus feature
        }
    }
    
    /// Requests notification permission after first semester creation
    /// Call this at the END of createSemester() method
    func requestNotificationPermissionAfterFirstSemester() async {
        logger.debug("🔑 Requesting notification permission after semester creation")
        
        do {
            let granted = try await NotificationManager.shared.requestPermissionAfterFirstSchedule()
            if granted {
                logger.info("✅ Notification permission granted")
            } else {
                logger.info("ℹ️ Notification permission denied - app will continue normally")
            }
        } catch {
            logger.error("❌ Failed to request notification permission: \(error.localizedDescription)")
            // Don't show error to user - this is non-critical
        }
    }
    
    /// Cancels notifications when semester is deleted
    /// Call this at the BEGINNING of deleteSemester() method
    func cancelNotificationsForSemester(_ semester: Semester) async {
        guard let semesterId = semester.semesterId else { return }
        
        logger.debug("🗑️ Cancelling notifications for semester: \(semester.semesterName ?? "unknown")")
        
        do {
            try await NotificationManager.shared.cancelRemindersForSemester(semesterId)
            logger.info("✅ Successfully cancelled notifications for semester")
        } catch {
            logger.error("❌ Failed to cancel notifications: \(error.localizedDescription)")
            // Don't throw - deletion should continue regardless
        }
    }
    
    /// Performs notification maintenance during app lifecycle
    /// Call this during app initialization or periodic maintenance
    func performNotificationMaintenance() async {
        guard let currentSemester = selectedSemesterForUser else {
            logger.debug("🔍 No active semester for notification maintenance")
            return
        }
        
        logger.debug("🔧 Performing notification maintenance")
        
        do {
            try await NotificationManager.shared.refreshRemindersIfNeeded(for: currentSemester)
            logger.info("✅ Notification maintenance completed")
        } catch {
            logger.error("❌ Notification maintenance failed: \(error.localizedDescription)")
            // Don't throw - this is background maintenance
        }
    }
}

// MARK: - ScheduleViewModel Notification Extensions
extension ScheduleViewModel {
    
    /// Refreshes notifications when schedule operations might affect them
    /// Call this after ANY schedule CRUD operation (create/update/delete)
    func refreshNotificationsAfterScheduleChange() async {
        logger.debug("🔄 Refreshing notifications after schedule change")
        
        // Get current semester from any existing schedule or from semester service
        guard let currentSemester = getCurrentSemesterForNotifications() else {
            logger.debug("🔍 No current semester available for notification refresh")
            return
        }
        
        do {
            try await NotificationManager.shared.performWeeklyMaintenance(for: currentSemester)
            logger.info("✅ Notifications refreshed after schedule change")
        } catch {
            logger.error("❌ Failed to refresh notifications: \(error.localizedDescription)")
            // Don't throw - schedule operation succeeded, notification refresh is bonus
        }
    }
    
    /// Requests notification permission after first schedule creation
    /// Call this at the END of createSchedule() method
    func requestNotificationPermissionAfterFirstSchedule() async {
        logger.debug("🔑 Requesting notification permission after first schedule")
        
        do {
            let granted = try await NotificationManager.shared.requestPermissionAfterFirstSchedule()
            if granted {
                logger.info("✅ Notification permission granted")
                // Immediately refresh notifications for current semester
                await refreshNotificationsAfterScheduleChange()
            } else {
                logger.info("ℹ️ Notification permission denied - app will continue normally")
            }
        } catch {
            logger.error("❌ Failed to request notification permission: \(error.localizedDescription)")
            // Don't show error to user - this is non-critical
        }
    }
    
    /// Helper method to get current semester from available data
    private func getCurrentSemesterForNotifications() -> Semester? {
        // Use stored reference first
        if let semester = currentSemester {
            return semester
        }
        
        // Fallback: Try to get semester from any existing schedule
        if let firstSchedule = schedulesList.first,
           let semester = firstSchedule.subject?.semester {
            return semester
        }
        
        logger.debug("🔍 Could not determine current semester from schedules")
        return nil
    }
}

// MARK: - SubjectViewModel Notification Extensions
extension SubjectViewModel {
    
    /// Requests notification permission after first subject creation
    /// Call this at the END of createSubject() method
    func requestNotificationPermissionAfterFirstSubject() async {
        logger.debug("🔑 Requesting notification permission after first subject")
        
        do {
            let granted = try await NotificationManager.shared.requestPermissionAfterFirstSchedule()
            if granted {
                logger.info("✅ Notification permission granted after subject creation")
            } else {
                logger.info("ℹ️ Notification permission denied - app will continue normally")
            }
        } catch {
            logger.error("❌ Failed to request notification permission: \(error.localizedDescription)")
            // Don't show error to user - this is non-critical
        }
    }
}

// MARK: - App Launch Integration Helper
struct NotificationAppLaunchHelper {
    private static let logger = Logger(
        subsystem: "com.eda.app",
        category: "NotificationAppLaunch"
    )
    
    /// Initializes notifications during app launch
    /// Call this from edaApp.swift in the .task block
    static func initializeNotificationsOnAppLaunch(
        semesterViewModel: SemesterViewModel,
        subjectViewModel: SubjectViewModel
    ) async {
        logger.info("🚀 Initializing notifications on app launch")
        
        // Only proceed if we have an active semester
        guard let currentSemester = await semesterViewModel.selectedSemesterForUser else {
            logger.debug("🔍 No active semester on launch - skipping notification setup")
            return
        }
        
        // Only proceed if there are subjects (indicates user is actually using the app)
        guard await !subjectViewModel.subjectsList.isEmpty else {
            logger.debug("🔍 No subjects found on launch - skipping notification setup")
            return
        }
        
        logger.debug("📚 Active semester found with subjects - setting up notifications")
        
        // Check if notification permission exists
        let status = await NotificationManager.shared.checkPermissionStatus()
        
        switch status {
        case .authorized:
            logger.info("✅ Notification permission already granted - scheduling reminders")
            do {
                try await NotificationManager.shared.scheduleRemindersForSemester(currentSemester)
                logger.info("✅ App launch notification setup completed")
            } catch {
                logger.error("❌ Failed to schedule reminders on app launch: \(error.localizedDescription)")
            }
            
        case .denied:
            logger.info("ℹ️ Notification permission denied - app will function normally")
            
        case .notDetermined:
            logger.debug("🔍 Notification permission not determined - will request when user creates next item")
            
        default:
            logger.debug("🔍 Notification permission status: \(status.rawValue)")
        }
    }
    
    /// Performs periodic notification maintenance
    /// Call this from scene phase changes or periodic app events
    static func performPeriodicMaintenance(for semesterViewModel: SemesterViewModel) async {
        logger.debug("🔧 Performing periodic notification maintenance")
        
        guard let currentSemester = await semesterViewModel.selectedSemesterForUser else {
            logger.debug("🔍 No active semester for maintenance")
            return
        }
        
        do {
            try await NotificationManager.shared.refreshRemindersIfNeeded(for: currentSemester)
            logger.info("✅ Periodic notification maintenance completed")
        } catch {
            logger.error("❌ Periodic maintenance failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Integration Instructions and Examples

/*
 INTEGRATION INSTRUCTIONS:
 
 1. **SemesterViewModel.swift** - Add these calls:
 
    // In selectSemester() method - ADD at the end before return:
    Task {
        await scheduleNotificationsForSelectedSemester(semester)
    }
 
    // In createSemester() method - ADD at the end before return:
    Task {
        await requestNotificationPermissionAfterFirstSemester()
    }
 
    // In deleteSemester() method - ADD at the beginning:
    Task {
        await cancelNotificationsForSemester(semester)
    }
 
 2. **ScheduleViewModel.swift** - Add these calls:
 
    // In createSchedule() method - ADD at the end before return:
    Task {
        await requestNotificationPermissionAfterFirstSchedule()
    }
 
    // In updateSchedule() method - ADD at the end before return:
    Task {
        await refreshNotificationsAfterScheduleChange()
    }
 
    // In deleteSchedule() method - ADD at the end:
    Task {
        await refreshNotificationsAfterScheduleChange()
    }
 
 3. **SubjectViewModel.swift** - Add this call:
 
    // In createSubject() method - ADD at the end before return:
    Task {
        await requestNotificationPermissionAfterFirstSubject()
    }
 
 4. **edaApp.swift** - Add this to the .task block:
 
    .task {
        // ... existing initialization code ...
        
        // ADD this after all ViewModels are initialized:
        await NotificationAppLaunchHelper.initializeNotificationsOnAppLaunch(
            semesterViewModel: semesterViewModel,
            subjectViewModel: subjectViewModel
        )
    }
 
 5. **HomeView.swift** - Add periodic maintenance:
 
    // In onChange(of: scenePhase) - ADD this case:
    .onChange(of: scenePhase) { oldPhase, newPhase in
        if newPhase == .active {
            Task {
                await NotificationAppLaunchHelper.performPeriodicMaintenance(
                    for: semesterViewModel
                )
                
                // ... existing code ...
            }
        }
    }
 
 IMPORTANT NOTES:
 - All notification operations are wrapped in Task {} to avoid blocking
 - Errors are logged but don't break existing functionality
 - Permission requests happen at optimal times (after user creates content)
 - All operations are non-blocking and fail gracefully
 - Notifications enhance the app but don't break it if they fail
*/
