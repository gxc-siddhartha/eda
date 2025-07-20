//
//  ScheduleViewModel.swift
//  eda
//
//  Created by Siddhartha Srivastava on 12/07/25.
//

import CoreData
import Foundation
import SwiftUI
import os.log

// MARK: - Custom Error Types
enum ScheduleViewModelError: LocalizedError {
    case validationFailed(String)
    case repositoryError(String)
    case networkError(String)
    case userCancelled
    case timeConflict(String)
    case scheduleNotFound(String)
    case subjectNotFound(String)
    case semesterNotFound(String)
    case operationTimeout
    case invalidState(String)
    case coreDataError(String)
    case noSemesterSelected
    case invalidTimeRange

    var errorDescription: String? {
        switch self {
        case .validationFailed(let message):
            return "Validation Error: \(message)"
        case .repositoryError(let message):
            return "Data Error: \(message)"
        case .networkError(let message):
            return "Network Error: \(message)"
        case .userCancelled:
            return "Operation was cancelled"
        case .timeConflict(let details):
            return "Schedule time conflict: \(details)"
        case .scheduleNotFound(let id):
            return "Schedule not found: \(id)"
        case .subjectNotFound(let id):
            return "Subject not found: \(id)"
        case .semesterNotFound(let id):
            return "Semester not found: \(id)"
        case .operationTimeout:
            return "Operation timed out. Please try again."
        case .invalidState(let message):
            return "Invalid state: \(message)"
        case .coreDataError(let message):
            return "Database error: \(message)"
        case .noSemesterSelected:
            return "No semester selected. Please select a semester first."
        case .invalidTimeRange:
            return "End time must be after start time"
        }
    }

    var failureReason: String? {
        switch self {
        case .validationFailed:
            return "The provided data doesn't meet the required criteria"
        case .repositoryError:
            return "Failed to perform database operation"
        case .networkError:
            return "Network connection issue"
        case .userCancelled:
            return "User cancelled the operation"
        case .timeConflict:
            return "Schedule overlaps with existing schedule"
        case .scheduleNotFound:
            return "The requested schedule could not be found"
        case .subjectNotFound:
            return "The requested subject could not be found"
        case .semesterNotFound:
            return "The requested semester could not be found"
        case .operationTimeout:
            return "Operation took too long to complete"
        case .invalidState:
            return "Application is in an invalid state"
        case .coreDataError:
            return "Core Data operation failed"
        case .noSemesterSelected:
            return "A semester must be selected before managing schedules"
        case .invalidTimeRange:
            return "Invalid time range specified"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .validationFailed:
            return "Please check your input and try again"
        case .repositoryError, .coreDataError:
            return "Please restart the app and try again"
        case .networkError:
            return "Check your internet connection and retry"
        case .userCancelled:
            return "No action needed"
        case .timeConflict:
            return "Please choose a different time slot"
        case .scheduleNotFound, .subjectNotFound, .semesterNotFound:
            return "Refresh the list and try again"
        case .operationTimeout:
            return "Check your connection and try again"
        case .invalidState:
            return "Please restart the app"
        case .noSemesterSelected:
            return "Select a semester from the semester picker"
        case .invalidTimeRange:
            return "Ensure end time is after start time"
        }
    }
}

// MARK: - Loading State
enum ScheduleLoadingState {
    case idle
    case loading
    case success
    case failure(ScheduleViewModelError)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var error: ScheduleViewModelError? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

@MainActor
class ScheduleViewModel: ObservableObject {
    private var masterViewModel: MasterViewModel = MasterViewModel.shared

    // MARK: - Cache Properties (ADD THESE)
    private var scheduleCache: [String: [Schedule]] = [:]
    private var cacheTimestamps: [String: Date] = [:]
    private let cacheValidityDuration: TimeInterval = 300  // 5 minutes
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - Dependencies
    private let repository: ScheduleRepository
    private let logger = Logger(
        subsystem: "com.eda.app",
        category: "ScheduleViewModel"
    )

    // MARK: - Published Properties
    @Published var schedulesList: [Schedule] = []
    @Published var loadingState: ScheduleLoadingState = .idle
    @Published var isInitialized: Bool = false

    // MARK: - Info Alert Properties
    @Published var showInfoAlert: Bool = false
    @Published var infoAlertTitle: String = ""
    @Published var infoAlertMessage: String = ""

    // MARK: - Form Properties
    @Published var scheduleStartTime: Date = Date()
    @Published var scheduleEndTime: Date = Date().addingTimeInterval(3600)  // 1 hour later
    @Published var scheduleDay: String = "Monday"
    @Published var scheduleLocation: String = ""
    @Published var selectedSubject: Subject? = nil
    @Published var schedulesForSelectedDate: [Schedule] = []

    // MARK: - UI State
    @Published var presentScheduleCreateSheet: Bool = false
    @Published var presentScheduleEditSheet: Bool = false
    @Published var showErrorAlert: Bool = false
    @Published var showSuccessAlert: Bool = false
    @Published var alertTitle: String = ""
    @Published var alertMessage: String = ""
    @Published var showRetryOption: Bool = false

    // MARK: - Edit State
    @Published var editingSchedule: Schedule? = nil

    // MARK: - Additional State
    @Published var currentActiveSchedule: Schedule? = nil
    @Published var todaySchedules: [Schedule] = []
    @Published var selectedDate: Date = Date()
    @Published var availableSubjects: [Subject] = []

    // MARK: - Constants
    private let operationTimeout: TimeInterval = 30.0
    let availableDays: [String] = [
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
        "Sunday",
    ]

    // MARK: - Initialization
    init(repository: ScheduleRepository = ScheduleRepository()) {
        self.repository = repository
        self.logger.info("🚀 ScheduleViewModel initialized")
    }

    // MARK: - Initialization Method
    func initialize(with semester: Semester?) async {
        logger.info(
            "🚀 Initializing ScheduleViewModel with semester: \(semester?.semesterName ?? "nil")"
        )

        performCacheMaintenance()

        guard !isInitialized else {
            logger.debug("🔄 ScheduleViewModel already initialized")
            do {
                try await loadSchedules(for: selectedDate, semester: semester)
                await checkCurrentlyActiveSchedule(for: semester)
            } catch {
                print(
                    "Error from ScheduleViewModel, while calling initialize: \(error.localizedDescription)"
                )
            }
            return
        }

        loadingState = .loading

        do {
            try await loadSchedules(for: selectedDate, semester: semester)
            await checkCurrentlyActiveSchedule(for: semester)
            isInitialized = true
            loadingState = .success
            logger.info(
                "✅ ScheduleViewModel initialization completed successfully"
            )

        } catch {
            logger.error(
                "❌ ScheduleViewModel initialization failed: \(error.localizedDescription)"
            )
            await handleError(error, operation: "initialization")
        }
    }

    func loadSchedulesForScheduleView(for date: Date, semester: Semester?)
        async throws
    {
        if semester == nil {
            logger.warning(
                "⚠️loadSchedulesForScheduleView - Cannot load schedules: no semester selected"
            )
            loadingState = .failure(.noSemesterSelected)
            return
        }

        // Clear expired cache entries first
        clearExpiredCache()

        // Generate cache key
        let key = cacheKey(for: date, semester: semester)

        // Check cache first
        if let cachedSchedules = getCachedSchedules(for: key) {
            schedulesForSelectedDate = cachedSchedules
            loadingState = .success
            logger.info(
                "✅ loadSchedulesForScheduleView: Used cached data (\(cachedSchedules.count) schedules)"
            )
            return
        }

        // Cache miss - load from database
        logger.info(
            "📅 Loading schedules for date: \(date) in semester: \(semester!.semesterName ?? "unknown")"
        )
        loadingState = .loading

        do {
            let schedules = try await withTimeout(operationTimeout) {
                try await self.repository.getAllSchedules(
                    for: date,
                    semester: semester!
                )
            }

            // Cache the results
            cacheSchedules(schedules, for: key)

            // Update UI
            schedulesForSelectedDate = schedules
            loadingState = .success

            logger.info(
                "✅ loadSchedulesForScheduleView: Successfully loaded and cached \(schedules.count) schedules"
            )

        } catch {
            let wrappedError = await wrapError(
                error,
                context: "loading schedules"
            )
            loadingState = .failure(wrappedError)
            throw wrappedError
        }
    }

    // MARK: - Cache Management (ADD THIS ENTIRE SECTION)

    /// Creates a unique cache key for date and semester combination
    func cacheKey(for date: Date, semester: Semester?) -> String {
        let dateString = dateFormatter.string(from: date)
        let semesterName = semester?.semesterName ?? "no-semester"
        let semesterId = semester?.semesterId?.uuidString ?? "no-id"
        return "\(dateString)-\(semesterName)-\(semesterId)"
    }

    /// Checks if cached data is still valid (not expired)
    private func isCacheValid(for key: String) -> Bool {
        guard let timestamp = cacheTimestamps[key] else { return false }
        return Date().timeIntervalSince(timestamp) < cacheValidityDuration
    }

    /// Stores schedules in cache with current timestamp
    private func cacheSchedules(_ schedules: [Schedule], for key: String) {
        scheduleCache[key] = schedules
        cacheTimestamps[key] = Date()
        logger.debug("📋 Cached \(schedules.count) schedules for key: \(key)")
    }

    /// Retrieves cached schedules if available and valid
    private func getCachedSchedules(for key: String) -> [Schedule]? {
        guard isCacheValid(for: key), let schedules = scheduleCache[key] else {
            return nil
        }
        logger.debug(
            "📋 Using cached schedules for key: \(key) (\(schedules.count) items)"
        )
        return schedules
    }

    /// Invalidates cache for a specific key
    func invalidateCache(for key: String) {
        scheduleCache.removeValue(forKey: key)
        cacheTimestamps.removeValue(forKey: key)
        logger.debug("🗑️ Invalidated cache for key: \(key)")
    }

    /// Clears expired cache entries
    private func clearExpiredCache() {
        let now = Date()
        let expiredKeys = cacheTimestamps.compactMap { key, timestamp in
            now.timeIntervalSince(timestamp) > cacheValidityDuration ? key : nil
        }

        for key in expiredKeys {
            scheduleCache.removeValue(forKey: key)
            cacheTimestamps.removeValue(forKey: key)
        }

        if !expiredKeys.isEmpty {
            logger.debug("🧹 Cleared \(expiredKeys.count) expired cache entries")
        }
    }

    // MARK: - Core Operations
    func loadSchedules(for date: Date, semester: Semester?) async throws {
        if semester == nil {
            logger.warning(
                "⚠️loadSchedules: Cannot load schedules: no semester selected"
            )
            loadingState = .failure(.noSemesterSelected)
            return
        }

        // Clear expired cache entries first
        clearExpiredCache()

        // Generate cache key
        let key = cacheKey(for: date, semester: semester)

        // Check cache first
        if let cachedSchedules = getCachedSchedules(for: key) {
            schedulesList = cachedSchedules

            // Update today's schedules if selected date is today
            if Calendar.current.isDateInToday(date) {
                todaySchedules = cachedSchedules
            } else {
                todaySchedules = []
            }

            loadingState = .success
            logger.info(
                "✅ loadSchedules: Used cached data (\(cachedSchedules.count) schedules)"
            )
            return
        }

        // Cache miss - load from database
        logger.info(
            "📅 Loading schedules for date: \(date) in semester: \(semester!.semesterName ?? "unknown")"
        )
        loadingState = .loading

        do {
            let schedules = try await withTimeout(operationTimeout) {
                try await self.repository.getAllSchedules(
                    for: date,
                    semester: semester!
                )
            }

            // Cache the results
            cacheSchedules(schedules, for: key)

            // Update UI
            schedulesList = schedules

            // Update today's schedules if selected date is today
            if Calendar.current.isDateInToday(date) {
                todaySchedules = schedules
            } else {
                todaySchedules = []
            }

            loadingState = .success
            logger.info(
                "✅ loadSchedules: Successfully loaded and cached \(schedules.count) schedules"
            )

        } catch {
            let wrappedError = await wrapError(
                error,
                context: "loading schedules"
            )
            loadingState = .failure(wrappedError)
            throw wrappedError
        }
    }

    func createSchedule(semester: Semester?) async throws -> Schedule {
        if semester == nil {
            let error = ScheduleViewModelError.noSemesterSelected
            await handleError(error, operation: "create schedule")
            throw error
        }

        guard let subject = selectedSubject else {
            let error = ScheduleViewModelError.validationFailed(
                "Please select a subject"
            )
            await handleError(error, operation: "create schedule")
            throw error
        }

        logger.info(
            "💾 Creating schedule for subject: \(subject.subjectName ?? "unknown")"
        )
        loadingState = .loading

        do {
            // Validate input
            try await validateScheduleData()

            // Check for time conflicts
            let hasConflict = try await withTimeout(operationTimeout) {
                try await self.repository.checkForTimeConflict(
                    scheduleData: ScheduleData(
                        startTime: self.scheduleStartTime,
                        endTime: self.scheduleEndTime,
                        day: self.scheduleDay,
                        location: self.scheduleLocation.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                    ),
                    in: semester!
                )
            }

            if hasConflict {
                let error = ScheduleViewModelError.timeConflict(
                    "This time slot conflicts with an existing schedule"
                )
                await handleError(error, operation: "create schedule")
                throw error
            }

            // Create schedule data
            let scheduleData = ScheduleData(
                startTime: scheduleStartTime,
                endTime: scheduleEndTime,
                day: scheduleDay,
                location: scheduleLocation.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            )

            // Create schedule
            let newSchedule = try await withTimeout(operationTimeout) {
                try await self.repository.createSchedule(
                    scheduleData: scheduleData,
                    for: subject
                )
            }

            // Invalidate cache for the new schedule's date
            let scheduleDate = getDateFromSchedule(newSchedule)
            let cacheKeyToInvalidate = cacheKey(
                for: scheduleDate,
                semester: semester
            )
            invalidateCache(for: cacheKeyToInvalidate)

            // Also invalidate cache for selected date if different
            if !Calendar.current.isDate(scheduleDate, inSameDayAs: selectedDate)
            {
                let selectedDateKey = cacheKey(
                    for: selectedDate,
                    semester: semester
                )
                invalidateCache(for: selectedDateKey)
            }

            // Update local state if the new schedule is for the selected date
            if isScheduleOnDate(newSchedule, date: selectedDate) {
                schedulesList.append(newSchedule)
                schedulesList.sort {
                    ($0.scheduleStartTime ?? Date())
                        < ($1.scheduleStartTime ?? Date())
                }

                // Update today's schedules if needed
                if Calendar.current.isDateInToday(selectedDate) {
                    todaySchedules = schedulesList
                }
            }

            await checkCurrentlyActiveSchedule(for: semester)

            clearForm()
            presentScheduleCreateSheet = false
            loadingState = .success

            //            await MainActor.run {
            //                self.showInfoAlert = true
            //                self.infoAlertTitle = "Schedule Added"
            //                self.infoAlertMessage = "Schedule for \(subject.subjectName ?? "Untitled Subject") on \(formattedSelectedDate) has been added successfully."
            //            }

            self.masterViewModel.showAlert = true
            self.masterViewModel.alertTitle = "Schedule Added"
            self.masterViewModel.alertMessage =
                "Schedule for \(subject.subjectName?.lowercased() ?? "Untitled Subject") on \(formattedSelectedDate) has been added successfully."

            logger.info("✅ Schedule created successfully")
            return newSchedule

        } catch {
            let wrappedError = await wrapError(
                error,
                context: "creating schedule"
            )
            await handleError(wrappedError, operation: "create schedule")
            throw wrappedError
        }
    }

    func updateSchedule(semester: Semester?) async throws -> Schedule {
        if semester == nil {
            let error = ScheduleViewModelError.noSemesterSelected
            await handleError(error, operation: "update schedule")
            throw error
        }

        guard let editingSchedule = editingSchedule,
            let scheduleId = editingSchedule.scheduleId
        else {
            let error = ScheduleViewModelError.scheduleNotFound(
                "No schedule selected for editing"
            )
            await handleError(error, operation: "update schedule")
            throw error
        }

        guard let subject = selectedSubject else {
            let error = ScheduleViewModelError.validationFailed(
                "Please select a subject"
            )
            await handleError(error, operation: "update schedule")
            throw error
        }

        logger.info("📝 Updating schedule: \(scheduleId.uuidString)")
        loadingState = .loading

        do {
            // Validate input
            try await validateScheduleData()

            // Check for time conflicts (excluding current schedule)
            let hasConflict = try await withTimeout(operationTimeout) {
                try await self.repository.checkForTimeConflict(
                    scheduleData: ScheduleData(
                        startTime: self.scheduleStartTime,
                        endTime: self.scheduleEndTime,
                        day: self.scheduleDay,
                        location: self.scheduleLocation.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                    ),
                    in: semester!,
                    excluding: scheduleId
                )
            }

            if hasConflict {
                let error = ScheduleViewModelError.timeConflict(
                    "This time slot conflicts with an existing schedule"
                )
                await handleError(error, operation: "update schedule")
                throw error
            }

            // Create schedule data
            let scheduleData = ScheduleData(
                startTime: scheduleStartTime,
                endTime: scheduleEndTime,
                day: scheduleDay,
                location: scheduleLocation.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            )

            // Update schedule
            let updatedSchedule = try await withTimeout(operationTimeout) {
                try await self.repository.updateSchedule(
                    scheduleId: scheduleId,
                    scheduleData: scheduleData,
                    for: subject
                )
            }

            // Invalidate cache for both old and new schedule dates
            let oldScheduleDate = getDateFromSchedule(editingSchedule)
            let newScheduleDate = getDateFromSchedule(updatedSchedule)
            invalidateCache(
                for: cacheKey(for: oldScheduleDate, semester: semester)
            )
            invalidateCache(
                for: cacheKey(for: newScheduleDate, semester: semester)
            )

            // Also invalidate selected date cache if different
            let selectedDateKey = cacheKey(
                for: selectedDate,
                semester: semester
            )
            invalidateCache(for: selectedDateKey)

            // Update local state
            if let index = schedulesList.firstIndex(where: {
                $0.scheduleId == scheduleId
            }) {
                if isScheduleOnDate(updatedSchedule, date: selectedDate) {
                    schedulesList[index] = updatedSchedule
                    schedulesList.sort {
                        ($0.scheduleStartTime ?? Date())
                            < ($1.scheduleStartTime ?? Date())
                    }
                } else {
                    // Schedule moved to different day, remove from current list
                    schedulesList.remove(at: index)
                }

                // Update today's schedules if needed
                if Calendar.current.isDateInToday(selectedDate) {
                    todaySchedules = schedulesList
                }
            }
            // Clear form and close sheet
            clearForm()
            clearEditingState()
            presentScheduleEditSheet = false
            loadingState = .success

            await showSuccess(
                title: "Schedule Updated",
                message: "Schedule has been updated successfully!"
            )

            logger.info("✅ Schedule updated successfully")
            return updatedSchedule

        } catch {
            let wrappedError = await wrapError(
                error,
                context: "updating schedule"
            )
            await handleError(wrappedError, operation: "update schedule")
            throw wrappedError
        }
    }

    func deleteSchedule(_ schedule: Schedule) async throws {
        guard let scheduleId = schedule.scheduleId else {
            let error = ScheduleViewModelError.scheduleNotFound(
                "Invalid schedule ID"
            )
            await handleError(error, operation: "delete schedule")
            throw error
        }

        logger.info("🗑️ Deleting schedule: \(scheduleId.uuidString)")
        loadingState = .loading

        do {
            try await withTimeout(operationTimeout) {
                try await self.repository.deleteSchedule(scheduleId: scheduleId)
            }

            // Invalidate cache for the deleted schedule's date
            let scheduleDate = getDateFromSchedule(schedule)
            let cacheKeyToInvalidate = cacheKey(
                for: scheduleDate,
                semester: nil
            )  // We don't have semester context here
            invalidateCache(for: cacheKeyToInvalidate)

            // Also invalidate selected date cache
            let selectedDateKey = cacheKey(for: selectedDate, semester: nil)
            invalidateCache(for: selectedDateKey)

            // Update local state
            schedulesList.removeAll { $0.scheduleId == scheduleId }

            // Update today's schedules if needed
            if Calendar.current.isDateInToday(selectedDate) {
                todaySchedules = schedulesList
            }

            // Clear editing state if this was the schedule being edited
            if editingSchedule?.scheduleId == scheduleId {
                clearEditingState()
            }

            // Clear current active schedule if it was deleted
            if currentActiveSchedule?.scheduleId == scheduleId {
                currentActiveSchedule = nil
            }

            loadingState = .success

            await showSuccess(
                title: "Schedule Deleted",
                message: "Schedule has been deleted successfully."
            )

            logger.info("✅ Schedule deleted successfully")

        } catch {
            let wrappedError = await wrapError(
                error,
                context: "deleting schedule"
            )
            await handleError(wrappedError, operation: "delete schedule")
            throw wrappedError
        }
    }

    func refreshData(semester: Semester?) async {
        logger.info("🔄 Refreshing schedule data...")
        loadingState = .loading

        do {
            try await loadSchedules(for: selectedDate, semester: semester)
            await checkCurrentlyActiveSchedule(for: semester)
            loadingState = .success
            await showSuccess(
                title: "Data Refreshed",
                message: "Schedule data has been updated."
            )
        } catch {
            logger.error(
                "❌ Failed to refresh data: \(error.localizedDescription)"
            )
            await handleError(error, operation: "refresh data", showRetry: true)
        }
    }

    // MARK: - Active Schedule Management
    func checkCurrentlyActiveSchedule(for semester: Semester?) async {
        guard let semester = semester else {
            currentActiveSchedule = nil
            return
        }

        do {
            currentActiveSchedule =
                try await repository.getCurrentlyActiveSchedule(for: semester)
            logger.info(
                "📍 Current active schedule: \(self.currentActiveSchedule?.subject?.subjectName ?? "none")"
            )
        } catch {
            logger.error(
                "❌ Failed to check active schedule: \(error.localizedDescription)"
            )
            currentActiveSchedule = nil
        }
    }

    // MARK: - Edit Management
    func startEditing(_ schedule: Schedule) {
        logger.info(
            "✏️ Starting to edit schedule: \(schedule.scheduleId?.uuidString ?? "unknown")"
        )
        editingSchedule = schedule
        // Populate form with current values
        scheduleStartTime = schedule.scheduleStartTime ?? Date()
        scheduleEndTime =
            schedule.scheduleEndTime ?? Date().addingTimeInterval(3600)
        scheduleDay = schedule.scheduleDay ?? "Monday"
        scheduleLocation = schedule.scheduleLocation ?? ""
        selectedSubject = schedule.subject

        presentScheduleEditSheet = true
    }

    func cancelEditing() {
        logger.info("❌ Cancelling schedule editing")
        clearForm()
        clearEditingState()
        presentScheduleEditSheet = false
    }

    private func clearEditingState() {
        editingSchedule = nil
    }

    // MARK: - Validation Methods
    private func validateScheduleData() async throws {
        logger.debug("🔍 Validating schedule data...")

        let trimmedLocation = scheduleLocation.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard scheduleEndTime > scheduleStartTime else {
            throw ScheduleViewModelError.invalidTimeRange
        }

        guard !trimmedLocation.isEmpty else {
            throw ScheduleViewModelError.validationFailed(
                "Location cannot be empty"
            )
        }

        guard trimmedLocation.count >= 2 else {
            throw ScheduleViewModelError.validationFailed(
                "Location must be at least 2 characters long"
            )
        }

        guard trimmedLocation.count <= 100 else {
            throw ScheduleViewModelError.validationFailed(
                "Location cannot exceed 100 characters"
            )
        }

        guard availableDays.contains(scheduleDay) else {
            throw ScheduleViewModelError.validationFailed(
                "Please select a valid day"
            )
        }

        guard selectedSubject != nil else {
            throw ScheduleViewModelError.validationFailed(
                "Please select a subject"
            )
        }

        logger.debug("✅ Schedule data validation passed")
    }

    // MARK: - Error Handling
    private func wrapError(_ error: Error, context: String) async
        -> ScheduleViewModelError
    {
        if let scheduleError = error as? ScheduleViewModelError {
            return scheduleError
        }

        if let repositoryError = error as? ScheduleRepositoryError {
            switch repositoryError {
            case .scheduleNotFound(let details):
                return .scheduleNotFound(details)
            case .subjectNotFound(let details):
                return .subjectNotFound(details)
            case .semesterNotFound(let details):
                return .semesterNotFound(details)
            case .timeConflict(let details):
                return .timeConflict(details)
            case .invalidScheduleData(let details):
                return .validationFailed(details)
            case .coreDataError(let details):
                return .coreDataError(details)
            }
        }

        if error is CancellationError {
            return .userCancelled
        }

        if let nsError = error as NSError? {
            switch nsError.domain {
            case NSCocoaErrorDomain:
                return .coreDataError(
                    "Core Data error in \(context): \(nsError.localizedDescription)"
                )
            case NSURLErrorDomain:
                return .networkError(
                    "Network error in \(context): \(nsError.localizedDescription)"
                )
            default:
                return .repositoryError(
                    "Repository error in \(context): \(nsError.localizedDescription)"
                )
            }
        }

        return .repositoryError(
            "Unknown error in \(context): \(error.localizedDescription)"
        )
    }

    private func handleError(
        _ error: Error,
        operation: String,
        showRetry: Bool = false
    ) async {
        let wrappedError = await wrapError(error, context: operation)

        logger.error(
            "❌ Error in \(operation): \(wrappedError.localizedDescription)"
        )

        alertTitle = "Oops, we got stuck!"
        alertMessage = wrappedError.localizedDescription
        showRetryOption = showRetry
        showErrorAlert = true
        loadingState = .failure(wrappedError)
    }

    private func showSuccess(title: String, message: String) async {
        alertTitle = title
        alertMessage = message
        showSuccessAlert = true
    }

    // MARK: - Timeout Handling
    private func withTimeout<T>(
        _ timeout: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(
                    nanoseconds: UInt64(timeout * 1_000_000_000)
                )
                throw ScheduleViewModelError.operationTimeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - Utility Methods

    func performCacheMaintenance() {
        clearExpiredCache()

        // If cache gets too large, clear oldest entries
        if scheduleCache.count > 50 {
            let sortedByTime = cacheTimestamps.sorted { $0.value < $1.value }
            let keysToRemove = Array(sortedByTime.prefix(20).map { $0.key })

            for key in keysToRemove {
                scheduleCache.removeValue(forKey: key)
                cacheTimestamps.removeValue(forKey: key)
            }

            logger.debug("🧹 Removed \(keysToRemove.count) oldest cache entries")
        }
    }

    /// Extracts the date that corresponds to a schedule based on its day
    private func getDateFromSchedule(_ schedule: Schedule) -> Date {
        guard let scheduleDay = schedule.scheduleDay else {
            return selectedDate
        }

        // Find the most recent date that matches the schedule's day
        let calendar = Calendar.current
        let today = Date()

        // Get weekday number (1 = Sunday, 2 = Monday, etc.)
        let targetWeekday: Int
        switch scheduleDay {
        case "Sunday": targetWeekday = 1
        case "Monday": targetWeekday = 2
        case "Tuesday": targetWeekday = 3
        case "Wednesday": targetWeekday = 4
        case "Thursday": targetWeekday = 5
        case "Friday": targetWeekday = 6
        case "Saturday": targetWeekday = 7
        default: targetWeekday = calendar.component(.weekday, from: today)
        }

        // Find the date for this weekday in the current week
        var components = calendar.dateComponents(
            [.yearForWeekOfYear, .weekOfYear],
            from: today
        )
        components.weekday = targetWeekday

        return calendar.date(from: components) ?? today
    }
    func clearForm() {
        scheduleStartTime = Date()
        scheduleEndTime = Date().addingTimeInterval(3600)
        scheduleDay = "Monday"
        scheduleLocation = ""
        selectedSubject = nil
        logger.debug("🧹 Schedule form cleared")
    }

    func clearAlerts() {
        showErrorAlert = false
        showSuccessAlert = false
        alertTitle = ""
        alertMessage = ""
        showRetryOption = false
    }

    func changeSelectedDate(_ newDate: Date, semester: Semester?) async {
        selectedDate = newDate
        do {
            try await loadSchedules(for: newDate, semester: semester)
        } catch {
            logger.error(
                "❌ Failed to load schedules for new date: \(error.localizedDescription)"
            )
        }
    }

    private func isScheduleOnDate(_ schedule: Schedule, date: Date) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let dateDayName = formatter.string(from: date)
        return schedule.scheduleDay == dateDayName
    }

    // MARK: - Query Methods
    func getSchedule(by id: UUID) async throws -> Schedule? {
        return try await repository.getScheduleById(id)
    }

    func getSchedulesForSubject(_ subjectId: UUID) async throws -> [Schedule] {
        return try await repository.getAllSchedulesForSubject(subjectId)
    }

    func getSchedulesCount() -> Int {
        return schedulesList.count
    }

    func hasSchedules() -> Bool {
        return !schedulesList.isEmpty
    }

    func getSchedulesByDay(_ day: String) -> [Schedule] {
        return schedulesList.filter { $0.scheduleDay == day }
    }

    // MARK: - Computed Properties
    var isFormValid: Bool {
        let trimmedLocation = scheduleLocation.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return scheduleEndTime > scheduleStartTime && !trimmedLocation.isEmpty
            && trimmedLocation.count >= 2 && trimmedLocation.count <= 100
            && availableDays.contains(scheduleDay) && selectedSubject != nil
    }

    var canUpdateSchedule: Bool {
        isFormValid && !loadingState.isLoading && editingSchedule != nil
    }

    var isEditing: Bool {
        editingSchedule != nil
    }

    var hasActiveSchedule: Bool {
        currentActiveSchedule != nil
    }

    var formattedSelectedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: selectedDate)
    }

    var hasAvailableSubjects: Bool {
        !availableSubjects.isEmpty
    }

    var selectedSubjectName: String {
        selectedSubject?.subjectName ?? "No subject selected"
    }

    // MARK: - Deinitializer
    deinit {
        logger.info("🔄 ScheduleViewModel deinitialized")
    }
}
