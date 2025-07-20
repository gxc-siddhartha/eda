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
    
    @State private var showDeleteScheduleAlert: Bool = false
    @State private var scheduleToDelete: Schedule? = nil
    
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
                   
                        ScheduleViewListItem(schedule: schedule).listRowSeparator(.hidden)
                        .padding(.trailing)
                        .swipeActions(edge: .leading) {
                            Button {
                                scheduleViewModel.startEditing(schedule)
                                scheduleViewModel.presentScheduleEditSheet = true
                            } label: {
                                Text("Edit")
                            }
                            .tint(.accentColor)
                            
                            Button {
                                showDeleteScheduleAlert = true
                                scheduleToDelete = schedule
                            } label: {
                                Text("Delete")
                            }
                            .tint(.red)
                        }
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
            .alert(isPresented: $showDeleteScheduleAlert) {
                            Alert(
                                title: Text("Delete Schedule"),
                                message: Text("This will also remove all the attendances for this schedule. Are you sure you want to delete this schedule?"),
                                primaryButton: .destructive(Text("Delete")) {
                                    Task {
                                        do {
                                            try await scheduleViewModel.deleteSchedule(scheduleToDelete!)
                                            try await scheduleViewModel.loadSchedulesForScheduleView(for: scheduleViewModel.selectedDate, semester: semesterViewModel.selectedSemesterForUser!)
                                            
                                        } catch {
                                            // handle error if needed
                                        }
                                        showDeleteScheduleAlert = false
                                    }
                                },
                                secondaryButton: .cancel(Text("Cancel")) {
                                    showDeleteScheduleAlert = false
                                }
                            )
                        }
            
        
    }
}

#Preview {
    ScheduleView()
        .environmentObject(ScheduleViewModel())
}
