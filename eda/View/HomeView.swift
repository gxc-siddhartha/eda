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
    
    @State private var presentConfirmationDialog : Bool = false
    
    var body: some View {
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
                    ForEach(subjectViewModel.subjectsList, id: \.subjectId) { subject in
                        NavigationLink(destination: AttendanceView(subject: subject)) {
                            SubjectsListItem(subject: subject)

                        }.padding(.trailing, 16)
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
            }
            
            
                Button("Add Attendance Log") {
                    attendanceViewModel.presentAttendanceCreateSheet = true
                }
            
        }
        .task {
            // Initialize if not already done
            if !semesterViewModel.isInitialized {
                await semesterViewModel.initialize()
            }
            
            if(!subjectViewModel.isInitialized) {
                if(semesterViewModel.selectedSemesterForUser != nil ){
                    await subjectViewModel.initialize(with: semesterViewModel.selectedSemesterForUser!)
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
