//
//  HomeView.swift
//  eda
//
//  Created by Siddhartha Srivastava on 12/07/25.
//

import SwiftUI
import Foundation


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
                                            
                                            try await scheduleViewModel.loadSchedules(for: Date(), semester: semesterViewModel.selectedSemesterForUser!)
                                
                                              await scheduleViewModel.checkCurrentlyActiveSchedule(for: semesterViewModel.selectedSemesterForUser!)
                                        } catch {
                                            // handle error if needed
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
                if(!subjectViewModel.isInitialized) {
                    if(semesterViewModel.selectedSemesterForUser != nil ){
                        await subjectViewModel.initialize(with: semesterViewModel.selectedSemesterForUser!)
                    } else if(!semesterViewModel.semesterList.isEmpty) {
                        await semesterViewModel.selectedSemesterForUser = semesterViewModel.semesterList[0] 
                    }
                   
                }
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                            if newPhase == .active {
                                // The user has just swiped up / left your app
                                if( semesterViewModel.selectedSemesterForUser != nil) {
                                    Task {
                                        try? await semesterViewModel.selectSemester(semesterViewModel.selectedSemesterForUser!)
                                        try? await subjectViewModel.loadSubjects(semester: semesterViewModel.selectedSemesterForUser!)
                                       
                                          try await scheduleViewModel.loadSchedules(for: Date(), semester: semesterViewModel.selectedSemesterForUser!)
                              
                                            await scheduleViewModel.checkCurrentlyActiveSchedule(for: semesterViewModel.selectedSemesterForUser!)
                                        }
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
                        try? await semesterViewModel.selectSemester(semester)
                        try? await subjectViewModel.loadSubjects(semester: semester)
                        
                       
                          try await scheduleViewModel.loadSchedules(for: Date(), semester: semester)
                       
              
                            await scheduleViewModel.checkCurrentlyActiveSchedule(for: semester)
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
