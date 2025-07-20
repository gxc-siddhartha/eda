//
//  SemesterViewModel.swift
//  eda
//
//  Created by Siddhartha Srivastava on 12/07/25.
//

import Foundation
import SwiftUI
import CoreData
import os.log

// MARK: - Custom Error Types
enum SemesterViewModelError: LocalizedError {
    case validationFailed(String)
    case repositoryError(String)
    case networkError(String)
    case userCancelled
    case duplicateName(String)
    case semesterNotFound(String)
    case operationTimeout
    case invalidState(String)
    case coreDataError(String)
    
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
        case .duplicateName(let name):
            return "A semester named '\(name)' already exists"
        case .semesterNotFound(let id):
            return "Semester not found: \(id)"
        case .operationTimeout:
            return "Operation timed out. Please try again."
        case .invalidState(let message):
            return "Invalid state: \(message)"
        case .coreDataError(let message):
            return "Database error: \(message)"
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
        case .duplicateName:
            return "Semester name must be unique"
        case .semesterNotFound:
            return "The requested semester could not be found"
        case .operationTimeout:
            return "Operation took too long to complete"
        case .invalidState:
            return "Application is in an invalid state"
        case .coreDataError:
            return "Core Data operation failed"
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
        case .duplicateName:
            return "Please choose a different name"
        case .semesterNotFound:
            return "Refresh the list and try again"
        case .operationTimeout:
            return "Check your connection and try again"
        case .invalidState:
            return "Please restart the app"
        }
    }
}

// MARK: - Loading State
enum LoadingState {
    case idle
    case loading
    case success
    case failure(SemesterViewModelError)
    
    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
    
    var error: SemesterViewModelError? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

@MainActor
class SemesterViewModel: ObservableObject {
    private var masterViewModel: MasterViewModel = MasterViewModel.shared

    // MARK: - Dependencies
    private let repository: SemesterRepository
    private let logger = Logger(subsystem: "com.eda.app", category: "SemesterViewModel")
    
    // MARK: - Editing Options
    @Published var editSemesterName: String = ""
    @Published var editSemesterStartDate: Date = Date()
    @Published var editedEndDate: Date = Date()
    @Published var editedPassingPercentage: String = ""
    
    // MARK: - Published Properties
    @Published var semesterList: [Semester] = []
    @Published var selectedSemesterForUser: Semester? = nil
    @Published var loadingState: LoadingState = .idle
    @Published var isInitialized: Bool = false
    
    @Published var presentSemesterEditSheet: Bool = false
    
    // MARK: - Info Alert Properties
    @Published var showInfoAlert: Bool = false
    @Published var infoAlertTitle: String = ""
    @Published var infoAlertMessage: String = ""
    
    // MARK: - Form Properties
    @Published var selectedSemesterName: String = "Semester 1"
    @Published var semesterStartDate: Date = Date()
    @Published var semesterEndDate: Date = Date()
    @Published var passingPercentage: String = ""
    
    
    @Published var editingSemester: Semester?
    
 
    
    // MARK: - Manage Semesters
    @Published var presentManageSemestersSheet: Bool = false
    
    // MARK: - UI State
    @Published var presentSemesterDetailsSheet: Bool = false
    @Published var showErrorAlert: Bool = false
    @Published var showSuccessAlert: Bool = false
    @Published var alertTitle: String = ""
    @Published var alertMessage: String = ""
    @Published var showRetryOption: Bool = false
    
    // MARK: - Constants
    private let operationTimeout: TimeInterval = 30.0
    let semesterOptions: [String] = [
        "Semester 1", "Semester 2", "Semester 3", "Semester 4",
        "Semester 5", "Semester 6", "Semester 7", "Semester 8",
        "Semester 9", "Semester 10", "Semester 11", "Semester 12"
    ]
    
    // MARK: - Initialization
    init(repository: SemesterRepository = SemesterRepository()) {
        self.repository = repository
        self.logger.info("🚀 SemesterViewModel initialized")
        self.setupInitialDates()
    }
    
    // Call when the user taps “Edit” on a semester row
     func startEditing(_ semester: Semester) {
         editingSemester = semester
         // initialize our two fields from the existing object
         
         editSemesterName = semester.semesterName ?? ""
         editSemesterStartDate = semester.semesterStartDate ?? Date()
         editedEndDate = semester.semesterEndDate ?? Date()
         editedPassingPercentage = semester.passingPercentage ?? ""
     }
     
     // Call to cancel out of edit mode
     func cancelEditing() {
         editingSemester = nil
     }
    
    private func setupInitialDates() {
        self.semesterEndDate = Calendar.current.date(byAdding: .month, value: 5, to: self.semesterStartDate) ?? self.semesterStartDate
        self.logger.debug("📅 Initial dates configured")
    }
    
    // MARK: - Initialization Method
    func initialize() async {
        guard !isInitialized else {
            logger.debug("🔄 SemesterViewModel already initialized")
            return
        }
        
        logger.info("🚀 Initializing SemesterViewModel...")
        loadingState = .loading
        
        do {
            // Load all semesters
            try await loadSemesters()
            
            // Load selected semester
            try await loadSelectedSemester()
            
            isInitialized = true
            loadingState = .success
            logger.info("✅ SemesterViewModel initialization completed successfully")
            
        } catch {
            logger.error("❌ SemesterViewModel initialization failed: \(error.localizedDescription)")
            await handleError(error, operation: "initialization")
        }
    }
    
    // MARK: - Core Operations
    func loadSemesters() async throws {
        logger.info("📚 Loading semesters...")
        loadingState = .loading
        
        do {
            let semesters = try await withTimeout(operationTimeout) {
                try await self.repository.getAllSemesters()
            }
            
            semesterList = semesters
            logger.info("✅ Successfully loaded \(semesters.count) semesters")
            
        } catch {
            let wrappedError = await wrapError(error, context: "loading semesters")
            loadingState = .failure(wrappedError)
            throw wrappedError
        }
    }
    
    func loadSelectedSemester() async throws {
        logger.info("🎯 Loading selected semester...")
        
        do {
            let semester = try await withTimeout(operationTimeout) {
                try await self.repository.getSelectedSemester()
            }
            
            selectedSemesterForUser = semester
            
            if let semester = semester {
                logger.info("✅ Selected semester loaded: \(semester.semesterName ?? "unnamed")")
            } else {
                logger.info("ℹ️ No selected semester found")
            }
            
        } catch {
            let wrappedError = await wrapError(error, context: "loading selected semester")
            logger.warning("⚠️ Failed to load selected semester: \(wrappedError.localizedDescription)")
            // Don't throw here as this is not critical for app function
        }
    }
    
    func createSemester() async throws -> Semester {
        logger.info("💾 Creating semester: \(self.selectedSemesterName)")
        loadingState = .loading
        
        do {
            // Validate input
            try await validateSemesterData()
            
            // Check for duplicates
            let isDuplicate = try await withTimeout(operationTimeout) {
                try await self.repository.checkForDuplicateSemesterName(self.selectedSemesterName)
            }
            
            if isDuplicate {
                let error = SemesterViewModelError.duplicateName(selectedSemesterName)
                await handleError(error, operation: "create semester")
                throw error
            }
            
            // Create semester data
            let semesterData = SemesterData(
                name: selectedSemesterName.trimmingCharacters(in: .whitespacesAndNewlines),
                startDate: semesterStartDate,
                endDate: semesterEndDate,
                passingPercentage: passingPercentage.isEmpty ? nil : passingPercentage
            )
            
            // Create semester
            let newSemester = try await withTimeout(operationTimeout) {
                try await self.repository.createSemester(semesterData: semesterData)
            }
            
            // Update local state
            semesterList.append(newSemester)
            semesterList.sort { ($0.semesterName ?? "") < ($1.semesterName ?? "") }
            
            // Set as selected if it's the first semester
            if semesterList.count == 1 {
                try await selectSemester(newSemester)
            }
            
            // Clear form and close sheet
            clearForm()
            presentSemesterDetailsSheet = false

            loadingState = .success

            try? await Task.sleep(nanoseconds: 500_000_000)
//            
//            await MainActor.run {
//                self.showInfoAlert = true
//                self.infoAlertTitle = "Semester Added"
//                self.infoAlertMessage = "\(selectedSemesterName) is added to your list."
//            }
//            
            await MainActor.run {
                self.masterViewModel.showAlert = true
                self.masterViewModel.alertTitle = "Semester Added"
                self.masterViewModel.alertMessage = "\(selectedSemesterName) is added to your semesters' list. You can now add subjects to this semester."
            }
            
            logger.info("✅ Semester created successfully: \(newSemester.semesterName ?? "unnamed")")
            return newSemester
            
        } catch {
            let wrappedError = await wrapError(error, context: "creating semester")
            await handleError(wrappedError, operation: "create semester")
            throw wrappedError
        }
    }
    
    // The single “save” action: takes the original name & startDate,
        // but applies only the two edited fields
        func updateSemester() async {
            guard let semester = editingSemester,
                  let id = semester.semesterId,
                  let name = semester.semesterName,
                  let startDate = semester.semesterStartDate
                
            else {
                alertMessage = "No Semester Found"
                alertTitle = "Error"
                showErrorAlert = true
                return
            }
          
            let updatedData = SemesterData(
                name: name,
                startDate: startDate,
                endDate: editedEndDate,
                passingPercentage: editedPassingPercentage
            )
            
            do {
                let updated = try await repository.updateSemester(semesterId: id, semesterData: updatedData)
                
                // reflect change in our local array
                if let idx = semesterList.firstIndex(where: { $0.semesterId == id }) {
                    semesterList[idx] = updated
                }
                
                await MainActor.run {
                    presentSemesterEditSheet = false
                    presentManageSemestersSheet = false
                }
                
 
                await MainActor.run {
                    self.masterViewModel.showAlert = true
                    self.masterViewModel.alertTitle = "Semester Updated"
                    self.masterViewModel.alertMessage = "\(name) has been updated."
                   
                }
                
                // exit edit‐mode
                editingSemester = nil
                
            } catch {
                logger.error("❌ Failed to update semester: \(error.localizedDescription)")
                alertMessage = error.localizedDescription
                alertTitle = "Error"
                showErrorAlert = true
            }
        }
    
    func selectSemester(_ semester: Semester) async throws {
        logger.info("🎯 Selecting semester: \(semester.semesterName ?? "unnamed")")
        loadingState = .loading
        
        do {
            try await withTimeout(operationTimeout) {
                try await self.repository.updateSelectedSemester(semester)
            }
            
            selectedSemesterForUser = semester
            loadingState = .success
            
            await showSuccess(title: "Semester Selected", message: "'\(semester.semesterName ?? "Semester")' is now your active semester.")
            
            logger.info("✅ Semester selected successfully: \(semester.semesterName ?? "unnamed")")
            
        } catch {
            let wrappedError = await wrapError(error, context: "selecting semester")
            await handleError(wrappedError, operation: "select semester")
            throw wrappedError
        }
    }
    
    func deleteSemester(_ semester: Semester) async throws {
        guard let semesterId = semester.semesterId else {
            let error = SemesterViewModelError.semesterNotFound("Invalid semester ID")
            await handleError(error, operation: "delete semester")
            throw error
        }
        
        logger.info("🗑️ Deleting semester: \(semester.semesterName ?? "unnamed")")
        loadingState = .loading
        
        do {
            // Check if this is the selected semester
            let isSelectedSemester = selectedSemesterForUser?.semesterId == semesterId
            
            try await withTimeout(operationTimeout) {
                try await self.repository.deleteSemester(semesterId: semesterId)
            }
            
            // Update local state
            semesterList.removeAll { $0.semesterId == semesterId }
            
            // Clear selection if this was the selected semester
            if isSelectedSemester {
                selectedSemesterForUser = nil
                if(!semesterList.isEmpty) {
                    selectedSemesterForUser = semesterList[0]
                }
            }
            
            loadingState = .success
            logger.info("✅ Semester deleted successfully: \(semester.semesterName ?? "unnamed")")
            
        } catch {
            let wrappedError = await wrapError(error, context: "deleting semester")
            await handleError(wrappedError, operation: "delete semester")
            throw wrappedError
        }
    }
    
    func refreshData() async {
        logger.info("🔄 Refreshing semester data...")
        loadingState = .loading
        
        do {
            try await loadSemesters()
            try await loadSelectedSemester()
            loadingState = .success
            await showSuccess(title: "Data Refreshed", message: "Semester data has been updated.")
        } catch {
            logger.error("❌ Failed to refresh data: \(error.localizedDescription)")
            await handleError(error, operation: "refresh data", showRetry: true)
        }
    }
    
    // MARK: - Validation Methods
    private func validateSemesterData() async throws {
        logger.debug("🔍 Validating semester data...")
        
        let trimmedName = selectedSemesterName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedName.isEmpty else {
            throw SemesterViewModelError.validationFailed("Semester name cannot be empty")
        }
        
        guard trimmedName.count >= 2 else {
            throw SemesterViewModelError.validationFailed("Semester name must be at least 2 characters long")
        }
        
        guard trimmedName.count <= 50 else {
            throw SemesterViewModelError.validationFailed("Semester name cannot exceed 50 characters")
        }
        
        guard semesterStartDate <= semesterEndDate else {
            throw SemesterViewModelError.validationFailed("Start date must be before or equal to end date")
        }
        
        let currentDate = Date()
        let fiveYearsAgo = Calendar.current.date(byAdding: .year, value: -5, to: currentDate) ?? currentDate
        let fiveYearsFromNow = Calendar.current.date(byAdding: .year, value: 5, to: currentDate) ?? currentDate
        
        guard semesterStartDate >= fiveYearsAgo && semesterStartDate <= fiveYearsFromNow else {
            throw SemesterViewModelError.validationFailed("Start date must be within 5 years of current date")
        }
        
        guard semesterEndDate >= fiveYearsAgo && semesterEndDate <= fiveYearsFromNow else {
            throw SemesterViewModelError.validationFailed("End date must be within 5 years of current date")
        }
        
        if !passingPercentage.isEmpty {
            guard let percentage = Double(passingPercentage), percentage >= 0 && percentage <= 100 else {
                throw SemesterViewModelError.validationFailed("Passing percentage must be between 0 and 100")
            }
        }
        
        logger.debug("✅ Semester data validation passed")
    }
    
    // MARK: - Error Handling
    private func wrapError(_ error: Error, context: String) async -> SemesterViewModelError {
        if let semesterError = error as? SemesterViewModelError {
            return semesterError
        }
        
        if error is CancellationError {
            return .userCancelled
        }
        
        if let nsError = error as NSError? {
            switch nsError.domain {
            case NSCocoaErrorDomain:
                return .coreDataError("Core Data error in \(context): \(nsError.localizedDescription)")
            case NSURLErrorDomain:
                return .networkError("Network error in \(context): \(nsError.localizedDescription)")
            default:
                return .repositoryError("Repository error in \(context): \(nsError.localizedDescription)")
            }
        }
        
        return .repositoryError("Unknown error in \(context): \(error.localizedDescription)")
    }
    
    private func handleError(_ error: Error, operation: String, showRetry: Bool = false) async {
        let wrappedError = await wrapError(error, context: operation)
        
        logger.error("❌ Error in \(operation): \(wrappedError.localizedDescription)")
        
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
    private func withTimeout<T>(_ timeout: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw SemesterViewModelError.operationTimeout
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    // MARK: - Utility Methods
    func clearForm() {
        selectedSemesterName = "Semester 1"
        semesterStartDate = Date()
        semesterEndDate = Calendar.current.date(byAdding: .month, value: 5, to: Date()) ?? Date()
        passingPercentage = "40"
        logger.debug("🧹 Form cleared")
    }
    
    func clearAlerts() {
        showErrorAlert = false
        showSuccessAlert = false
        alertTitle = ""
        alertMessage = ""
        showRetryOption = false
    }
    
    func retryLastOperation() async {
        logger.info("🔄 Retrying last operation...")
        await refreshData()
    }
    
    // MARK: - Computed Properties
    var hasSelectedSemester: Bool {
        selectedSemesterForUser != nil
    }
    
    var isFormValid: Bool {
        let trimmedName = selectedSemesterName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassingPercentage = passingPercentage.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty &&
               trimmedName.count >= 2 &&
               trimmedName.count <= 50 &&
        Int(trimmedPassingPercentage) != nil &&
        Int(trimmedPassingPercentage)! >= 0 &&
        Int(trimmedPassingPercentage)! <= 100 &&
               semesterStartDate <= semesterEndDate
    }
    
    var canCreateSemester: Bool {
        isFormValid && !loadingState.isLoading
    }
    
    // MARK: - Deinitializer
    deinit {
        logger.info("🔄 SemesterViewModel deinitialized")
    }
}
