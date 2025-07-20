//
//  HomeView.swift
//  eda
//
//  Created by Siddhartha Srivastava on 12/07/25.
//

import SwiftUI
import Foundation
import os.log



struct HomeView: View {
    @EnvironmentObject private var semesterViewModel: SemesterViewModel
    @EnvironmentObject private var subjectViewModel: SubjectViewModel
    @EnvironmentObject private var scheduleViewModel: ScheduleViewModel
    @EnvironmentObject private var attendanceViewModel: AttendanceViewModel
    private var masterViewModel: MasterViewModel = MasterViewModel.shared
    
    @State private var presentConfirmationDialog : Bool = false
    
    @State private var showDeleteSubjectAlert : Bool = false
    @State private var showSemesterDeleteAlert : Bool = false
    
    @State private var selectedSubjectForDeletion : Subject? = nil
    
    private let logger = Logger(subsystem: "com.eda.app", category: "HomeView")

    
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        if(subjectViewModel.subjectsList.isEmpty) {

                VStack {
                    Text("📥").font(.system(size: 60, weight: .bold, design: .default))
                        .padding()
                    if(semesterViewModel.semesterList.isEmpty) {
                        Text("Nothing to show. Add a semester to get started!")
                            .padding(.horizontal)
                            .padding(.bottom)
                        
                        Button("Add Semester") {
                            semesterViewModel.presentSemesterDetailsSheet = true
                        }
                    } else {
                        Text("Nothing to show. Add some subjects to get started!")
                            .padding(.horizontal)
                            .padding(.bottom)
                        
                        Button("Add Subject") {
                            subjectViewModel.presentSubjectCreateSheet = true
                        }
                       
                    }
                 
                }.multilineTextAlignment(.center)
         
                .navigationTitle("My Dashboard")
                .navigationBarTitleDisplayMode(.large)
                .toolbarBackgroundVisibility(.visible, for: .navigationBar)
                .toolbarBackgroundVisibility(.visible, for: .tabBar)
                .toolbar {
                    toolbarContent
                }
                
                .confirmationDialog("Add Components", isPresented: $presentConfirmationDialog) {
                    Button("Add Subject") {
                        subjectViewModel.presentSubjectCreateSheet = true
                    }
                    
                    if(!subjectViewModel.subjectsList.isEmpty) {
                        Button("Add Schedule") {
                            scheduleViewModel.presentScheduleCreateSheet = true
                        }
                        Button("Add Attendance Log") {
                            attendanceViewModel.presentAttendanceCreateSheet = true
                        }
                    }
                    if(!scheduleViewModel.schedulesList.isEmpty) {
                        Button("Add Attendance Log") {
                            attendanceViewModel.presentAttendanceCreateSheet = true
                        }
                    }
                        
                    
                }
        } else {
            List {
                if(!$scheduleViewModel.todaySchedules.isEmpty) {
                    Section("Today's Events") {
                        TodaysEventsItem(todaysSchedules: scheduleViewModel.todaySchedules).listRowInsets(EdgeInsets())
                    }
                }
                
                if(scheduleViewModel.hasActiveSchedule) {
                    Section("Ongoing") {
                        NavigationLink(destination: AttendanceView(subject: scheduleViewModel.currentActiveSchedule!.subject!)){
                            ActiveScheduleItem(schedule: scheduleViewModel.currentActiveSchedule! )
                        }.padding(.trailing, 16)
                    }.listRowInsets(EdgeInsets())
                }

                if(!subjectViewModel.subjectsList.isEmpty) {
                    Section("My Subjects") {
                        ForEach($subjectViewModel.subjectsList.wrappedValue, id: \.subjectId) { subject in
                            NavigationLink(destination: AttendanceView(subject: subject)) {
                                SubjectsListItem(subject: subject)
                            }
                            .padding(.trailing, 16)
                            .swipeActions(edge: .leading) {
                                Button {
                                    subjectViewModel.startEditing(subject)
                                    subjectViewModel.presentSubjectEditSheet = true
                                } label: {
                                    Text("Edit")
                                }
                                .tint(.accentColor)
                                
                                Button {
                                    self.selectedSubjectForDeletion = subject
                                    self.showDeleteSubjectAlert = true
                                } label: {
                                    Text("Delete")
                                }
                                .tint(.red)
                            }
                        }
                        .listRowInsets(EdgeInsets())
                    }
                }
                
                
            }
            .navigationTitle("My Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .tabBar)
            .toolbar {
                toolbarContent
            }
            
            .confirmationDialog("Add Components", isPresented: $presentConfirmationDialog) {
                Button("Add Subject") {
                    subjectViewModel.presentSubjectCreateSheet = true
                }
                
                if(!subjectViewModel.subjectsList.isEmpty) {
                    Button("Add Schedule") {
                        scheduleViewModel.presentScheduleCreateSheet = true
                    }
                    
                            Button("Add Attendance Log") {
                                attendanceViewModel.presentAttendanceCreateSheet = true
                            }
                }
            
                
            }
            .alert(isPresented: $showDeleteSubjectAlert) {
                            Alert(
                                title: Text("Delete Subject"),
                                message: Text("Are you sure you want to delete this subject?"),
                                primaryButton: .destructive(Text("Delete")) {
                                    Task {
                                        do {
                                            try await subjectViewModel.deleteSubject(selectedSubjectForDeletion!)
                                            
                                            // Refresh schedules since subject deletion affects them
                                            if let semester = semesterViewModel.selectedSemesterForUser {
                                                try await scheduleViewModel.loadSchedules(for: Date(), semester: semester)
                                                await scheduleViewModel.checkCurrentlyActiveSchedule(for: semester)
                                            }
                                        } catch {
                                            print("Error deleting subject: \(error)")
                                        }
                                        showDeleteSubjectAlert = false
                                    }
                                },
                                secondaryButton: .cancel(Text("Cancel")) {
                                    showDeleteSubjectAlert = false
                                }
                            )
                        }
            .task {
                if !subjectViewModel.isInitialized {
                    if let semester = semesterViewModel.selectedSemesterForUser {
                        await subjectViewModel.initialize(with: semester)
                    } else if !semesterViewModel.semesterList.isEmpty {
                        let firstSemester = semesterViewModel.semesterList[0]
                        semesterViewModel.selectedSemesterForUser = firstSemester
                        await refreshAllData(for: firstSemester)
                    }
                }
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .active {
                    guard semesterViewModel.selectedSemesterForUser != nil else { return }
                    
                    Task {
                        // Use lightweight refresh for app returns (better UX)
                        await lightweightRefresh()
                    }
                }
            }
                        
        }
        
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Leading toolbar item
        ToolbarItem(placement: .topBarLeading) {
            if semesterViewModel.semesterList.isEmpty || semesterViewModel.selectedSemesterForUser == nil {
                addSemesterButton
            } else {
                semesterSelectionMenu
            }
        }
        
        // Principal (center) toolbar item
        if semesterViewModel.selectedSemesterForUser != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    presentConfirmationDialog = true
                    // Add your action here
                } label: {
                    Image(systemName: "plus")
                }
                
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    masterViewModel.presentImportSheet = true
                    // Add your action here
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                
            }
        }
        
        
        
        
    }
    
    @ViewBuilder
    private var addSemesterButton: some View {
        Button {
            semesterViewModel.presentSemesterDetailsSheet = true
        } label: {
            HStack {
                Text("Add Semester")
                Image(systemName: "plus")
            }
        }
        .disabled(semesterViewModel.loadingState.isLoading)
    }
    
    @ViewBuilder
    private var semesterSelectionMenu: some View {
        Menu {
            ForEach(semesterViewModel.semesterList, id: \.semesterId) { semester in
                Button {
                    Task {
                        await refreshAllData(for: semester)
                        }
                    
                } label: {
                    HStack {
                        Text(semester.semesterName ?? "Unknown Semester")
                        if semester.semesterId == semesterViewModel.selectedSemesterForUser?.semesterId {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            
            Divider()
            
            Button {
                semesterViewModel.presentSemesterDetailsSheet = true
            } label: {
                HStack {
                    Text("Add New Semester")
                    Image(systemName: "plus")
                }
            }
            
            Button {
                semesterViewModel.presentManageSemestersSheet = true
            } label: {
                HStack {
                    Text("Manage Semesters")
                    Image(systemName: "list.bullet")
                }
            }
            
        } label: {
            HStack {
                Text(semesterViewModel.selectedSemesterForUser?.semesterName ?? "Select Semester")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
            }
        }
        .disabled(semesterViewModel.loadingState.isLoading)
    }
    
    // MARK: - Data Loading (ADD THIS ENTIRE SECTION)

    /// Centralized function to refresh all data for a semester in parallel
    private func refreshAllData(for semester: Semester) async {
        logger.debug("🔄 Refreshing all data for semester: \(semester.semesterName ?? "unknown")")
        
        await withTaskGroup(of: Void.self) { group in
            // Load all data in parallel instead of sequential
            group.addTask {
                do {
                    try await semesterViewModel.selectSemester(semester)
                } catch {
                    print("Error selecting semester: \(error)")
                }
            }
            
            group.addTask {
                do {
                    try await subjectViewModel.loadSubjects(semester: semester)
                } catch {
                    print("Error loading subjects: \(error)")
                }
            }
            
            group.addTask {
                do {
                    try await scheduleViewModel.loadSchedules(for: Date(), semester: semester)
                } catch {
                    print("Error loading schedules: \(error)")
                }
            }
            
            group.addTask {
                await scheduleViewModel.checkCurrentlyActiveSchedule(for: semester)
            }
        }
        
        logger.debug("✅ Completed refreshing all data")
    }

    /// Quick refresh for active schedule only (lighter operation)
    private func refreshActiveSchedule() async {
        guard let semester = semesterViewModel.selectedSemesterForUser else { return }
        await scheduleViewModel.checkCurrentlyActiveSchedule(for: semester)
    }

    /// Lightweight data refresh (only if data might be stale)
    private func lightweightRefresh() async {
        guard let semester = semesterViewModel.selectedSemesterForUser else { return }
        
        // Only refresh active schedule (fast operation)
        await refreshActiveSchedule()
        
        // Could add timestamp-based refresh logic here later
    }
}

#Preview {
    TabView {
        NavigationStack {
            HomeView()
        }
        .tabItem {
            Image(systemName: "house.fill")
            Text("Home")
        }
        
        NavigationStack {
            ScheduleView()
        }
        .tabItem {
            Image(systemName: "calendar")
            Text("Schedule")
        }
        

    }
    .environmentObject(SemesterViewModel())
    .environmentObject(SubjectViewModel())
    .environmentObject(ScheduleViewModel())
}

// You'll also need these placeholder views for the preview
