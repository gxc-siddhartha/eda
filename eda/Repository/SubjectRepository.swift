//
//  SubjectRepository.swift
//  eda
//
//  Created by Siddhartha Srivastava on 12/07/25.
//

import CoreData
import Foundation
import os.log

// MARK: - Data Transfer Objects
struct SubjectData {
    let name: String
    let teacher: String
    let color: String
    let icon: String?
}

// MARK: - Subject Repository Error Types
enum SubjectRepositoryError: LocalizedError {
    case subjectNotFound(String)
    case semesterNotFound(String)
    case invalidSubjectData(String)
    case coreDataError(String)
    case duplicateSubjectName(String)
    
    var errorDescription: String? {
        switch self {
        case .subjectNotFound(let details):
            return "Subject not found: \(details)"
        case .semesterNotFound(let details):
            return "Semester not found: \(details)"
        case .invalidSubjectData(let details):
            return "Invalid subject data: \(details)"
        case .coreDataError(let details):
            return "Core Data error: \(details)"
        case .duplicateSubjectName(let name):
            return "A subject named '\(name)' already exists in this semester"
        }
    }
}

// MARK: - Core Data Repository Implementation
class SubjectRepository {
    private let persistentContainer: NSPersistentContainer
    private let backgroundContext: NSManagedObjectContext
    private let logger = Logger(subsystem: "com.eda.app", category: "SubjectRepository")
    
    init(persistentContainer: NSPersistentContainer = PersistenceController.shared.container) {
        self.persistentContainer = persistentContainer
        self.backgroundContext = persistentContainer.newBackgroundContext()
        self.backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
    
    // MARK: - Create Subject
    func createSubject(subjectData: SubjectData, for semester: Semester) async throws -> Subject {
        self.logger.debug("📚 Creating subject: \(subjectData.name) for semester: \(semester.semesterName ?? "unknown")")
        
        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    // Get semester in background context
                    guard let backgroundSemester = try? self.backgroundContext.existingObject(with: semester.objectID) as? Semester else {
                        let error = SubjectRepositoryError.semesterNotFound("Semester not found in background context")
                        self.logger.error("❌ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    // Check for duplicate subject name in the same semester
                    let isDuplicate = try self.checkForDuplicateSubjectNameSync(subjectData.name, in: backgroundSemester)
                    if isDuplicate {
                        let error = SubjectRepositoryError.duplicateSubjectName(subjectData.name)
                        self.logger.error("❌ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    // Create new subject
                    let newSubject = Subject(context: self.backgroundContext)
                    newSubject.subjectName = subjectData.name
                    newSubject.subjectTeacher = subjectData.teacher
                    newSubject.subjectColor = subjectData.color
                    newSubject.subjectIcon = subjectData.icon
                    newSubject.subjectId = UUID()
                    
                    // Associate with semester
                    newSubject.semester = backgroundSemester
                    
                    // Save background context
                    try self.backgroundContext.save()
                    
                    // Get object in main context
                    let mainContextSubject = try self.persistentContainer.viewContext.existingObject(with: newSubject.objectID) as! Subject
                    
                    self.logger.info("✅ Subject created successfully: \(subjectData.name) in semester: \(backgroundSemester.semesterName ?? "unknown")")
                    continuation.resume(returning: mainContextSubject)
                    
                } catch let error as SubjectRepositoryError {
                    continuation.resume(throwing: error)
                } catch {
                    let wrappedError = SubjectRepositoryError.coreDataError("Failed to create subject: \(error.localizedDescription)")
                    self.logger.error("❌ \(wrappedError.localizedDescription)")
                    continuation.resume(throwing: wrappedError)
                }
            }
        }
    }
    
    // MARK: - Update Subject
    func updateSubject(subjectId: UUID, subjectData: SubjectData, for semester: Semester) async throws -> Subject {
        self.logger.debug("📝 Updating subject: \(subjectId.uuidString) with name: \(subjectData.name)")
        
        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    // Find subject in background context
                    let fetchRequest: NSFetchRequest<Subject> = Subject.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "subjectId == %@", subjectId as CVarArg)
                    fetchRequest.fetchLimit = 1
                    
                    let subjects = try self.backgroundContext.fetch(fetchRequest)
                    guard let subject = subjects.first else {
                        let error = SubjectRepositoryError.subjectNotFound("Subject with ID \(subjectId.uuidString) not found")
                        self.logger.error("❌ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    // Get semester in background context
                    guard let backgroundSemester = try? self.backgroundContext.existingObject(with: semester.objectID) as? Semester else {
                        let error = SubjectRepositoryError.semesterNotFound("Semester not found in background context")
                        self.logger.error("❌ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    // Check for duplicate subject name in the same semester (excluding current subject)
                    let isDuplicate = try self.checkForDuplicateSubjectNameSync(subjectData.name, in: backgroundSemester, excluding: subject)
                    if isDuplicate {
                        let error = SubjectRepositoryError.duplicateSubjectName(subjectData.name)
                        self.logger.error("❌ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    // Update properties
                    subject.subjectName = subjectData.name
                    subject.subjectTeacher = subjectData.teacher
                    subject.subjectColor = subjectData.color
                    subject.subjectIcon = subjectData.icon
                    subject.semester = backgroundSemester
                    
                    // Save background context
                    try self.backgroundContext.save()
                    
                    // Get updated object in main context
                    let mainContextSubject = try self.persistentContainer.viewContext.existingObject(with: subject.objectID) as! Subject
                    
                    self.logger.info("✅ Subject updated successfully: \(subjectData.name) in semester: \(backgroundSemester.semesterName ?? "unknown")")
                    continuation.resume(returning: mainContextSubject)
                    
                } catch let error as SubjectRepositoryError {
                    continuation.resume(throwing: error)
                } catch {
                    let wrappedError = SubjectRepositoryError.coreDataError("Failed to update subject: \(error.localizedDescription)")
                    self.logger.error("❌ \(wrappedError.localizedDescription)")
                    continuation.resume(throwing: wrappedError)
                }
            }
        }
    }
    
    // MARK: - Delete Subject
    func deleteSubject(subjectId: UUID) async throws {
        self.logger.debug("🗑️ Deleting subject: \(subjectId.uuidString)")
        
        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    // Find subject in background context
                    let fetchRequest: NSFetchRequest<Subject> = Subject.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "subjectId == %@", subjectId as CVarArg)
                    fetchRequest.fetchLimit = 1
                    
                    let subjects = try self.backgroundContext.fetch(fetchRequest)
                    guard let subject = subjects.first else {
                        let error = SubjectRepositoryError.subjectNotFound("Subject with ID \(subjectId.uuidString) not found")
                        self.logger.warning("⚠️ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    let subjectName = subject.subjectName ?? "Unknown Subject"
                    let semesterName = subject.semester?.semesterName ?? "Unknown Semester"
                    
                    // Delete subject (this will cascade delete related schedules if configured)
                    self.backgroundContext.delete(subject)
                    
                    // Save background context
                    try self.backgroundContext.save()
                    
                    self.logger.info("✅ Subject deleted successfully: \(subjectName) from semester: \(semesterName)")
                    continuation.resume()
                    
                } catch let error as SubjectRepositoryError {
                    continuation.resume(throwing: error)
                } catch {
                    let wrappedError = SubjectRepositoryError.coreDataError("Failed to delete subject: \(error.localizedDescription)")
                    self.logger.error("❌ \(wrappedError.localizedDescription)")
                    continuation.resume(throwing: wrappedError)
                }
            }
        }
    }
    
    // MARK: - Additional Helper Methods
    
    func getAllSubjects(for semester: Semester) async throws -> [Subject] {
        self.logger.debug("📚 Fetching all subjects for semester: \(semester.semesterName ?? "unknown")")
        
        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    // Get semester in background context
                    guard let backgroundSemester = try? self.backgroundContext.existingObject(with: semester.objectID) as? Semester else {
                        let error = SubjectRepositoryError.semesterNotFound("Semester not found in background context")
                        self.logger.error("❌ \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    let fetchRequest: NSFetchRequest<Subject> = Subject.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "semester == %@", backgroundSemester)
                    
                    // Sort by name
                    fetchRequest.sortDescriptors = [
                        NSSortDescriptor(key: "subjectName", ascending: true)
                    ]
                    
                    let backgroundSubjects = try self.backgroundContext.fetch(fetchRequest)
                    
                    // Convert to main context objects
                    let mainContextSubjects = try backgroundSubjects.map { subject in
                        try self.persistentContainer.viewContext.existingObject(with: subject.objectID) as! Subject
                    }
                    
                    self.logger.info("✅ Fetched \(mainContextSubjects.count) subjects for semester: \(backgroundSemester.semesterName ?? "unknown")")
                    continuation.resume(returning: mainContextSubjects)
                    
                } catch let error as SubjectRepositoryError {
                    continuation.resume(throwing: error)
                } catch {
                    let wrappedError = SubjectRepositoryError.coreDataError("Failed to fetch subjects: \(error.localizedDescription)")
                    self.logger.error("❌ \(wrappedError.localizedDescription)")
                    continuation.resume(throwing: wrappedError)
                }
            }
        }
    }
    
    func getSubjectById(_ id: UUID) async throws -> Subject? {
        self.logger.debug("🔍 Fetching subject by ID: \(id.uuidString)")
        
        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    let fetchRequest: NSFetchRequest<Subject> = Subject.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "subjectId == %@", id as CVarArg)
                    fetchRequest.fetchLimit = 1
                    
                    let backgroundSubjects = try self.backgroundContext.fetch(fetchRequest)
                    
                    if let backgroundSubject = backgroundSubjects.first {
                        // Convert to main context object
                        let mainContextSubject = try self.persistentContainer.viewContext.existingObject(with: backgroundSubject.objectID) as! Subject
                        
                        self.logger.info("✅ Found subject: \(mainContextSubject.subjectName ?? "unnamed")")
                        continuation.resume(returning: mainContextSubject)
                    } else {
                        self.logger.info("ℹ️ No subject found with ID: \(id.uuidString)")
                        continuation.resume(returning: nil)
                    }
                    
                } catch {
                    let wrappedError = SubjectRepositoryError.coreDataError("Failed to fetch subject by ID: \(error.localizedDescription)")
                    self.logger.error("❌ \(wrappedError.localizedDescription)")
                    continuation.resume(throwing: wrappedError)
                }
            }
        }
    }
    
    // MARK: - Private Utility Methods
    
    private func checkForDuplicateSubjectNameSync(_ name: String, in semester: Semester, excluding excludedSubject: Subject? = nil) throws -> Bool {
        let fetchRequest: NSFetchRequest<Subject> = Subject.fetchRequest()
        
        var predicateComponents: [NSPredicate] = []
        predicateComponents.append(NSPredicate(format: "subjectName ==[c] %@", name.trimmingCharacters(in: .whitespacesAndNewlines)))
        predicateComponents.append(NSPredicate(format: "semester == %@", semester))
        
        if let excludedSubject = excludedSubject {
            predicateComponents.append(NSPredicate(format: "subjectId != %@", excludedSubject.subjectId! as CVarArg))
        }
        
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicateComponents)
        fetchRequest.fetchLimit = 1
        
        let existingSubjects = try backgroundContext.fetch(fetchRequest)
        return !existingSubjects.isEmpty
    }
    
    func checkForDuplicateSubjectName(_ name: String, in semester: Semester, excluding excludedSubjectId: UUID? = nil) async throws -> Bool {
        self.logger.debug("🔍 Checking for duplicate subject name: \(name) in semester: \(semester.semesterName ?? "unknown")")
        
        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    // Get semester in background context
                    guard let backgroundSemester = try? self.backgroundContext.existingObject(with: semester.objectID) as? Semester else {
                        let error = SubjectRepositoryError.semesterNotFound("Semester not found in background context")
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    let fetchRequest: NSFetchRequest<Subject> = Subject.fetchRequest()
                    
                    var predicateComponents: [NSPredicate] = []
                    predicateComponents.append(NSPredicate(format: "subjectName ==[c] %@", name.trimmingCharacters(in: .whitespacesAndNewlines)))
                    predicateComponents.append(NSPredicate(format: "semester == %@", backgroundSemester))
                    
                    if let excludedId = excludedSubjectId {
                        predicateComponents.append(NSPredicate(format: "subjectId != %@", excludedId as CVarArg))
                    }
                    
                    fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicateComponents)
                    fetchRequest.fetchLimit = 1
                    
                    let existingSubjects = try self.backgroundContext.fetch(fetchRequest)
                    let isDuplicate = !existingSubjects.isEmpty
                    
                    self.logger.debug("📊 Duplicate check result for '\(name)': \(isDuplicate)")
                    continuation.resume(returning: isDuplicate)
                    
                } catch {
                    let wrappedError = SubjectRepositoryError.coreDataError("Failed to check for duplicate: \(error.localizedDescription)")
                    self.logger.error("❌ \(wrappedError.localizedDescription)")
                    continuation.resume(throwing: wrappedError)
                }
            }
        }
    }
}
