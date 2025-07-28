//
//  BulkAttendanceViewModel.swift
//  eda
//
//  Simplified ViewModel for managing bulk attendance operations
//

import CoreData
import Foundation
import SwiftUI
import os.log

// MARK: - Custom Error Types
enum BulkAttendanceViewModelError: LocalizedError {
    case noSemesterSelected
    case noPendingSchedules
    case noSchedulesSelected
    case validationFailed(String)
    case repositoryError(String)
    case operationTimeout
    case invalidState(String)
    
    var errorDescription: String? {
        switch self {
        case .noSemesterSelected:
            return "No semester selected. Please select a semester first."
        case .noPendingSchedules:
            return "No pending schedules found for today."
        case .noSchedulesSelected:
            return "Please select at least one schedule to mark."
        case .validationFailed(let message):
            return "Validation Error: \(message)"
        case .repositoryError(let message):
            return "Data Error: \(message)"
        case .operationTimeout:
            return "Operation timed out. Please try again."
        case .invalidState(let message):
            return "Invalid state: \(message)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .noSemesterSelected:
            return "Select a semester from the semester picker"
        case .noPendingSchedules:
            return "All classes for today are already marked"
        case .noSchedulesSelected:
            return "Select one or more schedules to mark attendance"
        case .validationFailed:
            return "Please check your input and try again"
        case .repositoryError:
            return "Please restart the app and try again"
        case .operationTimeout:
            return "Check your connection and try again"
        case .invalidState:
            return "Please restart the app"
        }
    }
}

// MARK: - Loading State
enum BulkAttendanceLoadingState {
    case idle
    case loadingSchedules
    case submittingAttendance
    case success(BulkAttendanceResult)
    case failure(BulkAttendanceViewModelError)
    
    var isLoading: Bool {
        switch self {
        case .loadingSchedules, .submittingAttendance:
            return true
        default:
            return false
        }
    }
    
    var error: BulkAttendanceViewModelError? {
        if case .failure(let error) = self { return error }
        return nil
    }
    
    var result: BulkAttendanceResult? {
        if case .success(let result) = self { return result }
        return nil
    }
}

// MARK: - Schedule Selection Item
struct ScheduleSelectionItem: Identifiable {
    let schedule: Schedule
    var attendanceStatus: AttendanceStatus = .notMarked
    var canMark: Bool // Based on timing or other business rules
    
    var id: UUID { schedule.scheduleId ?? UUID() }
    
    enum AttendanceStatus {
        case notMarked
        case present
        case absent
        
        var displayText: String {
            switch self {
            case .notMarked: return "Not Marked"
            case .present: return "Present"
            case .absent: return "Absent"
            }
        }
        
        var attendanceValue: String {
            switch self {
            case .notMarked: return "Present" // Default to present
            case .present: return "Present"
            case .absent: return "Absent"
            }
        }
    }
}

@MainActor
class BulkAttendanceViewModel: ObservableObject {
    
    // MARK: - Dependencies
    private let repository: AttendanceRepository
    private let logger = Logger(
        subsystem: "com.eda.app",
        category: "BulkAttendanceViewModel"
    )
    
    // MARK: - Published Properties
    @Published var scheduleItems: [ScheduleSelectionItem] = []
    @Published var loadingState: BulkAttendanceLoadingState = .idle
    @Published var isInitialized: Bool = false
    
    // MARK: - Selection State
    @Published var selectedItems: Set<UUID> = []
    
    // MARK: - UI State
    @Published var showErrorAlert: Bool = false
    @Published var showSuccessAlert: Bool = false
    @Published var alertTitle: String = ""
    @Published var alertMessage: String = ""
    @Published var showRetryOption: Bool = false
    @Published var presentBulkAttendanceSheet: Bool = false
    
    // MARK: - Current Context
    @Published var currentSemester: Semester?
    @Published var lastRefreshDate: Date?
    
    // MARK: - Constants
    private let operationTimeout: TimeInterval = 30.0
    
    // MARK: - Initialization
    init(repository: AttendanceRepository = AttendanceRepository()) {
        self.repository = repository
        self.logger.info("🚀 BulkAttendanceViewModel initialized")
    }
    
    // MARK: - Core Operations
    
    /// Initializes the view model with pending schedules for the given semester
    func initialize(with semester: Semester?) async {
        logger.info("🚀 Initializing BulkAttendanceViewModel with semester: \(semester?.semesterName ?? "nil")")
        
        guard let semester = semester else {
            loadingState = .failure(.noSemesterSelected)
            return
        }
        
        currentSemester = semester
        loadingState = .loadingSchedules
        
        do {
            try await loadPendingSchedules(for: semester)
            isInitialized = true
            loadingState = .idle
            logger.info("✅ BulkAttendanceViewModel initialization completed successfully")
        } catch {
            logger.error("❌ BulkAttendanceViewModel initialization failed: \(error.localizedDescription)")
            await handleError(error, operation: "initialization")
        }
    }
    
    /// Loads pending schedules for today
    func loadPendingSchedules(for semester: Semester) async throws {
        logger.info("📅 Loading pending schedules for today")
        loadingState = .loadingSchedules
        
        do {
            let pendingSchedules = try await withTimeout(operationTimeout) {
                try await self.repository.getTodaysPendingSchedules(for: semester)
            }
            
            // Convert to selection items
            scheduleItems = pendingSchedules.map { schedule in
                ScheduleSelectionItem(
                    schedule: schedule,
                    canMark: canMarkAttendance(for: schedule)
                )
            }
            
            // Clear previous selections
            selectedItems.removeAll()
            lastRefreshDate = Date()
            
            logger.info("✅ Successfully loaded \(self.scheduleItems.count) pending schedules")
            
        } catch {
            let wrappedError = await wrapError(error, context: "loading pending schedules")
            loadingState = .failure(wrappedError)
            throw wrappedError
        }
    }
    
    /// Submits bulk attendance for selected schedules
    func submitBulkAttendance() async throws -> BulkAttendanceResult {
        logger.info("📝 Submitting bulk attendance for selected schedules")
        
        guard !selectedItems.isEmpty else {
            let error = BulkAttendanceViewModelError.noSchedulesSelected
            await handleError(error, operation: "submit bulk attendance")
            throw error
        }
        
        loadingState = .submittingAttendance
        
        do {
            // Prepare bulk requests
            let requests = createBulkRequests()
            
            // Submit to repository
            let result = try await withTimeout(operationTimeout) {
                try await self.repository.createBulkAttendance(requests)
            }
            
            // Update UI state
            updateItemsAfterSubmission(result: result)
            loadingState = .success(result)
            
            // Show appropriate alert
            await showResultAlert(for: result)
            
            logger.info("✅ Bulk attendance submitted: \(result.successCount) created, \(result.failureCount) failed")
            return result
            
        } catch {
            let wrappedError = await wrapError(error, context: "submitting bulk attendance")
            loadingState = .failure(wrappedError)
            await handleError(wrappedError, operation: "submit bulk attendance")
            throw wrappedError
        }
    }
    
    /// Refreshes the pending schedules data
    func refreshData() async {
        logger.info("🔄 Refreshing bulk attendance data")
        
        guard let semester = currentSemester else {
            logger.warning("⚠️ No current semester for refresh")
            return
        }
        
        do {
            try await loadPendingSchedules(for: semester)
            await showSuccess(
                title: "Data Refreshed",
                message: "Schedule data has been updated."
            )
        } catch {
            logger.error("❌ Failed to refresh data: \(error.localizedDescription)")
            await handleError(error, operation: "refresh data", showRetry: true)
        }
    }
    
    // MARK: - Selection Management
    
    /// Toggles selection for a specific schedule
    func toggleSelection(for scheduleId: UUID) {
        if selectedItems.contains(scheduleId) {
            selectedItems.remove(scheduleId)
        } else {
            selectedItems.insert(scheduleId)
        }
        logger.debug("🔄 Toggled selection for schedule. Total selected: \(self.selectedItems.count)")
    }
    
    /// Selects all markable schedules
    func selectAll() {
        selectedItems = Set(scheduleItems.filter { $0.canMark }.map { $0.id })
        logger.debug("✅ Selected all markable schedules: \(self.selectedItems.count)")
    }
    
    /// Clears all selections
    func clearAllSelections() {
        selectedItems.removeAll()
        logger.debug("🗑️ Cleared all selections")
    }
    
    /// Sets attendance status for all selected schedules (called during submit)
    func setAttendanceStatusForSelected(_ status: ScheduleSelectionItem.AttendanceStatus) {
        for scheduleId in selectedItems {
            if let index = scheduleItems.firstIndex(where: { $0.id == scheduleId }) {
                scheduleItems[index].attendanceStatus = status
            }
        }
        logger.debug("📝 Set attendance status to \(status.displayText) for \(self.selectedItems.count) schedules")
    }
    
    // MARK: - Private Helper Methods
    
    /// Creates bulk attendance requests from selected items
    private func createBulkRequests() -> [BulkAttendanceRequest] {
        return selectedItems.compactMap { scheduleId in
            guard let item = scheduleItems.first(where: { $0.id == scheduleId }) else {
                return nil
            }
            
            let attendanceData = AttendanceData(
                attendanceType: determineAttendanceType(for: item.schedule),
                attendancePresent: item.attendanceStatus.attendanceValue,
                attendanceEvent: "",
                attendanceDate: Date(),
                attendanceStartTime: item.schedule.scheduleStartTime ?? Date(),
                attendanceEndTime: item.schedule.scheduleEndTime ?? Date(),
                attendanceLocation: item.schedule.scheduleLocation
            )
            
            return BulkAttendanceRequest(
                schedule: item.schedule,
                attendanceData: attendanceData
            )
        }
    }
    
    /// Determines appropriate attendance type based on schedule
    private func determineAttendanceType(for schedule: Schedule) -> String {
        // You can add logic here to determine if it's Theory, Lab, etc.
        // For now, default to "Theory"
        return "Theory"
    }
    
    /// Checks if attendance can be marked for the given schedule
    private func canMarkAttendance(for schedule: Schedule) -> Bool {
        // Add business logic here:
        // - Check if it's within marking window
        // - Check if class has already started/ended
        // - Any other business rules
        
        // For now, allow marking for all schedules
        return true
    }
    
    /// Updates schedule items after successful submission
    private func updateItemsAfterSubmission(result: BulkAttendanceResult) {
        let successfulScheduleIds = Set(result.successfulCreations.compactMap { attendance in
            // Find the schedule that corresponds to this attendance
            scheduleItems.first { item in
                item.schedule.subject?.subjectId == attendance.subject?.subjectId &&
                Calendar.current.isDate(item.schedule.scheduleStartTime ?? Date(),
                                      equalTo: attendance.attendanceStartTime ?? Date(),
                                      toGranularity: .minute)
            }?.id
        })
        
        // Remove successfully processed items
        scheduleItems.removeAll { successfulScheduleIds.contains($0.id) }
        selectedItems.subtract(successfulScheduleIds)
        
        logger.debug("📊 Updated items after submission: \(self.scheduleItems.count) remaining")
    }
    
    /// Shows appropriate alert based on submission result
    private func showResultAlert(for result: BulkAttendanceResult) async {
        if result.isFullSuccess {
            await showSuccess(
                title: "Attendance Marked",
                message: "Successfully marked attendance for \(result.successCount) \(result.successCount == 1 ? "class" : "classes")."
            )
        } else if result.hasPartialSuccess {
            await showSuccess(
                title: "Partially Completed",
                message: "Marked \(result.successCount) classes successfully. \(result.failureCount) failed and \(result.skippedCount) were skipped."
            )
        } else {
            await showError(
                title: "Attendance Failed",
                message: "Could not mark attendance. Please try again.",
                showRetry: true
            )
        }
    }
    
    // MARK: - Error Handling
    
    private func wrapError(_ error: Error, context: String) async -> BulkAttendanceViewModelError {
        if let bulkError = error as? BulkAttendanceViewModelError {
            return bulkError
        }
        
        if let repoError = error as? AttendanceRepositoryError {
            switch repoError {
            case .attendanceNotFound, .subjectNotFound:
                return .repositoryError(repoError.localizedDescription)
            case .invalidAttendanceData(let details):
                return .validationFailed(details)
            case .coreDataError(let details):
                return .repositoryError(details)
            case .duplicateAttendance:
                return .repositoryError("Some attendance records already exist")
            }
        }
        
        if error is CancellationError {
            return .operationTimeout
        }
        
        return .repositoryError("Unknown error in \(context): \(error.localizedDescription)")
    }
    
    private func handleError(
        _ error: Error,
        operation: String,
        showRetry: Bool = false
    ) async {
        let wrappedError = await wrapError(error, context: operation)
        
        logger.error("❌ Error in \(operation): \(wrappedError.localizedDescription)")
        
        await showError(
            title: "Oops, we got stuck!",
            message: wrappedError.localizedDescription,
            showRetry: showRetry
        )
        
        loadingState = .failure(wrappedError)
    }
    
    private func showError(title: String, message: String, showRetry: Bool = false) async {
        alertTitle = title
        alertMessage = message
        showRetryOption = showRetry
        showErrorAlert = true
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
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw BulkAttendanceViewModelError.operationTimeout
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    // MARK: - Utility Methods
    
    func clearAlerts() {
        showErrorAlert = false
        showSuccessAlert = false
        alertTitle = ""
        alertMessage = ""
        showRetryOption = false
    }
    
    func retryLastOperation() async {
        logger.info("🔄 Retrying last operation...")
        
        guard let semester = currentSemester else {
            await handleError(BulkAttendanceViewModelError.noSemesterSelected, operation: "retry")
            return
        }
        
        await refreshData()
    }
}

// MARK: - Computed Properties

extension BulkAttendanceViewModel {
    
    var hasSchedules: Bool {
        !scheduleItems.isEmpty
    }
    
    var hasSelectedSchedules: Bool {
        !selectedItems.isEmpty
    }
    
    var selectedCount: Int {
        selectedItems.count
    }
    
    var totalSchedules: Int {
        scheduleItems.count
    }
    
    var markableSchedules: Int {
        scheduleItems.filter { $0.canMark }.count
    }
    
    var canSubmit: Bool {
        hasSelectedSchedules && !loadingState.isLoading
    }
    
    var canSelectAll: Bool {
        markableSchedules > 0 && selectedCount < markableSchedules
    }
    
    var selectionSummary: String {
        if selectedItems.isEmpty {
            return "No classes selected"
        } else if selectedItems.count == 1 {
            return "1 class selected"
        } else {
            return "\(selectedItems.count) classes selected"
        }
    }
    
    var formattedLastRefresh: String? {
        guard let lastRefresh = lastRefreshDate else { return nil }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "Last updated: \(formatter.string(from: lastRefresh))"
    }
}
