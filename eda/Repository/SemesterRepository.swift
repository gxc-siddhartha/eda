//
//  SemesterRepository.swift
//  eda
//
//  Created by Siddhartha Srivastava on 12/07/25.
//
import CoreData
import Foundation
import os.log

extension UserDefaults {
    private enum Keys {
        static let selectedSemesterID = "selectedSemesterID"
    }
    
    var selectedSemesterID: UUID? {
        get {
            guard let uuidString = string(forKey: Keys.selectedSemesterID) else { return nil }
            return UUID(uuidString: uuidString)
        }
        set {
            if let uuid = newValue {
                set(uuid.uuidString, forKey: Keys.selectedSemesterID)
            } else {
                removeObject(forKey: Keys.selectedSemesterID)
            }
        }
    }
}
struct SemesterData {
    let name: String
    let startDate: Date
    let endDate: Date
    let passingPercentage: String?
}

class SemesterRepository {
    private let persistentContainer: NSPersistentContainer
    private let backgroundContext: NSManagedObjectContext
    private let logger = Logger(subsystem: "com.eda.app", category: "SemesterRepository")
    
    init(persistentContainer: NSPersistentContainer = PersistenceController.shared.container) {
        self.persistentContainer = persistentContainer
        self.backgroundContext = persistentContainer.newBackgroundContext()
        self.backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
    
    func createSemester(semesterData: SemesterData) async throws -> Semester {
        self.logger.debug("📚 Creating semester: \(semesterData.name)")
        
        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    // Create new semester
                    let newSemester = Semester(context: self.backgroundContext)
                    newSemester.semesterName = semesterData.name
                    newSemester.semesterStartDate = semesterData.startDate
                    newSemester.semesterEndDate = semesterData.endDate
                    newSemester.passingPercentage = semesterData.passingPercentage
                    newSemester.semesterId = UUID()
                    
                    // Save background context
                    try self.backgroundContext.save()
                    
                    // Get object in main context
                    let mainContextSemester = try self.persistentContainer.viewContext.existingObject(with: newSemester.objectID) as! Semester
                    
                    self.logger.info("✅ Semester created successfully: \(semesterData.name)")
                    continuation.resume(returning: mainContextSemester)
                    
                } catch {
                    self.logger.error("❌ Failed to create semester: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func updateSemester(semesterId: UUID, semesterData: SemesterData) async throws -> Semester {
        self.logger.debug("📝 Updating semester: \(semesterId.uuidString)")
        
        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {

                    let fetchRequest: NSFetchRequest<Semester> = Semester.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "semesterId == %@", semesterId as CVarArg)
                    fetchRequest.fetchLimit = 1
                    
                    let semesters = try self.backgroundContext.fetch(fetchRequest)
                    guard let semester = semesters.first else {
                        self.logger.error("Error updating semester: Semester not found with the id: \(semesterId.uuidString) and name: \(semesterData.name)")
                        return
                    }
                
                    semester.semesterEndDate = semesterData.endDate
                    semester.passingPercentage = semesterData.passingPercentage
              
                    try self.backgroundContext.save()
                    
       
                    let mainContextSemester = try self.persistentContainer.viewContext.existingObject(with: semester.objectID) as! Semester
                    
                    self.logger.info("✅ Semester updated successfully: \(semesterData.name)")
                    continuation.resume(returning: mainContextSemester)
                    
                } catch {
                    self.logger.error("❌ Failed to update semester: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func deleteSemester(semesterId: UUID) async throws {
        self.logger.debug("🗑️ Deleting semester: \(semesterId.uuidString)")
        
        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    // Find semester in background context
                    let fetchRequest: NSFetchRequest<Semester> = Semester.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "semesterId == %@", semesterId as CVarArg)
                    fetchRequest.fetchLimit = 1
                    
                    let semesters = try self.backgroundContext.fetch(fetchRequest)
                    guard let semester = semesters.first else {
                        self.logger.warning("⚠️ Semester not found: \(semesterId.uuidString)")
                        return
                    }
                    

                    self.backgroundContext.delete(semester)

                    try self.backgroundContext.save()
                    
                    self.logger.info("✅ Semester deleted successfully: \(semesterId.uuidString)")
                    continuation.resume()
                    
                } catch {
                    self.logger.error("❌ Failed to delete semester: \(error.localizedDescription)")
              
                }
            }
        }
    }
    

    func updateSelectedSemester(_ semester: Semester) async throws {
        self.logger.debug("🎯 Updating selected semester in UserDefaults: \(semester.semesterName ?? "unknown")")
        
        guard let semesterId = semester.semesterId else {
            self.logger.error("❌ Failed to update selected semester: Missing semester ID")
            return
        }

        await MainActor.run {
            UserDefaults.standard.selectedSemesterID = semesterId
        }
        
        self.logger.info("✅ Selected semester updated in UserDefaults: \(semester.semesterName ?? "unknown")")
    }
    
    func getAllSemesters() async throws -> [Semester] {

        
        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    let fetchRequest: NSFetchRequest<Semester> = Semester.fetchRequest()
                    
                    // Sort by name
                    fetchRequest.sortDescriptors = [
                        NSSortDescriptor(key: "semesterName", ascending: true)
                    ]
                    
                    let backgroundSemesters = try self.backgroundContext.fetch(fetchRequest)
                    
                    // Convert to main context objects
                    let mainContextSemesters = try backgroundSemesters.map { semester in
                        try self.persistentContainer.viewContext.existingObject(with: semester.objectID) as! Semester
                    }
                    
                    self.logger.info("✅ Fetched \(mainContextSemesters.count) semesters")
                    continuation.resume(returning: mainContextSemesters)
                    
                } catch {
                    self.logger.error("❌ Failed to fetch semesters: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func getSemesterById(_ id: UUID) async throws -> Semester? {
        self.logger.debug("🔍 Fetching semester by ID: \(id.uuidString)")
        
        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    let fetchRequest: NSFetchRequest<Semester> = Semester.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "semesterId == %@", id as CVarArg)
                    fetchRequest.fetchLimit = 1
                    
                    let backgroundSemesters = try self.backgroundContext.fetch(fetchRequest)
                    
                    if let backgroundSemester = backgroundSemesters.first {
          
                        let mainContextSemester = try self.persistentContainer.viewContext.existingObject(with: backgroundSemester.objectID) as! Semester
                        
                        self.logger.info("✅ Found semester: \(mainContextSemester.semesterName ?? "unnamed")")
                        continuation.resume(returning: mainContextSemester)
                    } else {
                        self.logger.info("ℹ️ No semester found with ID: \(id.uuidString)")
                        continuation.resume(returning: nil)
                    }
                    
                } catch {
                    self.logger.error("❌ Failed to fetch semester by ID: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func getSelectedSemester() async throws -> Semester? {
        self.logger.debug("🎯 Fetching selected semester from UserDefaults")

        guard let selectedSemesterID = await MainActor.run(body: {
            return UserDefaults.standard.selectedSemesterID
        }) else {
            self.logger.info("ℹ️ No selected semester found in UserDefaults")
            return nil
        }
        
        self.logger.debug("📚 Found selected semester ID: \(selectedSemesterID.uuidString)")
        

        return try await getSemesterById(selectedSemesterID)
    }

    func checkForDuplicateSemesterName(_ name: String) async throws -> Bool {
        self.logger.debug("🔍 Checking for duplicate semester name: \(name)")
        
        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    let fetchRequest: NSFetchRequest<Semester> = Semester.fetchRequest()
                    fetchRequest.predicate = NSPredicate(
                        format: "semesterName == %@",
                        name.trimmingCharacters(in: .whitespacesAndNewlines),
                    )
                    
                    fetchRequest.fetchLimit = 1
                    
                    let existingSemesters = try self.backgroundContext.fetch(fetchRequest)
                    let isDuplicate = !existingSemesters.isEmpty
                    
                    self.logger.debug("📊 Duplicate check result: \(isDuplicate)")
                    continuation.resume(returning: isDuplicate)
                } catch {
                    self.logger.error("❌ Failed to check for duplicate: \(error.localizedDescription)")
                }
            }
        }
    }
}
