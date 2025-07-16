//
//  HomeView.swift
//  eda
//
//  Created by Siddhartha Srivastava on 12/07/25.
//

import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject var scheduleViewModel: ScheduleViewModel
    @EnvironmentObject var semesterViewModel: SemesterViewModel
    
    var body: some View {
        
        List {
            DatePicker("Select Date", selection: $scheduleViewModel.selectedDate, displayedComponents: .date, )
                .onChange(of: scheduleViewModel.selectedDate) {oldDate, newDate in
                    if(semesterViewModel.selectedSemesterForUser != nil) {
                        Task {
                            try await scheduleViewModel.loadSchedulesForScheduleView(for: scheduleViewModel.selectedDate, semester: semesterViewModel.selectedSemesterForUser)
                        }
                    }
                }
                .datePickerStyle(.graphical)
                
                
            
            Section {
                ForEach(scheduleViewModel.schedulesForSelectedDate, id: \.scheduleId) {schedule in
                    NavigationLink(destination: AttendanceView(subject: schedule.subject!),){
                        ScheduleViewListItem(schedule: schedule).listRowSeparator(.hidden)
                            
                    }.padding(.trailing)
                }
                
            }.listRowInsets(EdgeInsets())
        }.listStyle(.plain)
            .navigationTitle(Text("Schedules")).navigationBarTitleDisplayMode(.large)
            .onAppear {
                if(semesterViewModel.selectedSemesterForUser != nil) {
                    Task {
                        try await scheduleViewModel.loadSchedulesForScheduleView(for: scheduleViewModel.selectedDate, semester: semesterViewModel.selectedSemesterForUser)
                    }
                }
                
            }
            
        
    }
}

#Preview {
    ScheduleView()
        .environmentObject(ScheduleViewModel())
}
