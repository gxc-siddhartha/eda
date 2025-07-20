import CoreData
import Foundation
import SwiftUI
import os.log

// MARK: - Custom Error Types
enum AttendanceViewModelError: LocalizedError {
    case validationFailed(String)
    case repositoryError(String)
    case networkError(String)
    case userCancelled
    case duplicateAttendance(String)
    case attendanceNotFound(String)
    case scheduleNotFound(String)
    case subjectNotFound(String)
    case operationTimeout
    case invalidState(String)
    case coreDataError(String)
    case noSubjectSelected
    case noScheduleSelected
    case invalidAttendanceData
    case invalidDate

    var errorDescription: String? {
        switch self {
        case .validationFailed(let message):
            return "\(message)"
        case .repositoryError(let message):
            return "\(message)"
        case .networkError(let message):
            return "\(message)"
        case .userCancelled:
            return "Operation was cancelled"
        case .duplicateAttendance(let details):
            return "\(details)"
        case .attendanceNotFound(let id):
            return "\(id)"
        case .scheduleNotFound(let id):
            return "\(id)"
        case .subjectNotFound(let id):
            return "\(id)"
        case .operationTimeout:
            return "Operation timed out. Please try again."
        case .invalidState(let message):
            return "Invalid state: \(message)"
        case .coreDataError(let message):
            return "Database error: \(message)"
        case .noSubjectSelected:
            return "No subject selected. Please select a subject first."
        case .noScheduleSelected:
            return "No schedule selected. Please select a schedule first."
        case .invalidAttendanceData:
            return "Invalid attendance data provided"
        case .invalidDate:
            return "Invalid attendance date selected"
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
        case .duplicateAttendance:
            return "Attendance already exists for this subject and time"
        case .attendanceNotFound:
            return "The requested attendance could not be found"
        case .scheduleNotFound:
            return "The requested schedule could not be found"
        case .subjectNotFound:
            return "The requested subject could not be found"
        case .operationTimeout:
            return "Operation took too long to complete"
        case .invalidState:
            return "Application is in an invalid state"
        case .coreDataError:
            return "Core Data operation failed"
        case .noSubjectSelected:
            return "A subject must be selected before managing attendance"
        case .noScheduleSelected:
            return "A schedule must be selected before creating attendance"
        case .invalidAttendanceData:
            return "Attendance data is invalid or incomplete"
        case .invalidDate:
            return "The selected date is invalid or outside allowed range"
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
        case .duplicateAttendance:
            return
                "Please choose a different time or update existing attendance"
        case .attendanceNotFound, .scheduleNotFound, .subjectNotFound:
            return "Refresh the list and try again"
        case .operationTimeout:
            return "Check your connection and try again"
        case .invalidState:
            return "Please restart the app"
        case .noSubjectSelected:
            return "Select a subject from the subject picker"
        case .noScheduleSelected:
            return "Select a schedule from the schedule picker"
        case .invalidAttendanceData:
            return "Ensure all required fields are filled correctly"
        case .invalidDate:
            return "Please select a valid date within the semester range"
        }
    }
}

// MARK: - Loading State
enum AttendanceLoadingState {
    case idle
    case loading
    case success
    case failure(AttendanceViewModelError)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var error: AttendanceViewModelError? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

@MainActor
class AttendanceViewModel: ObservableObject {

    private var masterViewModel: MasterViewModel = MasterViewModel.shared

    // MARK: - Dependencies
    private let repository: AttendanceRepository
    let logger = Logger(
        subsystem: "com.eda.app",
        category: "AttendanceViewModel"
    )

    // MARK: - Published Properties
    @Published var attendanceList: [Attendance] = []
    @Published var loadingState: AttendanceLoadingState = .idle
    @Published var isInitialized: Bool = false

    // MARK: - Cache Properties (ADD THESE)
    private var attendanceCache: [String: [Attendance]] = [:]
    private var attendanceCacheTimestamp: [String: Date] = [:]
    private let attendanceCacheValidityDuration: TimeInterval = 300  // 5 minutes (attendance changes frequently)
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - Form Properties
    @Published var attendanceType: String = ""
    @Published var attendancePresent: String = "Present"
    @Published var attendanceEvent: String = ""
    @Published var attendanceDate: Date = Date()
    @Published var selectedSchedule: Schedule? = nil {
        didSet {
            // Auto-populate timing and location when schedule changes
            if let schedule = selectedSchedule {
                attendanceStartTime = schedule.scheduleStartTime ?? Date()
                attendanceEndTime = schedule.scheduleEndTime ?? Date()
                attendanceLocation = schedule.scheduleLocation ?? ""
                logger.debug(
                    "✅ Auto-populated timing from schedule: \(schedule.scheduleDay ?? "Unknown")"
                )
            }
        }
    }

    // MARK: - New Form Properties for Timing
    @Published var attendanceStartTime: Date = Date()
    @Published var attendanceEndTime: Date = Date()
    @Published var attendanceLocation: String = ""

    // MARK: Schedules
    @Published var schedulesForSubject: [Schedule] = []

    // MARK: Info Alert Properties
    @Published var infoAlertForContentView: Bool = false
    @Published var infoAlertMessage: String = ""
    @Published var infoAlertTitle: String = ""

    // MARK: - UI State
    @Published var presentAttendanceCreateSheet: Bool = false
    @Published var presentAttendanceEditSheet: Bool = false
    @Published var showErrorAlert: Bool = false
    @Published var showSuccessAlert: Bool = false
    @Published var alertTitle: String = ""
    @Published var alertMessage: String = ""
    @Published var showRetryOption: Bool = false

    // MARK: - Edit State
    @Published var editingAttendance: Attendance? = nil

    // MARK: - Additional State
    @Published var attendanceForSelectedDate: [Attendance] = []
    @Published var attendanceForSelectedSubject: [Attendance] = []
    @Published var selectedDate: Date = Date()
    @Published var selectedSubject: Subject? = nil
    @Published var availableSchedules: [Schedule] = []

    @Published var weeklyChartData: WeeklyAttendanceChartData? = nil

    // MARK: - Constants
    private let operationTimeout: TimeInterval = 30.0
    let availableAttendanceTypes: [String] = [
        "Theory", "Lab", "Other",
    ]
    let availablePresenceStatus: [String] = [
        "Present", "Absent", "Medical Substitution",
    ]

    // MARK: - Initialization
    init(repository: AttendanceRepository = AttendanceRepository()) {
        self.repository = repository
        self.logger.info("🚀 AttendanceViewModel initialized")
    }

    // MARK: - Initialization Method
    func initialize(with subject: Subject?) async {
        logger.info(
            "🚀 Initializing AttendanceViewModel with subject: \(subject?.subjectName ?? "nil")"
        )

        performAttendanceCacheMaintenance()

        guard !isInitialized else {
            logger.debug("🔄 AttendanceViewModel already initialized")
            do {
                try await loadAttendanceForSubject(subject)
                try await loadAttendanceForDate(selectedDate, subject: subject)
            } catch {
                logger.error(
                    "❌ Error from AttendanceViewModel, while calling initialize: \(error.localizedDescription)"
                )
            }
            return
        }

        loadingState = .loading

        do {
            if let subject = subject {
                try await loadAttendanceForSubject(subject)
                try await loadAttendanceForDate(selectedDate, subject: subject)
            }
            isInitialized = true
            loadingState = .success
            logger.info(
                "✅ AttendanceViewModel initialization completed successfully"
            )

        } catch {
            logger.error(
                "❌ AttendanceViewModel initialization failed: \(error.localizedDescription)"
            )
            await handleError(error, operation: "initialization")
        }
    }

    // MARK: - Attendance Cache Management (ADD THIS ENTIRE SECTION)

    /// Creates a unique cache key for subject-based attendance
    private func attendanceCacheKey(for subject: Subject?) -> String {
        let subjectName = subject?.subjectName ?? "no-subject"
        let subjectId = subject?.subjectId?.uuidString ?? "no-id"
        let semesterId =
            subject?.semester?.semesterId?.uuidString ?? "no-semester"
        return "attendance-\(subjectName)-\(subjectId)-\(semesterId)"
    }

    /// Creates cache key for date-specific attendance
    private func attendanceDateCacheKey(for date: Date, subject: Subject?)
        -> String
    {
        let dateString = dateFormatter.string(from: date)
        let subjectId = subject?.subjectId?.uuidString ?? "no-id"
        return "attendance-date-\(dateString)-\(subjectId)"
    }

    /// Checks if cached data is still valid (not expired)
    private func isAttendanceCacheValid(for key: String) -> Bool {
        guard let timestamp = attendanceCacheTimestamp[key] else {
            return false
        }
        return Date().timeIntervalSince(timestamp)
            < attendanceCacheValidityDuration
    }

    /// Stores attendance in cache with current timestamp
    private func cacheAttendance(_ attendance: [Attendance], for key: String) {
        attendanceCache[key] = attendance
        attendanceCacheTimestamp[key] = Date()
        logger.debug(
            "📋 Cached \(attendance.count) attendance records for key: \(key)"
        )
    }

    /// Retrieves cached attendance if available and valid
    private func getCachedAttendance(for key: String) -> [Attendance]? {
        guard isAttendanceCacheValid(for: key),
            let attendance = attendanceCache[key]
        else {
            return nil
        }
        logger.debug(
            "📋 Using cached attendance for key: \(key) (\(attendance.count) items)"
        )
        return attendance
    }

    /// Invalidates cache for a specific key
    private func invalidateAttendanceCache(for key: String) {
        attendanceCache.removeValue(forKey: key)
        attendanceCacheTimestamp.removeValue(forKey: key)
        logger.debug("🗑️ Invalidated attendance cache for key: \(key)")
    }

    /// Invalidates all cache for a subject (useful when attendance changes)
    private func invalidateAllAttendanceCacheForSubject(_ subject: Subject?) {
        guard let subject = subject else { return }

        let subjectId = subject.subjectId?.uuidString ?? "no-id"
        let keysToRemove = attendanceCache.keys.filter {
            $0.contains(subjectId)
        }

        for key in keysToRemove {
            attendanceCache.removeValue(forKey: key)
            attendanceCacheTimestamp.removeValue(forKey: key)
        }

        logger.debug(
            "🗑️ Invalidated \(keysToRemove.count) attendance cache entries for subject: \(subject.subjectName ?? "unknown")"
        )
    }

    /// Clears expired cache entries
    private func clearExpiredAttendanceCache() {
        let now = Date()
        let expiredKeys = attendanceCacheTimestamp.compactMap {
            key,
            timestamp in
            now.timeIntervalSince(timestamp) > attendanceCacheValidityDuration
                ? key : nil
        }

        for key in expiredKeys {
            attendanceCache.removeValue(forKey: key)
            attendanceCacheTimestamp.removeValue(forKey: key)
        }

        if !expiredKeys.isEmpty {
            logger.debug(
                "🧹 Cleared \(expiredKeys.count) expired attendance cache entries"
            )
        }
    }

    /// Performs cache maintenance - call periodically
    private func performAttendanceCacheMaintenance() {
        clearExpiredAttendanceCache()

        // If cache gets too large, clear oldest entries
        if attendanceCache.count > 50 {
            let sortedByTime = attendanceCacheTimestamp.sorted {
                $0.value < $1.value
            }
            let keysToRemove = Array(sortedByTime.prefix(20).map { $0.key })

            for key in keysToRemove {
                attendanceCache.removeValue(forKey: key)
                attendanceCacheTimestamp.removeValue(forKey: key)
            }

            logger.debug(
                "🧹 Removed \(keysToRemove.count) oldest attendance cache entries"
            )
        }
    }

    // MARK: - Core Operations
    func loadAttendanceForSubject(_ subject: Subject?) async throws {
        guard let subject = subject else {
            logger.warning("⚠️ Cannot load attendance: no subject selected")
            loadingState = .failure(.noSubjectSelected)
            attendanceForSelectedSubject = []
            return
        }

        // Clear expired cache entries first
        clearExpiredAttendanceCache()

        // Generate cache key
        let key = attendanceCacheKey(for: subject)

        // Check cache first
        if let cachedAttendance = getCachedAttendance(for: key) {
            loadingState = .success

            self.attendanceForSelectedSubject = cachedAttendance

            updateWeeklyChartData()
            logger.info(
                "✅ loadAttendanceForSubject: Used cached data (\(cachedAttendance.count) records)"
            )
            return
        }

        // Cache miss - load from database
        logger.info(
            "📚 Loading attendance for subject: \(subject.subjectName ?? "unknown")"
        )
        loadingState = .loading

        do {
            let attendance = try await withTimeout(operationTimeout) {
                try await self.repository.getAllAttendance(for: subject)
            }

            // Cache the results
            cacheAttendance(attendance, for: key)

            // Update UI
            loadingState = .success

            self.attendanceForSelectedSubject = attendance

            updateWeeklyChartData()

            logger.info(
                "✅ loadAttendanceForSubject: Successfully loaded and cached \(attendance.count) attendance records"
            )

        } catch {
            let wrappedError = await wrapError(
                error,
                context: "loading attendance for subject"
            )
            loadingState = .failure(wrappedError)
            attendanceForSelectedSubject = []
            throw wrappedError
        }
    }

    func loadAttendanceForDate(_ date: Date, subject: Subject?) async throws {
        guard let subject = subject else {
            logger.warning(
                "⚠️ Cannot load attendance for date: no subject selected"
            )
            attendanceForSelectedDate = []
            return
        }

        // Clear expired cache entries first
        clearExpiredAttendanceCache()

        // Generate cache key for date-specific data
        let key = attendanceDateCacheKey(for: date, subject: subject)

        // Check cache first
        if let cachedAttendance = getCachedAttendance(for: key) {
            attendanceForSelectedDate = cachedAttendance
            logger.info(
                "✅ loadAttendanceForDate: Used cached data (\(cachedAttendance.count) records)"
            )
            return
        }

        // Cache miss - load from database
        logger.info(
            "📅 Loading attendance for date: \(date) and subject: \(subject.subjectName ?? "unknown")"
        )

        do {
            let attendance = try await withTimeout(operationTimeout) {
                try await self.repository.getAllAttendanceForDate(
                    date,
                    subject: subject
                )
            }

            // Cache the results
            cacheAttendance(attendance, for: key)

            // Update UI
            attendanceForSelectedDate = attendance

            logger.info(
                "✅ loadAttendanceForDate: Successfully loaded and cached \(attendance.count) attendance records for date"
            )

        } catch {
            let wrappedError = await wrapError(
                error,
                context: "loading attendance for date"
            )
            attendanceForSelectedDate = []
            throw wrappedError
        }
    }

    func createAttendance() async throws -> Attendance {
        guard let schedule = selectedSchedule else {
            let error = AttendanceViewModelError.noScheduleSelected
            await handleError(error, operation: "create attendance")
            throw error
        }

        guard let subject = schedule.subject else {
            let error = AttendanceViewModelError.noSubjectSelected
            await handleError(error, operation: "create attendance")
            throw error
        }

        // DEBUG: Log detailed information about what we're trying to create
        logger.info("🔍 DEBUG: Creating attendance with details:")
        logger.info("   Subject: \(subject.subjectName ?? "unknown")")
        logger.info("   Date: \(self.attendanceDate)")
        logger.info("   Start Time: \(self.attendanceStartTime)")
        logger.info("   End Time: \(self.attendanceEndTime)")
        logger.info("   Schedule Day: \(schedule.scheduleDay ?? "unknown")")
        logger.info(
            "   Schedule Start Time: \(schedule.scheduleStartTime ?? Date())"
        )

        logger.info(
            "💾 Creating attendance for subject: \(subject.subjectName ?? "unknown")"
        )
        loadingState = .loading

        do {
            // Validate input
            try await validateAttendanceData()

            // Create attendance data with timing information
            let attendanceData = AttendanceData(
                attendanceType: attendanceType.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
                attendancePresent: attendancePresent.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
                attendanceEvent: attendanceEvent.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
                attendanceDate: attendanceDate,
                attendanceStartTime: attendanceStartTime,
                attendanceEndTime: attendanceEndTime,
                attendanceLocation: attendanceLocation.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
                    ? nil
                    : attendanceLocation.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
            )

            // Create attendance with subject (not schedule)
            if try await validateAttendanceDate() == false {
                let wrappedError = await wrapError(
                    AttendanceViewModelError.invalidAttendanceData,
                    context: "create attendance"
                )
                throw wrappedError
            }

            let newAttendance = try await withTimeout(operationTimeout) {
                try await self.repository.createAttendance(
                    attendanceData: attendanceData,
                    for: subject
                )
            }

            // DEBUG: Log success
            logger.info(
                "✅ DEBUG: Attendance created successfully with ID: \(newAttendance.attendanceId?.uuidString ?? "unknown")"
            )

            // Invalidate cache for the subject (attendance data changed)
            invalidateAllAttendanceCacheForSubject(subject)

            // ✅ UPDATE LOCAL STATE DIRECTLY (MUCH FASTER)
            // Add to main subject list
            attendanceForSelectedSubject.append(newAttendance)
            attendanceForSelectedSubject.sort {
                ($0.attendanceDate ?? Date()) > ($1.attendanceDate ?? Date())
            }

            // ✅ Update date-specific array if this attendance is for the selected date
            if Calendar.current.isDate(
                newAttendance.attendanceDate ?? Date(),
                inSameDayAs: selectedDate
            ) {
                attendanceForSelectedDate.append(newAttendance)
                attendanceForSelectedDate.sort {
                    ($0.attendanceStartTime ?? Date())
                        < ($1.attendanceStartTime ?? Date())
                }
            }

            // ✅ Update chart data immediately
            updateWeeklyChartData()

            logger.debug(
                "✅ Added attendance to local state: \(newAttendance.attendanceId?.uuidString ?? "unknown")"
            )

            // Clear form and close sheet
            clearForm()
            presentAttendanceCreateSheet = false
            loadingState = .success

            self.masterViewModel.showAlert = true
            self.masterViewModel.alertTitle = "Attendance Created"
            self.masterViewModel.alertMessage =
                "Attendance for \(subject.subjectName?.lowercased() ?? "unknown subject".lowercased()) has been created, you can view it in the attendance page for that subject."

            logger.info("✅ Attendance created successfully")
            return newAttendance

        } catch {
            let wrappedError = await wrapError(
                error,
                context: "creating attendance"
            )
            let attendanceDateValid = try await validateAttendanceDate()
            attendanceDateValid
                ? await handleError(
                    wrappedError,
                    operation: "create attendance"
                ) : ()
            throw wrappedError
        }
    }

    func updateAttendance() async throws -> Attendance {
        guard let editingAttendance = editingAttendance,
            let attendanceId = editingAttendance.attendanceId
        else {
            let error = AttendanceViewModelError.attendanceNotFound(
                "No attendance selected for editing"
            )
            await handleError(error, operation: "update attendance")
            throw error
        }

        logger.info("📝 Updating attendance: \(attendanceId.uuidString)")
        loadingState = .loading

        do {
            // Validate input
            try await validateAttendanceDataForEditing()

            // Create attendance data with timing information
            let attendanceData = AttendanceData(
                attendanceType: attendanceType.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
                attendancePresent: attendancePresent.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
                attendanceEvent: attendanceEvent.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
                attendanceDate: attendanceDate,
                attendanceStartTime: attendanceStartTime,
                attendanceEndTime: attendanceEndTime,
                attendanceLocation: attendanceLocation.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
                    ? nil
                    : attendanceLocation.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
            )

            // Update attendance
            let updatedAttendance = try await withTimeout(operationTimeout) {
                try await self.repository.updateAttendance(
                    attendanceId: attendanceId,
                    attendanceData: attendanceData
                )
            }

            // Invalidate cache for the subject (attendance data changed)
            if let subject = selectedSubject {
                invalidateAllAttendanceCacheForSubject(subject)
            }

            // ✅ UPDATE LOCAL STATE DIRECTLY (MUCH FASTER)
            // Update in main subject list
            if let index = attendanceForSelectedSubject.firstIndex(where: {
                $0.attendanceId == attendanceId
            }) {
                attendanceForSelectedSubject[index] = updatedAttendance
                attendanceForSelectedSubject.sort {
                    ($0.attendanceDate ?? Date())
                        > ($1.attendanceDate ?? Date())
                }
                logger.debug(
                    "✅ Updated attendance in subject list at index \(index)"
                )
            }

            // ✅ Update in date-specific array
            if let dateIndex = attendanceForSelectedDate.firstIndex(where: {
                $0.attendanceId == attendanceId
            }) {
                // Check if updated attendance is still for the selected date
                if Calendar.current.isDate(
                    updatedAttendance.attendanceDate ?? Date(),
                    inSameDayAs: selectedDate
                ) {
                    attendanceForSelectedDate[dateIndex] = updatedAttendance
                    attendanceForSelectedDate.sort {
                        ($0.attendanceStartTime ?? Date())
                            < ($1.attendanceStartTime ?? Date())
                    }
                    logger.debug(
                        "✅ Updated attendance in date list at index \(dateIndex)"
                    )
                } else {
                    // Attendance moved to different date, remove from current date array
                    attendanceForSelectedDate.remove(at: dateIndex)
                    logger.debug(
                        "✅ Removed attendance from date list (moved to different date)"
                    )
                }
            } else if Calendar.current.isDate(
                updatedAttendance.attendanceDate ?? Date(),
                inSameDayAs: selectedDate
            ) {
                // Attendance was moved TO the selected date, add it
                attendanceForSelectedDate.append(updatedAttendance)
                attendanceForSelectedDate.sort {
                    ($0.attendanceStartTime ?? Date())
                        < ($1.attendanceStartTime ?? Date())
                }
                logger.debug(
                    "✅ Added attendance to date list (moved from different date)"
                )
            }

            // ✅ Update chart data immediately
            updateWeeklyChartData()

            logger.debug(
                "✅ Updated attendance in local state: \(updatedAttendance.attendanceId?.uuidString ?? "unknown")"
            )

            loadingState = .success

            self.presentAttendanceCreateSheet = false

            // Clear form and close sheet
            clearForm()
            clearEditingState()

            logger.info("✅ Attendance updated successfully")
            return updatedAttendance

        } catch {
            let wrappedError = await wrapError(
                error,
                context: "updating attendance"
            )
            await handleError(wrappedError, operation: "update attendance")
            throw wrappedError
        }
    }

    func deleteAttendance(_ attendance: Attendance) async throws {
        guard let attendanceId = attendance.attendanceId else {
            let error = AttendanceViewModelError.attendanceNotFound(
                "Invalid attendance ID"
            )
            await handleError(error, operation: "delete attendance")
            throw error
        }

        logger.info("🗑️ Deleting attendance: \(attendanceId.uuidString)")
        loadingState = .loading

        do {
            try await withTimeout(operationTimeout) {
                try await self.repository.deleteAttendance(
                    attendanceId: attendanceId
                )
            }

            // Invalidate cache for the subject (attendance data changed)
            if let subject = selectedSubject {
                invalidateAllAttendanceCacheForSubject(subject)
            }

            // ✅ UPDATE LOCAL STATE DIRECTLY (MUCH FASTER)
            // Remove from main subject list
            attendanceForSelectedSubject.removeAll {
                $0.attendanceId == attendanceId
            }

            // Remove from date-specific array
            attendanceForSelectedDate.removeAll {
                $0.attendanceId == attendanceId
            }
            // ✅ Update chart data immediately
            updateWeeklyChartData()

            logger.debug(
                "✅ Deleted attendance from local state: \(attendanceId.uuidString)"
            )

            // Clear editing state if this was the attendance being edited
            if editingAttendance?.attendanceId == attendanceId {
                clearEditingState()
            }

            loadingState = .success

            await showSuccess(
                title: "Attendance Deleted",
                message: "Attendance has been deleted successfully."
            )

            logger.info("✅ Attendance deleted successfully")

        } catch {
            let wrappedError = await wrapError(
                error,
                context: "deleting attendance"
            )
            await handleError(wrappedError, operation: "delete attendance")
            throw wrappedError
        }
    }

    func refreshData() async {
        logger.info("🔄 Refreshing attendance data...")
        loadingState = .loading

        // Clear all cache to force fresh data
        attendanceCache.removeAll()
        attendanceCacheTimestamp.removeAll()

        await refreshAttendanceData()
        loadingState = .success
        await showSuccess(
            title: "Data Refreshed",
            message: "Attendance data has been updated."
        )
    }

    private func refreshAttendanceData() async {
        do {
            if let subject = selectedSubject {
                // Clear cache to force fresh data (used only for manual refresh)
                let key = attendanceCacheKey(for: subject)
                invalidateAttendanceCache(for: key)

                // Load fresh data
                try await loadAttendanceForSubject(subject)

                // Update date-specific data if needed
                try await loadAttendanceForDate(selectedDate, subject: subject)
            }
            // Update chart data after refreshing
            updateWeeklyChartData()
        } catch {
            logger.error(
                "❌ Failed to refresh attendance data: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Edit Management
    func startEditing(_ attendance: Attendance) {
        loadingState = .success
        logger.info(
            "✏️ Starting to edit attendance: \(attendance.attendanceId?.uuidString ?? "unknown")"
        )
        editingAttendance = attendance

        // Populate form with current values
        attendanceType = attendance.attendanceType ?? ""
        attendancePresent = attendance.attendancePresence ?? "Present"
        attendanceEvent = attendance.attendanceEvent ?? ""
        attendanceDate = attendance.attendanceDate ?? Date()
        attendanceStartTime = attendance.attendanceStartTime ?? Date()
        attendanceEndTime = attendance.attendanceEndTime ?? Date()
        attendanceLocation = attendance.attendanceLocation ?? ""

        // Note: We don't set selectedSchedule since attendance is now independent
        // Users can manually adjust timing if needed

        presentAttendanceEditSheet = true
    }

    func cancelEditing() {
        logger.info("❌ Cancelling attendance editing")
        clearForm()
        clearEditingState()
        presentAttendanceEditSheet = false
    }

    private func clearEditingState() {
        editingAttendance = nil
    }

    // MARK: - Validation Methods
    private func validateAttendanceData() async throws {
        logger.debug("🔍 Validating attendance data...")

        let trimmedType = attendanceType.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let trimmedPresent = attendancePresent.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let trimmedEvent = attendanceEvent.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let trimmedLocation = attendanceLocation.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmedType.isEmpty else {
            throw AttendanceViewModelError.validationFailed(
                "Attendance type cannot be empty"
            )
        }

        guard !trimmedPresent.isEmpty else {
            throw AttendanceViewModelError.validationFailed(
                "Attendance presence status cannot be empty"
            )
        }

        guard trimmedType.count <= 50 else {
            throw AttendanceViewModelError.validationFailed(
                "Attendance type cannot exceed 50 characters"
            )
        }

        guard trimmedEvent.count <= 100 else {
            throw AttendanceViewModelError.validationFailed(
                "Attendance event cannot exceed 100 characters"
            )
        }

        guard trimmedLocation.count <= 100 else {
            throw AttendanceViewModelError.validationFailed(
                "Attendance location cannot exceed 100 characters"
            )
        }

        guard availablePresenceStatus.contains(trimmedPresent) else {
            throw AttendanceViewModelError.validationFailed(
                "Please select a valid presence status"
            )
        }

        guard selectedSchedule != nil else {
            throw AttendanceViewModelError.validationFailed(
                "Please select a schedule"
            )
        }

        // Validate timing
        guard attendanceStartTime < attendanceEndTime else {
            throw AttendanceViewModelError.validationFailed(
                "End time must be after start time"
            )
        }

        // Validate attendance date
        guard try await validateAttendanceDate() else {
            throw AttendanceViewModelError.invalidDate
        }

        logger.debug("✅ Attendance data validation passed")
    }

    private func validateAttendanceDataForEditing() async throws {
        logger.debug("🔍 Validating attendance data...")

        let trimmedType = attendanceType.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let trimmedPresent = attendancePresent.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let trimmedEvent = attendanceEvent.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let trimmedLocation = attendanceLocation.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmedType.isEmpty else {
            throw AttendanceViewModelError.validationFailed(
                "Attendance type cannot be empty"
            )
        }

        guard !trimmedPresent.isEmpty else {
            throw AttendanceViewModelError.validationFailed(
                "Attendance presence status cannot be empty"
            )
        }

        guard trimmedType.count <= 50 else {
            throw AttendanceViewModelError.validationFailed(
                "Attendance type cannot exceed 50 characters"
            )
        }

        guard trimmedEvent.count <= 100 else {
            throw AttendanceViewModelError.validationFailed(
                "Attendance event cannot exceed 100 characters"
            )
        }

        guard trimmedLocation.count <= 100 else {
            throw AttendanceViewModelError.validationFailed(
                "Attendance location cannot exceed 100 characters"
            )
        }

        guard availablePresenceStatus.contains(trimmedPresent) else {
            throw AttendanceViewModelError.validationFailed(
                "Please select a valid presence status"
            )
        }

        // Validate timing
        guard attendanceStartTime < attendanceEndTime else {
            throw AttendanceViewModelError.validationFailed(
                "End time must be after start time"
            )
        }
        logger.debug("✅ Attendance data validation passed")
    }

    private func validateAttendanceDate() async throws -> Bool {
        guard let schedule = selectedSchedule else {
            logger.warning(
                "⚠️ No schedule selected for attendance date validation"
            )
            return false
        }

        guard let scheduleDay = schedule.scheduleDay else {
            logger.warning("⚠️ Schedule has no day specified")
            return false
        }

        let calendar = Calendar.current

        // Get the weekday from the selected attendance date
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"  // Full day name (Monday, Tuesday, etc.)
        let attendanceDateWeekday = formatter.string(from: attendanceDate)

        // Check if the attendance date's weekday matches the schedule's day
        guard attendanceDateWeekday == scheduleDay else {

            self.showErrorAlert = true
            self.alertMessage =
                "Selected schedule's weekday doesn't match from your selected date's weekday. Please select a different date."
            self.alertTitle = "Attendance Date Mismatch"

            logger.warning(
                "⚠️ Attendance date weekday (\(attendanceDateWeekday)) doesn't match schedule day (\(scheduleDay))"
            )
            return false
        }

        // Get the semester from the schedule's subject
        guard let subject = schedule.subject,
            let semester = subject.semester
        else {
            logger.warning("⚠️ Schedule has no associated subject or semester")
            return false
        }

        // Check if the date lies within the semester's date range
        guard let semesterStartDate = semester.semesterStartDate,
            let semesterEndDate = semester.semesterEndDate
        else {
            logger.warning("⚠️ Semester has no start or end date specified")
            return false
        }

        let attendanceDateOnly = calendar.startOfDay(for: attendanceDate)
        let startDateOnly = calendar.startOfDay(for: semesterStartDate)
        let endDateOnly = calendar.startOfDay(for: semesterEndDate)

        guard
            attendanceDateOnly >= startDateOnly
                && attendanceDateOnly <= endDateOnly
        else {

            self.showErrorAlert = true
            self.alertMessage =
                "Your selected date is outside the semester range. Please select a different date."
            self.alertTitle = "Semester Date Exceeded!"

            logger.warning(
                "⚠️ Attendance date (\(self.attendanceDate)) is outside semester range (\(semesterStartDate) - \(semesterEndDate))"
            )
            return false
        }

        logger.debug(
            "✅ Attendance date validation passed: \(attendanceDateWeekday) matches \(scheduleDay) and is within semester range"
        )
        return true
    }

    // MARK: - Error Handling
    private func wrapError(_ error: Error, context: String) async
        -> AttendanceViewModelError
    {
        if let attendanceError = error as? AttendanceViewModelError {
            return attendanceError
        }

        if let repositoryError = error as? AttendanceRepositoryError {
            switch repositoryError {
            case .attendanceNotFound(let details):
                return .attendanceNotFound(details)
            case .subjectNotFound(let details):
                return .subjectNotFound(details)
            case .duplicateAttendance(let details):
                return .duplicateAttendance(details)
            case .invalidAttendanceData(let details):
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

        alertTitle = "Oops!"
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
                throw AttendanceViewModelError.operationTimeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    func clearForm() {
        attendanceType = ""
        attendancePresent = "Present"
        attendanceEvent = ""
        attendanceDate = Date()
        attendanceLocation = ""

        // Clear schedule first, then reset times to avoid stale data
        selectedSchedule = nil

        // Reset times to a neutral state (start of current day)
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        attendanceStartTime =
            calendar.date(byAdding: .hour, value: 9, to: startOfDay)
            ?? startOfDay
        attendanceEndTime =
            calendar.date(byAdding: .hour, value: 10, to: startOfDay)
            ?? startOfDay

        logger.debug("🧹 Attendance form cleared")
    }

    func clearAlerts() {
        showErrorAlert = false
        showSuccessAlert = false
        alertTitle = ""
        alertMessage = ""
        showRetryOption = false
    }

    func changeSelectedDate(_ newDate: Date) async {
        selectedDate = newDate
        do {
            try await loadAttendanceForDate(newDate, subject: selectedSubject)
        } catch {
            logger.error(
                "❌ Failed to load attendance for new date: \(error.localizedDescription)"
            )
        }
    }

    func changeSelectedSubject(_ newSubject: Subject?) async {
        selectedSubject = newSubject

        // Perform cache maintenance
        performAttendanceCacheMaintenance()

        do {
            if let subject = newSubject {
                try await loadAttendanceForSubject(subject)
            } else {
                attendanceForSelectedSubject = []
                attendanceForSelectedDate = []
            }
        } catch {
            logger.error(
                "❌ Failed to load attendance for new subject: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Query Methods
    func getAttendance(by id: UUID) async throws -> Attendance? {
        return try await repository.getAttendanceById(id)
    }

    func getAttendanceForDateRange(
        startDate: Date,
        endDate: Date,
        subject: Subject
    ) async throws -> [Attendance] {
        return try await repository.getAttendanceForDateRange(
            startDate: startDate,
            endDate: endDate,
            subject: subject
        )
    }

    func getAttendanceCount() -> Int {
        return attendanceList.count
    }

    func hasAttendance() -> Bool {
        return !attendanceList.isEmpty
    }

    func getAttendanceByType(_ type: String) -> [Attendance] {
        return attendanceForSelectedSubject.filter { $0.attendanceType == type }
    }

    func getAttendanceByPresence(_ presence: String) -> [Attendance] {
        return attendanceForSelectedSubject.filter {
            $0.attendancePresence == presence
        }
    }

    // MARK: - Computed Properties

    var cacheStatistics: (entries: Int, subjects: Int, dates: Int) {
        let totalEntries = attendanceCache.count
        let subjectEntries = attendanceCache.keys.filter {
            $0.hasPrefix("attendance-") && !$0.contains("date")
        }.count
        let dateEntries = attendanceCache.keys.filter {
            $0.contains("attendance-date")
        }.count

        return (
            entries: totalEntries, subjects: subjectEntries, dates: dateEntries
        )
    }

    var hasCachedData: Bool {
        !attendanceCache.isEmpty
    }

    var isFormValid: Bool {
        let trimmedType = attendanceType.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let trimmedPresent = attendancePresent.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return !trimmedType.isEmpty && !trimmedPresent.isEmpty
            && trimmedType.count >= 2 && trimmedType.count <= 50
            && availablePresenceStatus.contains(trimmedPresent)
            && selectedSchedule != nil
            && attendanceStartTime < attendanceEndTime
    }

    var isFormValidForUpdate: Bool {
        let trimmedType = attendanceType.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let trimmedPresent = attendancePresent.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return !trimmedType.isEmpty && !trimmedPresent.isEmpty
            && trimmedType.count >= 2 && trimmedType.count <= 50
            && availablePresenceStatus.contains(trimmedPresent)
            && attendanceStartTime < attendanceEndTime
    }

    var canUpdateAttendance: Bool {
        isFormValidForUpdate && !loadingState.isLoading
            && editingAttendance != nil
    }

    var isEditing: Bool {
        editingAttendance != nil
    }

    var formattedSelectedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: selectedDate)
    }

    var formattedAttendanceDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: attendanceDate)
    }

    var formattedAttendanceStartTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: attendanceStartTime)
    }

    var formattedAttendanceEndTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: attendanceEndTime)
    }

    var hasAvailableSchedules: Bool {
        !availableSchedules.isEmpty
    }

    var selectedScheduleName: String {
        if let schedule = selectedSchedule,
            let subject = schedule.subject
        {
            return
                "\(subject.subjectName ?? "Unknown") - \(schedule.scheduleDay ?? "Unknown")"
        }
        return "No schedule selected"
    }

    var selectedSubjectName: String {
        selectedSubject?.subjectName ?? "No subject selected"
    }

    var attendanceStatistics: (total: Int, present: Int, absent: Int) {
        let total = attendanceForSelectedSubject.count
        var present = attendanceForSelectedSubject.filter {
            $0.attendancePresence == "Present"
        }.count
        let medical = attendanceForSelectedSubject.filter {
            $0.attendancePresence == "Medical Substitution"
        }.count
        present = present + medical
        let absent = attendanceForSelectedSubject.filter {
            $0.attendancePresence == "Absent"
        }.count

        return (total: total, present: present, absent: absent)
    }

    var attendanceRate: Double {
        let stats = attendanceStatistics
        guard stats.total > 0 else { return 0.0 }
        return Double(stats.present) / Double(stats.total) * 100.0
    }

    var hasSchedulesForSubject: Bool {
        !schedulesForSubject.isEmpty
    }

    // MARK: – Raw Stats
    private var totalSessions: Int {
        attendanceForSelectedSubject.count
    }
    private var presentSessions: Int {
        attendanceForSelectedSubject
            .filter {
                $0.attendancePresence == "Present"
                    || $0.attendancePresence == "Medical Substitution"
            }
            .count
    }

    var minAllowedDate: Date {
        if let schedule = selectedSchedule,
            let subject = schedule.subject,
            let semester = subject.semester,
            let semesterStartDate = semester.semesterStartDate
        {
            return semesterStartDate
        }
        return Calendar.current.date(byAdding: .year, value: -1, to: Date())
            ?? Date()
    }

    var maxAllowedDate: Date {
        if let schedule = selectedSchedule,
            let subject = schedule.subject,
            let semester = subject.semester,
            let semesterEndDate = semester.semesterEndDate
        {
            return semesterEndDate
        }
        return Date()  // Fallback to today
    }

    var allowedWeekday: String? {
        return selectedSchedule?.scheduleDay
    }

    // MARK: – Inverse Attendance Calculators
    func maxSkippableClasses(beforeDroppingBelow thresholdPercent: Double)
        -> Int
    {
        let N = Double(totalSessions)
        let P = Double(presentSessions)
        let t = thresholdPercent / 100.0
        guard N > 0, t > 0 else { return 0 }
        let raw = (P - t * N) / t
        return max(0, Int(floor(raw)))
    }

    func presencesNeeded(toReach thresholdPercent: Double) -> Int {
        let N = Double(totalSessions)
        let P = Double(presentSessions)
        let t = thresholdPercent / 100.0
        guard N > 0, P / N < t else { return 0 }
        let raw = (t * N - P) / (1.0 - t)
        return max(0, Int(ceil(raw)))
    }

    /// Helper method to update attendance in both arrays after CRUD operations
    private func updateAttendanceInLocalArrays(
        _ attendance: Attendance,
        operation: String
    ) {
        switch operation {
        case "create":
            // Add to arrays with proper sorting
            attendanceForSelectedSubject.append(attendance)
            attendanceForSelectedSubject.sort {
                ($0.attendanceDate ?? Date()) > ($1.attendanceDate ?? Date())
            }

            if Calendar.current.isDate(
                attendance.attendanceDate ?? Date(),
                inSameDayAs: selectedDate
            ) {
                attendanceForSelectedDate.append(attendance)
                attendanceForSelectedDate.sort {
                    ($0.attendanceStartTime ?? Date())
                        < ($1.attendanceStartTime ?? Date())
                }
            }

        case "update":
            // Update is handled inline in updateAttendance due to complexity
            break

        case "delete":
            // Remove from arrays
            attendanceForSelectedSubject.removeAll {
                $0.attendanceId == attendance.attendanceId
            }
            attendanceForSelectedDate.removeAll {
                $0.attendanceId == attendance.attendanceId
            }

        default:
            logger.warning(
                "⚠️ Unknown operation for attendance array update: \(operation)"
            )
        }

        // Always update chart after array changes
        updateWeeklyChartData()
    }

    // MARK: - Date Filtering Helper
    func isDateAllowed(_ date: Date) -> Bool {
        guard let schedule = selectedSchedule else { return false }

        // Check weekday match
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let dateWeekday = formatter.string(from: date)

        guard dateWeekday == schedule.scheduleDay else { return false }

        // Check semester range
        guard let subject = schedule.subject,
            let semester = subject.semester,
            let semesterStartDate = semester.semesterStartDate,
            let semesterEndDate = semester.semesterEndDate
        else { return false }

        let calendar = Calendar.current
        let dateOnly = calendar.startOfDay(for: date)
        let startDateOnly = calendar.startOfDay(for: semesterStartDate)
        let endDateOnly = calendar.startOfDay(for: semesterEndDate)

        return dateOnly >= startDateOnly && dateOnly <= endDateOnly
    }

    // MARK: - Deinitializer
    deinit {
        logger.info("🔄 AttendanceViewModel deinitialized")
    }
}
