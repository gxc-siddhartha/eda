//
//  ContentView.swift
//  eda
//
//  Created by Siddhartha Srivastava on 12/07/25.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @StateObject private var masterViewModel: MasterViewModel = MasterViewModel.shared
    
    @EnvironmentObject private var semesterViewModel: SemesterViewModel
    @EnvironmentObject private var subjectViewModel: SubjectViewModel
    @EnvironmentObject private var scheduleViewModel: ScheduleViewModel
    @EnvironmentObject private var attendanceViewModel: AttendanceViewModel
    
    @Environment(\.scenePhase) private var scenePhase
    
  
    var body: some View {
        
        TabView {
            NavigationStack {
                HomeView()
                
            }.tabItem {
                Image(systemName: "rectangle.3.group.fill")
                Text("Home")
            }
            
            NavigationStack{
                
                ScheduleView()
                
            } .tabItem {
                Image(systemName: "calendar")
                Text("Schedules")
            }
        }
        .sheet(isPresented: $semesterViewModel.presentSemesterDetailsSheet ){
            CreateSemesterSheet()
                .presentationDragIndicator(.visible)
        }.sheet(isPresented: $subjectViewModel.presentSubjectCreateSheet ){
            CreateSubjectSheet()
                .presentationDragIndicator(.visible)
            
        }
        
        .sheet(isPresented: $scheduleViewModel.presentScheduleCreateSheet ){
            CreateScheduleSheet()
                .presentationDragIndicator(.visible)
            
        }
        .sheet(isPresented: $attendanceViewModel.presentAttendanceCreateSheet ){
            CreateAttendanceSheet()
                .presentationDragIndicator(.visible)
            
        }
        .sheet(isPresented: $subjectViewModel.presentSubjectEditSheet ){
            EditSubjectSheet()
                .presentationDragIndicator(.visible)
            
        }
        .sheet(isPresented: $semesterViewModel.presentManageSemestersSheet ){
            ManageSemesterSheet()
                .presentationDragIndicator(.visible)
            
        }
        .alert(isPresented: $masterViewModel.showAlert) {
            Alert(
                title: Text(masterViewModel.alertTitle),
                message: Text(masterViewModel.alertMessage),
                dismissButton: .default(Text("Okay").bold())
            )
        }
        

    }
}
#Preview {
    ContentView()
        .environmentObject(SubjectViewModel()).environmentObject(SemesterViewModel())
        .environmentObject(ScheduleViewModel())
        .environmentObject(AttendanceViewModel())
}
