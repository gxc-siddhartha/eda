import CoreData
import Foundation
import SwiftUI
import os.log

// MARK: - Import State
enum ImportState {
    case idle
    case importing
    case completed(BulkImportResult)
    case failed(Error)
}

// MARK: - Import Type
enum ImportType {
    case subjects
    case schedules
}

/// ViewModel that manages bulk CSV imports (for subjects and schedules) and alerts.
@MainActor
class MasterViewModel: ObservableObject {
    static let shared = MasterViewModel()

    // MARK: - ViewModel References (ADD THESE)
    weak var subjectViewModel: SubjectViewModel?
    weak var scheduleViewModel: ScheduleViewModel?

    // MARK: - UI State
    @Published var showAlert: Bool = false
    @Published var alertTitle: String = ""
    @Published var alertMessage: String = ""
    @Published var isLoading: Bool = false
    @Published var presentImportSheet: Bool = false

    // MARK: - Import State
    @Published var isImporting: Bool = false
    @Published var importProgress: String = ""
    @Published var selectedSubjectCSVContent: String?
    @Published var selectedSubjectFileName: String?
    @Published var selectedScheduleCSVContent: String?
    @Published var selectedScheduleFileName: String?
    @Published var importState: ImportState = .idle
    @Published var currentImportType: ImportType = .subjects
    
    // ✅ ADD THIS - Notification status tracking (optional)
        @Published var notificationPermissionStatus: UNAuthorizationStatus = .notDetermined
        @Published var scheduledNotificationCount: Int = 0

    // MARK: - Import Results
    @Published var lastImportResult: BulkImportResult?

    // MARK: - Dependencies
    private let bulkImporter: BulkImportRepository
    private let logger = Logger(
        subsystem: "com.eda.app",
        category: "MasterViewModel"
    )

    // MARK: - Initialization
    init(bulkImporter: BulkImportRepository = BulkImportRepository()) {
        self.bulkImporter = bulkImporter
    }

    // MARK: - Public API - File Selection for Subjects

    /// Sets the selected CSV content for subject import
    /// - Parameters:
    ///   - content: The CSV file content as string
    ///   - fileName: The original filename for display
    func selectSubjectCSVContent(_ content: String, fileName: String) {
        selectedSubjectCSVContent = content
        selectedSubjectFileName = fileName
        currentImportType = .subjects
        logger.info("📁 Subject CSV content selected: \(fileName)")
        resetImportState()
    }

    /// Clears the selected subject CSV content
    func clearSubjectSelectedFile() {
        selectedSubjectCSVContent = nil
        selectedSubjectFileName = nil
        resetImportState()
        logger.info("🗑️ Subject CSV content selection cleared")
    }

    // MARK: - Public API - File Selection for Schedules

    /// Sets the selected CSV content for schedule import
    /// - Parameters:
    ///   - content: The CSV file content as string
    ///   - fileName: The original filename for display
    func selectScheduleCSVContent(_ content: String, fileName: String) {
        selectedScheduleCSVContent = content
        selectedScheduleFileName = fileName
        currentImportType = .schedules
        logger.info("📁 Schedule CSV content selected: \(fileName)")
        resetImportState()
    }

    /// Clears the selected schedule CSV content
    func clearScheduleSelectedFile() {
        selectedScheduleCSVContent = nil
        selectedScheduleFileName = nil
        resetImportState()
        logger.info("🗑️ Schedule CSV content selection cleared")
    }

    // MARK: - Public API - Subject Import Operations

    /// Triggers a bulk import of subjects from the selected CSV content into the specified semester.
    /// Updates import state and shows results in alert.
    /// - Parameter semester: The semester to import subjects into
    func importSubjectsFromSelectedFile(for semester: Semester) {
        guard let content = selectedSubjectCSVContent else {
            showErrorAlert(
                title: "No File Selected",
                message: "Please select a CSV file before importing subjects."
            )
            return
        }

        let fileName = selectedSubjectFileName ?? "unknown.csv"
        importSubjectsCSV(content: content, fileName: fileName, for: semester)
    }

    /// Triggers a bulk import of subjects from the given CSV content into the specified semester.
    /// Updates import state and shows results in alert.
    /// - Parameters:
    ///   - content: The CSV content as string
    ///   - fileName: The filename for logging purposes
    ///   - semester: The semester to import subjects into
    func importSubjectsCSV(
        content: String,
        fileName: String,
        for semester: Semester
    ) {
        guard !isImporting else {
            logger.warning(
                "⚠️ Import already in progress, ignoring new import request"
            )
            return
        }

        logger.info(
            "🚀 Starting subject CSV import from: \(fileName) for semester: \(semester.semesterName ?? "unknown")"
        )

        currentImportType = .subjects
        setImportingState(true)
        importProgress = "Preparing subject import..."

        Task {
            await performSubjectImport(
                content: content,
                fileName: fileName,
                for: semester
            )
        }
    }

    // MARK: - Public API - Schedule Import Operations

    /// Triggers a bulk import of schedules from the selected CSV content into the specified semester.
    /// Updates import state and shows results in alert.
    /// - Parameter semester: The semester to import schedules into
    func importSchedulesFromSelectedFile(for semester: Semester) {
        guard let content = selectedScheduleCSVContent else {
            showErrorAlert(
                title: "No File Selected",
                message: "Please select a CSV file before importing schedules."
            )
            return
        }

        let fileName = selectedScheduleFileName ?? "unknown.csv"
        importSchedulesCSV(content: content, fileName: fileName, for: semester)
    }

    /// Triggers a bulk import of schedules from the given CSV content into the specified semester.
    /// Updates import state and shows results in alert.
    /// - Parameters:
    ///   - content: The CSV content as string
    ///   - fileName: The filename for logging purposes
    ///   - semester: The semester to import schedules into
    func importSchedulesCSV(
        content: String,
        fileName: String,
        for semester: Semester
    ) {
        guard !isImporting else {
            logger.warning(
                "⚠️ Import already in progress, ignoring new import request"
            )
            return
        }

        logger.info(
            "🚀 Starting schedule CSV import from: \(fileName) for semester: \(semester.semesterName ?? "unknown")"
        )

        currentImportType = .schedules
        setImportingState(true)
        importProgress = "Preparing schedule import..."

        Task {
            await performScheduleImport(
                content: content,
                fileName: fileName,
                for: semester
            )
        }
    }

    /// Cancels the current import operation (if possible)
    func cancelImport() {
        // Note: The actual Core Data operation can't be cancelled mid-operation,
        // but we can reset the UI state
        if isImporting {
            logger.warning("⚠️ Import cancellation requested")
            setImportingState(false)
            importState = .idle
            showErrorAlert(
                title: "Import Cancelled",
                message: "The import operation was cancelled."
            )
        }
    }

    // MARK: - Public API - Search Operations

    /// Searches for subjects by name using the bulk importer
    /// - Parameters:
    ///   - name: The subject name to search for
    ///   - semester: Optional semester to scope the search
    /// - Returns: Array of matching subjects
    func searchSubjects(byName name: String, in semester: Semester? = nil)
        async throws -> [Subject]
    {
        logger.debug("🔍 Searching for subjects with name: '\(name)'")
        return try await bulkImporter.getSubjectsByName(name, in: semester)
    }

    /// Searches for subjects by partial name using the bulk importer
    /// - Parameters:
    ///   - partialName: The partial subject name to search for
    ///   - semester: Optional semester to scope the search
    /// - Returns: Array of matching subjects
    func searchSubjects(
        byPartialName partialName: String,
        in semester: Semester? = nil
    ) async throws -> [Subject] {
        logger.debug("🔍 Searching for subjects containing: '\(partialName)'")
        return try await bulkImporter.getSubjectsByPartialName(
            partialName,
            in: semester
        )
    }

    // MARK: - File System Access

    /// Requests access to the app's Documents directory and lists files
    /// Note: This accesses the app's own sandbox Documents directory, not the user's Documents folder
    func requestFileSystemAccess() {
        logger.info("📁 Requesting file system access to Documents directory")

        // For accessing app's own Documents directory
        guard
            let documentsURL = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first
        else {
            logger.error("❌ Could not get Documents directory URL")
            showErrorAlert(
                title: "File System Error",
                message: "Could not access Documents directory."
            )
            return
        }

        logger.debug("📂 Documents directory path: \(documentsURL.path)")

        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: documentsURL,
                includingPropertiesForKeys: [
                    .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
                ]
            )

            logger.info(
                "✅ Successfully accessed Documents directory. Found \(files.count) items"
            )

            // Log details about each file
            for fileURL in files {
                do {
                    let resourceValues = try fileURL.resourceValues(forKeys: [
                        .isDirectoryKey, .fileSizeKey,
                        .contentModificationDateKey,
                    ])
                    let isDirectory = resourceValues.isDirectory ?? false
                    let fileSize = resourceValues.fileSize ?? 0
                    let modDate =
                        resourceValues.contentModificationDate ?? Date()

                    let type = isDirectory ? "📁 Directory" : "📄 File"
                    logger.debug(
                        "\(type): \(fileURL.lastPathComponent) (\(fileSize) bytes, modified: \(modDate))"
                    )
                } catch {
                    logger.debug(
                        "📄 File: \(fileURL.lastPathComponent) (could not read properties)"
                    )
                }
            }

            // Show success alert with file count
            let message =
                files.isEmpty
                ? "Documents directory is empty."
                : "Found \(files.count) items in Documents directory. Check console for details."

            showSuccessAlert(
                title: "File System Access Successful",
                message: message
            )

        } catch {
            logger.error(
                "❌ File system access denied: \(error.localizedDescription)"
            )
            showErrorAlert(
                title: "File System Access Denied",
                message:
                    "Could not access Documents directory: \(error.localizedDescription)"
            )
        }
    }

    /// Gets the app's Documents directory URL
    /// - Returns: URL to the app's Documents directory, or nil if not accessible
    func getDocumentsDirectory() -> URL? {
        return FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first
    }

    /// Lists all CSV files in the app's Documents directory
    /// - Returns: Array of CSV file URLs found in Documents directory
    func listCSVFilesInDocuments() -> [URL] {
        guard let documentsURL = getDocumentsDirectory() else {
            logger.error("❌ Could not get Documents directory")
            return []
        }

        do {
            let allFiles = try FileManager.default.contentsOfDirectory(
                at: documentsURL,
                includingPropertiesForKeys: [.isDirectoryKey]
            )

            let csvFiles = allFiles.filter { url in
                !url.hasDirectoryPath && url.pathExtension.lowercased() == "csv"
            }

            logger.info(
                "📊 Found \(csvFiles.count) CSV files in Documents directory"
            )
            return csvFiles

        } catch {
            logger.error(
                "❌ Error listing CSV files: \(error.localizedDescription)"
            )
            return []
        }
    }

    // MARK: - Alert Management

    /// Shows a success alert with the given title and message
    /// - Parameters:
    ///   - title: Alert title
    ///   - message: Alert message
    func showSuccessAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
        logger.info("✅ Success alert: \(title)")
    }

    /// Shows an error alert with the given title and message
    /// - Parameters:
    ///   - title: Alert title
    ///   - message: Alert message
    func showErrorAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
        logger.error("❌ Error alert: \(title) - \(message)")
    }

    /// Dismisses the current alert
    func dismissAlert() {
        showAlert = false
        alertTitle = ""
        alertMessage = ""
    }
    
    // ✅ ADD THIS - Notification status methods (optional)
    func updateNotificationStatus() async {
        let status = await NotificationManager.shared.checkPermissionStatus()
        let count = await NotificationManager.shared.getScheduledReminderCount()
        
        await MainActor.run {
            self.notificationPermissionStatus = status
            self.scheduledNotificationCount = count
        }
    }

    // MARK: - Private Helpers

    // MARK: - Data Refresh After Import

    /// Refreshes subject data across the app after successful import
    private func refreshSubjectDataAfterImport(semester: Semester) async {
        logger.info(
            "🔄 Refreshing subject data after import for semester: \(semester.semesterName ?? "unknown")"
        )

        guard let subjectViewModel = subjectViewModel else {
            logger.warning(
                "⚠️ SubjectViewModel reference not set, cannot refresh after import"
            )
            return
        }

        do {
            // Clear subject cache for this semester
            let key = subjectViewModel.subjectCacheKey(for: semester)
            subjectViewModel.invalidateSubjectCache(for: key)

            // Reload fresh data
            try await subjectViewModel.loadSubjects(semester: semester)

            logger.info("✅ Successfully refreshed subjects after import")
        } catch {
            logger.error(
                "❌ Failed to refresh subjects after import: \(error.localizedDescription)"
            )
        }
    }

    /// Refreshes schedule data across the app after successful import
    private func refreshScheduleDataAfterImport(semester: Semester) async {
        logger.info(
            "🔄 Refreshing schedule data after import for semester: \(semester.semesterName ?? "unknown")"
        )

        guard let scheduleViewModel = scheduleViewModel else {
            logger.warning(
                "⚠️ ScheduleViewModel reference not set, cannot refresh after import"
            )
            return
        }

        do {
            // Clear schedule cache for current date
            let key = scheduleViewModel.cacheKey(
                for: scheduleViewModel.selectedDate,
                semester: semester
            )
            scheduleViewModel.invalidateCache(for: key)

            // Reload fresh data
            try await scheduleViewModel.loadSchedules(
                for: scheduleViewModel.selectedDate,
                semester: semester
            )
            await scheduleViewModel.checkCurrentlyActiveSchedule(for: semester)

            logger.info("✅ Successfully refreshed schedules after import")
        } catch {
            logger.error(
                "❌ Failed to refresh schedules after import: \(error.localizedDescription)"
            )
        }
    }

    private func performSubjectImport(
        content: String,
        fileName: String,
        for semester: Semester
    ) async {
        importProgress = "Reading subject CSV content..."

        do {
            importProgress = "Processing subjects..."
            let result = try await bulkImporter.bulkImportSubjects(
                content: content,
                fileName: fileName,
                for: semester
            )

            importProgress = "Subject import completed!"
            lastImportResult = result
            importState = .completed(result)

            let successMessage = createSuccessMessage(
                from: result,
                type: "subjects"
            )

            presentImportSheet = false

            // ✅ REFRESH SUBJECT DATA AFTER IMPORT
            await refreshSubjectDataAfterImport(semester: semester)

            try await Task.sleep(nanoseconds: 500_000_000)  // ✅ 500ms

            showSuccessAlert(
                title: "Subject Import Completed",
                message: successMessage
            )
            logger.info(
                "✅ Subject import completed successfully: \(result.successfulImports)/\(result.totalRows) subjects imported"
            )

        } catch {
            importState = .failed(error)
            let errorMessage = createErrorMessage(from: error)
            showErrorAlert(
                title: "Subject Import Failed",
                message: errorMessage
            )

            logger.error(
                "❌ Subject import failed: \(error.localizedDescription)"
            )
        }

        setImportingState(false)
        importProgress = ""
    }

    private func performScheduleImport(
        content: String,
        fileName: String,
        for semester: Semester
    ) async {
        importProgress = "Reading schedule CSV content..."

        do {
            importProgress = "Processing schedules..."
            let result = try await bulkImporter.bulkImportSchedules(
                content: content,
                fileName: fileName,
                for: semester
            )

            importProgress = "Schedule import completed!"
            lastImportResult = result
            importState = .completed(result)

            let successMessage = createSuccessMessage(
                from: result,
                type: "schedules"
            )

            presentImportSheet = false

            // ✅ REFRESH SCHEDULE DATA AFTER IMPORT
            await refreshScheduleDataAfterImport(semester: semester)

            try await Task.sleep(nanoseconds: 500_000_000)  // ✅ 500ms

            showSuccessAlert(
                title: "Schedule Import Completed",
                message: successMessage
            )

            logger.info(
                "✅ Schedule import completed successfully: \(result.successfulImports)/\(result.totalRows) schedules imported"
            )

        } catch {
            importState = .failed(error)
            let errorMessage = createErrorMessage(from: error)
            showErrorAlert(
                title: "Schedule Import Failed",
                message: errorMessage
            )

            logger.error(
                "❌ Schedule import failed: \(error.localizedDescription)"
            )
        }

        setImportingState(false)
        importProgress = ""
    }

    private func setImportingState(_ importing: Bool) {
        isImporting = importing
        isLoading = importing
    }

    private func resetImportState() {
        importState = .idle
        lastImportResult = nil
        importProgress = ""
    }

    private func createSuccessMessage(
        from result: BulkImportResult,
        type: String
    ) -> String {
        var message =
            "Successfully imported \(result.successfulImports) out of \(result.totalRows) \(type)."

        if result.skippedRows > 0 {
            message +=
                "\n\n\(result.skippedRows) \(type) were skipped (likely duplicates)."
        }

        if !result.errors.isEmpty {
            message +=
                "\n\n\(result.errors.count) rows had errors and couldn't be imported."
        }

        return message
    }

    private func createErrorMessage(from error: Error) -> String {
        if let bulkImportError = error as? BulkImportRepositoryError {
            switch bulkImportError {
            case .csvParsingError(let details):
                return
                    "Failed to read the CSV file. Please check that it's a valid CSV format.\n\nDetails: \(details)"
            case .semesterNotFound(let details):
                return
                    "The selected semester could not be found. Please try again.\n\nDetails: \(details)"
            case .coreDataError(let details):
                return
                    "A database error occurred while importing. Please try again.\n\nDetails: \(details)"
            case .invalidRowData(let details, let rowNumber):
                return
                    "Invalid data found in row \(rowNumber). Please check your CSV file.\n\nDetails: \(details)"
            }
        }

        return "An unexpected error occurred: \(error.localizedDescription)"
    }
}

// MARK: - Computed Properties
extension MasterViewModel {

    /// Whether a subject CSV content is currently selected
    var hasSelectedSubjectFile: Bool {
        selectedSubjectCSVContent != nil
    }

    /// Whether a schedule CSV content is currently selected
    var hasSelectedScheduleFile: Bool {
        selectedScheduleCSVContent != nil
    }

    /// Whether the subject import can be started (has content and not currently importing)
    var canStartSubjectImport: Bool {
        hasSelectedSubjectFile && !isImporting
    }

    /// Whether the schedule import can be started (has content and not currently importing)
    var canStartScheduleImport: Bool {
        hasSelectedScheduleFile && !isImporting
    }

    /// Whether the last import had any issues (skipped rows or errors)
    var lastImportHadIssues: Bool {
        guard let result = lastImportResult else { return false }
        return result.skippedRows > 0 || !result.errors.isEmpty
    }
}
