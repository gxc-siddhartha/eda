//
//  edaApp.swift
//  eda
//
//  Created by Siddhartha Srivastava on 12/07/25.
//

import SwiftUI

@main
struct edaApp: App {
    let persistenceController = PersistenceController.shared
    private let semesterRepository = SemesterRepository()
    private let subjectRepository = SubjectRepository()
    @StateObject private var masterViewModel = MasterViewModel()
    
    @StateObject private var semesterViewModel = SemesterViewModel()
    @StateObject private var subjectViewModel = SubjectViewModel()
    @StateObject private var scheduleViewModel = ScheduleViewModel()
    @StateObject private var attendanceViewModel = AttendanceViewModel()
    

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)

                .environmentObject(semesterViewModel)
                .environmentObject(subjectViewModel)
                .environmentObject(scheduleViewModel)
                .environmentObject(attendanceViewModel)
                .task {
                    await semesterViewModel.initialize()
                    if(semesterViewModel.selectedSemesterForUser != nil) {
                        await subjectViewModel.initialize(with: semesterViewModel.selectedSemesterForUser!)
                        if(!subjectViewModel.subjectsList.isEmpty) {
                            await scheduleViewModel.initialize(with: semesterViewModel.selectedSemesterForUser!)
                        }
                    }
                    
                    // ✅ ADD THIS - Notification initialization
                       await NotificationAppLaunchHelper.initializeNotificationsOnAppLaunch(
                           semesterViewModel: semesterViewModel,
                           subjectViewModel: subjectViewModel
                       )
                }
        }
    }
}
