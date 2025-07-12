//
//  ContentView.swift
//  eda
//
//  Created by Siddhartha Srivastava on 12/07/25.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @EnvironmentObject private var semesterViewModel: SemesterViewModel
    @EnvironmentObject private var subjectViewModel: SubjectViewModel
    @EnvironmentObject private var scheduleViewModel: ScheduleViewModel
    
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
            
            NavigationStack{
                SettingsView()
                
            }.tabItem {
                Image(systemName: "gear")
                Text("Settings")
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
    }
}
#Preview {
    ContentView()
        .environmentObject(SubjectViewModel()).environmentObject(SemesterViewModel())
        .environmentObject(ScheduleViewModel())
}
