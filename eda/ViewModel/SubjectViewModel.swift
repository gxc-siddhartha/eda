//
//  SubjectViewModel.swift
//  eda
//
//  Created by Siddhartha Srivastava on 12/07/25.
//

import Foundation
import SwiftUI
import CoreData
import os.log

// MARK: - Custom Error Types
enum SubjectViewModelError: LocalizedError {
    case validationFailed(String)
    case repositoryError(String)
    case networkError(String)
    case userCancelled
    case duplicateName(String)
    case subjectNotFound(String)
    case semesterNotFound(String)
    case operationTimeout
    case invalidState(String)
    case coreDataError(String)
    case noSemesterSelected
    
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
            return "A subject named '\(name)' already exists in this semester"
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
            return "Subject name must be unique within a semester"
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
            return "A semester must be selected before managing subjects"
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
        case .subjectNotFound, .semesterNotFound:
            return "Refresh the list and try again"
        case .operationTimeout:
            return "Check your connection and try again"
        case .invalidState:
            return "Please restart the app"
        case .noSemesterSelected:
            return "Select a semester from the semester picker"
        }
    }
}

// MARK: - Loading State
enum SubjectLoadingState {
    case idle
    case loading
    case success
    case failure(SubjectViewModelError)
    
    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
    
    var error: SubjectViewModelError? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

@MainActor
class SubjectViewModel: ObservableObject {
    private var masterViewModel: MasterViewModel = MasterViewModel.shared

    // MARK: - Dependencies
    private let repository: SubjectRepository
    private let logger = Logger(subsystem: "com.eda.app", category: "SubjectViewModel")
    
    // MARK: - Cache Properties (ADD THESE)
    private var subjectCache: [String: [Subject]] = [:]
    private var subjectCacheTimestamp: [String: Date] = [:]
    private let subjectCacheValidityDuration: TimeInterval = 600
    
    // MARK: - Published Properties
    @Published var subjectsList: [Subject] = []
    @Published var loadingState: SubjectLoadingState = .idle
    @Published var isInitialized: Bool = false
    
    // MARK: - Editing
    @Published var subjectToBeEdited: Subject? = nil
    
    // MARK: - Info Alert Properties
    @Published var showInfoAlert: Bool = false
    @Published var infoAlertTitle: String = ""
    @Published var infoAlertMessage: String = ""
    
    // MARK: - Form Properties
    @Published var subjectName: String = ""
    @Published var subjectTeacher: String = ""
    @Published var subjectColor: String = "Blue"
    @Published var subjectIcon: String = "character.book.closed"
    
    // MARK: - UI State
    @Published var presentSubjectCreateSheet: Bool = false
    @Published var presentSubjectEditSheet: Bool = false
    @Published var showErrorAlert: Bool = false
    @Published var showSuccessAlert: Bool = false
    @Published var alertTitle: String = ""
    @Published var alertMessage: String = ""
    @Published var showRetryOption: Bool = false
    
    // MARK: - Edit State
    @Published var editingSubject: Subject? = nil
    
    // MARK: - Constants
    private let operationTimeout: TimeInterval = 30.0
    let availableColors: [String] = [
        "Red", "Blue", "Green", "Orange", "Purple", "Pink", "Yellow", "Brown", "Teal"
    ]
    let availableIcons: [String] = [
        "book.closed", "character.book.closed","apple.intelligence", "apple.logo", "applescript","book", "graduationcap", "icloud", "network", "globe",
        "atom", "flask", "paintbrush", "music.note", "theatermasks", "dpad", "gamecontroller", "moped", "apple.terminal","tray.full",  "volleyball", "gearshape.2", "gyroscope", "pianokeys", "wrench.and.screwdriver" , "printer", "suitcase", "lightbulb.max", "powercord"
    ]
    
    // MARK: - Initialization
    init(repository: SubjectRepository = SubjectRepository()) {
        self.repository = repository
        self.logger.info("🚀 SubjectViewModel initialized")
    }
    
    // MARK: - Initialization Method
    func initialize(with semester: Semester?) async {
        logger.info("🚀 Initializing SubjectViewModel with semester: \(semester?.semesterName ?? "nil")")
        
        guard !isInitialized else {
            logger.debug("🔄 SubjectViewModel already initialized")
            return // ✅ Just return, don't reload
        }
        loadingState = .loading
        
        do {
            try await loadSubjects(semester: semester)
            isInitialized = true
            loadingState = .success
            logger.info("✅ SubjectViewModel initialization completed successfully")
            
        } catch {
            logger.error("❌ SubjectViewModel initialization failed: \(error.localizedDescription)")
            await handleError(error, operation: "initialization")
        }
    }
    
    // MARK: - Subject Cache Management (ADD THIS ENTIRE SECTION)

    /// Creates a unique cache key for semester
    private func subjectCacheKey(for semester: Semester?) -> String {
        let semesterName = semester?.semesterName ?? "no-semester"
        let semesterId = semester?.semesterId?.uuidString ?? "no-id"
        return "subjects-\(semesterName)-\(semesterId)"
    }

    /// Checks if cached data is still valid (not expired)
    private func isSubjectCacheValid(for key: String) -> Bool {
        guard let timestamp = subjectCacheTimestamp[key] else { return false }
        return Date().timeIntervalSince(timestamp) < subjectCacheValidityDuration
    }

    /// Stores subjects in cache with current timestamp
    private func cacheSubjects(_ subjects: [Subject], for key: String) {
        subjectCache[key] = subjects
        subjectCacheTimestamp[key] = Date()
        logger.debug("📋 Cached \(subjects.count) subjects for key: \(key)")
    }

    /// Retrieves cached subjects if available and valid
    private func getCachedSubjects(for key: String) -> [Subject]? {
        guard isSubjectCacheValid(for: key), let subjects = subjectCache[key] else {
            return nil
        }
        logger.debug("📋 Using cached subjects for key: \(key) (\(subjects.count) items)")
        return subjects
    }

    /// Invalidates cache for a specific key
    private func invalidateSubjectCache(for key: String) {
        subjectCache.removeValue(forKey: key)
        subjectCacheTimestamp.removeValue(forKey: key)
        logger.debug("🗑️ Invalidated subject cache for key: \(key)")
    }

    /// Clears expired cache entries
    private func clearExpiredSubjectCache() {
        let now = Date()
        let expiredKeys = subjectCacheTimestamp.compactMap { key, timestamp in
            now.timeIntervalSince(timestamp) > subjectCacheValidityDuration ? key : nil
        }
        
        for key in expiredKeys {
            subjectCache.removeValue(forKey: key)
            subjectCacheTimestamp.removeValue(forKey: key)
        }
        
        if !expiredKeys.isEmpty {
            logger.debug("🧹 Cleared \(expiredKeys.count) expired subject cache entries")
        }
    }
    
    // MARK: - Core Operations
    func loadSubjects(semester: Semester?) async throws {
        if semester == nil {
            logger.warning("⚠️ Cannot load subjects: no semester selected")
            loadingState = .failure(.noSemesterSelected)
            return
        }
        
        // Clear expired cache entries first
        clearExpiredSubjectCache()
        
        // Generate cache key
        let key = subjectCacheKey(for: semester)
        
        // Check cache first
        if let cachedSubjects = getCachedSubjects(for: key) {
            subjectsList = cachedSubjects
            loadingState = .success
            logger.info("✅ loadSubjects: Used cached data (\(cachedSubjects.count) subjects)")
            return
        }
        
        // Cache miss - load from database
        logger.info("📚 Loading subjects for semester: \(semester!.semesterName ?? "unknown")")
        loadingState = .loading
        
        do {
            let subjects = try await withTimeout(operationTimeout) {
                try await self.repository.getAllSubjects(for: semester!)
            }
            
            // Cache the results
            cacheSubjects(subjects, for: key)
            
            // Update UI
            subjectsList = subjects
            loadingState = .success
            
            logger.info("✅ loadSubjects: Successfully loaded and cached \(subjects.count) subjects")
            
        } catch {
            let wrappedError = await wrapError(error, context: "loading subjects")
            loadingState = .failure(wrappedError)
            throw wrappedError
        }
    }
    
    func createSubject(semester: Semester?) async throws -> Subject {
        if(semester == nil){
            let error = SubjectViewModelError.noSemesterSelected
            await handleError(error, operation: "create subject")
            throw error
        }
        
        logger.info("💾 Creating subject: \(self.subjectName)")
        loadingState = .loading
        
        do {
            // Validate input
            try await validateSubjectData()
            
            // Check for duplicates
            let isDuplicate = try await withTimeout(operationTimeout) {
                try await self.repository.checkForDuplicateSubjectName(self.subjectName, in: semester!)
            }
            
            if isDuplicate {
                let error = SubjectViewModelError.duplicateName(subjectName)
                await handleError(error, operation: "create subject")
                throw error
            }
            
            // Create subject data
            let subjectData = SubjectData(
                name: subjectName.trimmingCharacters(in: .whitespacesAndNewlines),
                teacher: subjectTeacher.trimmingCharacters(in: .whitespacesAndNewlines),
                color: subjectColor,
                icon: subjectIcon
            )
            
            // Create subject
            let newSubject = try await withTimeout(operationTimeout) {
                try await self.repository.createSubject(subjectData: subjectData, for: semester!)
            }
            
            // Invalidate cache for the semester
            let cacheKey = subjectCacheKey(for: semester)
            invalidateSubjectCache(for: cacheKey)

            // Update local state
            subjectsList.append(newSubject)
            subjectsList.sort { ($0.subjectName ?? "") < ($1.subjectName ?? "") }

            // Clear form and close sheet
            presentSubjectCreateSheet = false
            loadingState = .success

            self.masterViewModel.showAlert = true
            self.masterViewModel.alertTitle = "Subject Created"
            self.masterViewModel.alertMessage = "..."
        
            
            logger.info("✅ Subject created successfully: \(newSubject.subjectName ?? "unnamed")")
            clearForm()
            return newSubject
            
        } catch {
            let wrappedError = await wrapError(error, context: "creating subject")
            await handleError(wrappedError, operation: "create subject")
            throw wrappedError
        }
    }
    
    func updateSubject(semester: Semester?) async throws -> Subject {
        if(semester == nil ){
            let error = SubjectViewModelError.noSemesterSelected
            await handleError(error, operation: "update subject")
            throw error
        }
        
        guard let editingSubject = editingSubject,
              let subjectId = editingSubject.subjectId else {
            let error = SubjectViewModelError.subjectNotFound("No subject selected for editing")
            await handleError(error, operation: "update subject")
            throw error
        }
        
        logger.info("📝 Updating subject: \(self.subjectName)")
        loadingState = .loading
        
        do {
            // Validate input
            try await validateSubjectData()
            
            // Check for duplicates (excluding current subject)
            let isDuplicate = try await withTimeout(operationTimeout) {
                try await self.repository.checkForDuplicateSubjectName(self.subjectName, in: semester!, excluding: subjectId)
            }
            
            if isDuplicate {
                let error = SubjectViewModelError.duplicateName(subjectName)
                await handleError(error, operation: "update subject")
                throw error
            }
            
            // Create subject data
            let subjectData = SubjectData(
                name: subjectName.trimmingCharacters(in: .whitespacesAndNewlines),
                teacher: subjectTeacher.trimmingCharacters(in: .whitespacesAndNewlines),
                color: subjectColor,
                icon: subjectIcon
            )
            
            // Update subject
            let updatedSubject = try await withTimeout(operationTimeout) {
                try await self.repository.updateSubject(subjectId: subjectId, subjectData: subjectData, for: semester!)
            }

            // ✅ UPDATE LOCAL STATE (ADD THIS SECTION)
            if let index = subjectsList.firstIndex(where: { $0.subjectId == subjectId }) {
                subjectsList[index] = updatedSubject
                subjectsList.sort { ($0.subjectName ?? "") < ($1.subjectName ?? "") }
                logger.debug("✅ Updated subject in local list: \(updatedSubject.subjectName ?? "unnamed")")
            }

            // Invalidate cache for the semester (but after updating local state)
            let cacheKey = subjectCacheKey(for: semester)
            invalidateSubjectCache(for: cacheKey)

            presentSubjectEditSheet = false
            loadingState = .success
            
                self.masterViewModel.showAlert = true
                self.masterViewModel.alertTitle = "Subject Updated"
                self.masterViewModel.alertMessage = "\(subjectName) was successfully updated."
            
            // Clear form and close sheet
            clearForm()
            clearEditingState()
            
            logger.info("✅ Subject updated successfully: \(updatedSubject.subjectName ?? "unnamed")")
            return updatedSubject
            
        } catch {
            let wrappedError = await wrapError(error, context: "updating subject")
            await handleError(wrappedError, operation: "update subject")
            throw wrappedError
        }
    }
    
    // MARK: Delete Subject
    func deleteSubject(_ subject: Subject) async throws {
        guard let subjectId = subject.subjectId else {
            let error = SubjectViewModelError.subjectNotFound("Invalid subject ID")
            await handleError(error, operation: "delete subject")
            throw error
        }
        
        logger.info("🗑️ Deleting subject: \(subject.subjectName ?? "unnamed")")
        loadingState = .loading
        
        do {
            try await withTimeout(operationTimeout) {
                try await self.repository.deleteSubject(subjectId: subjectId)
            }
            // Invalidate cache (we don't have semester context, so clear all subject cache)
            subjectCache.removeAll()
            subjectCacheTimestamp.removeAll()
            logger.debug("🗑️ Cleared all subject cache due to deletion")

            // Update local state
            subjectsList.removeAll { $0.subjectId == subjectId }
            
            // Clear editing state if this was the subject being edited
            if editingSubject?.subjectId == subjectId {
                clearEditingState()
            }
            
            loadingState = .success
            
            await showSuccess(title: "Subject Deleted", message: "'\(subject.subjectName ?? "Subject")' has been deleted successfully.")
            
            logger.info("✅ Subject deleted successfully: \(subject.subjectName ?? "unnamed")")
            
        } catch {
            let wrappedError = await wrapError(error, context: "deleting subject")
            await handleError(wrappedError, operation: "delete subject")
            throw wrappedError
        }
    }
    
    // MARK: Refresh Data
    func refreshData(semester: Semester?) async {
        logger.info("🔄 Refreshing subject data...")
        loadingState = .loading
        
        do {
            try await loadSubjects(semester: semester)
            loadingState = .success
            await showSuccess(title: "Data Refreshed", message: "Subject data has been updated.")
        } catch {
            logger.error("❌ Failed to refresh data: \(error.localizedDescription)")
            await handleError(error, operation: "refresh data", showRetry: true)
        }
    }
    
    // MARK: - Edit Management
    func startEditing(_ subject: Subject) {
        logger.info("✏️ Starting to edit subject: \(subject.subjectName ?? "unnamed")")
        editingSubject = subject
        
        // Populate form with current values
        subjectName = subject.subjectName ?? ""
        subjectTeacher = subject.subjectTeacher ?? ""
        subjectColor = subject.subjectColor ?? "Blue"
        subjectIcon = subject.subjectIcon ?? "book.fill"
        presentSubjectEditSheet = true
    }
    
    func cancelEditing() {
        logger.info("❌ Cancelling subject editing")
        editingSubject = nil
        clearForm()
        clearEditingState()
        presentSubjectEditSheet = false
    }
    
    private func clearEditingState() {
        editingSubject = nil
    }
    
    // MARK: - Validation Methods
    private func validateSubjectData() async throws {
        logger.debug("🔍 Validating subject data...")
        
        let trimmedName = subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTeacher = subjectTeacher.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedName.isEmpty else {
            throw SubjectViewModelError.validationFailed("Subject name cannot be empty")
        }
        
        guard trimmedName.count >= 2 else {
            throw SubjectViewModelError.validationFailed("Subject name must be at least 2 characters long")
        }
        
        guard trimmedName.count <= 50 else {
            throw SubjectViewModelError.validationFailed("Subject name cannot exceed 50 characters")
        }
        
        guard !trimmedTeacher.isEmpty else {
            throw SubjectViewModelError.validationFailed("Teacher name cannot be empty")
        }
        
        guard trimmedTeacher.count >= 2 else {
            throw SubjectViewModelError.validationFailed("Teacher name must be at least 2 characters long")
        }
        
        guard trimmedTeacher.count <= 50 else {
            throw SubjectViewModelError.validationFailed("Teacher name cannot exceed 50 characters")
        }
        
        guard availableColors.contains(subjectColor) else {
            throw SubjectViewModelError.validationFailed("Please select a valid color")
        }
        
        guard availableIcons.contains(subjectIcon) else {
            throw SubjectViewModelError.validationFailed("Please select a valid icon")
        }
        
        logger.debug("✅ Subject data validation passed")
    }
    
    // MARK: - Error Handling
    private func wrapError(_ error: Error, context: String) async -> SubjectViewModelError {
        if let subjectError = error as? SubjectViewModelError {
            return subjectError
        }
        
        if let repositoryError = error as? SubjectRepositoryError {
            switch repositoryError {
            case .subjectNotFound(let details):
                return .subjectNotFound(details)
            case .semesterNotFound(let details):
                return .semesterNotFound(details)
            case .duplicateSubjectName(let name):
                return .duplicateName(name)
            case .invalidSubjectData(let details):
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
                throw SubjectViewModelError.operationTimeout
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    // MARK: - Utility Methods
    func clearForm() {
        subjectName = ""
        subjectTeacher = ""
        subjectColor = "Blue"
        subjectIcon = "character.book.closed"
        logger.debug("🧹 Subject form cleared")
    }
    
    func clearAlerts() {
        showErrorAlert = false
        showSuccessAlert = false
        alertTitle = ""
        alertMessage = ""
        showRetryOption = false
    }
    
    // MARK: - Query Methods
    func getSubject(by id: UUID) async throws -> Subject? {
        return try await repository.getSubjectById(id)
    }
    
    func getSubjectsCount() -> Int {
        return subjectsList.count
    }
    
    func hasSubjects() -> Bool {
        return !subjectsList.isEmpty
    }

    var isFormValid: Bool {
        let trimmedName = subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTeacher = subjectTeacher.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return !trimmedName.isEmpty &&
               trimmedName.count >= 2 &&
               trimmedName.count <= 50 &&
               !trimmedTeacher.isEmpty &&
               trimmedTeacher.count >= 2 &&
               trimmedTeacher.count <= 50 &&
               availableColors.contains(subjectColor) &&
               availableIcons.contains(subjectIcon)
    }
    
    var canUpdateSubject: Bool {
        isFormValid && !loadingState.isLoading && editingSubject != nil
    }
    
    var isEditing: Bool {
        editingSubject != nil
    }
    
    // MARK: - Deinitializer
    deinit {
        logger.info("🔄 SubjectViewModel deinitialized")
    }
}
