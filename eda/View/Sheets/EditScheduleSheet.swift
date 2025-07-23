//
//  CreateSemesterSheet.swift
//  eda
//
//  Created by Siddhartha Srivastava on 12/07/25.
//

import SwiftUI

struct EditScheduleSheet: View {
    @EnvironmentObject var semesterViewModel: SemesterViewModel
    @EnvironmentObject var subjectViewModel: SubjectViewModel
    @EnvironmentObject var scheduleViewModel: ScheduleViewModel

    var body: some View {
        NavigationStack {
            List {
                Section("Subject Details") {
                    Picker(
                        "Select Subject",
                        selection: $scheduleViewModel.selectedSubject
                    ) {
                        ForEach(subjectViewModel.subjectsList, id: \.subjectId)
                        { subject in
                            Text(subject.subjectName ?? "")
                                .tag(Optional(subject))
                        }

                    }.pickerStyle(.menu).disabled(true)
                }

                Section("Semester Details") {
                    Picker(
                        "Select Day",
                        selection: $scheduleViewModel.scheduleDay
                    ) {
                        ForEach(scheduleViewModel.availableDays, id: \.self) {
                            day in
                            Text(day)

                        }
                    }
                    HStack {
                        Text("Location")
                            .padding(.trailing)
                        TextField(
                            "San Jose Public Library",
                            text: $scheduleViewModel.scheduleLocation
                        )
                    }

                    DatePicker(
                        "Start Time",
                        selection: $scheduleViewModel.scheduleStartTime,
                        displayedComponents: .hourAndMinute
                    )
                    DatePicker(
                        "End Time",
                        selection: $scheduleViewModel.scheduleEndTime,
                        displayedComponents: .hourAndMinute
                    )
                }
            }.navigationTitle(Text("Edit Schedule"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackgroundVisibility(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task {
                                _ = try await scheduleViewModel.updateSchedule(
                                    semester: semesterViewModel
                                        .selectedSemesterForUser
                                )
                                try await scheduleViewModel
                                    .loadSchedulesForScheduleView(
                                        for: scheduleViewModel.selectedDate,
                                        semester: semesterViewModel
                                            .selectedSemesterForUser
                                    )
                            }
                        } label: {
                            Text("Done").bold()
                        }
                    }

                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            scheduleViewModel.presentScheduleEditSheet = false
                            scheduleViewModel.clearForm()
                            scheduleViewModel.clearAlerts()
                        } label: {
                            Text("Close")
                        }
                    }
                }
                .alert(
                    isPresented: $scheduleViewModel.showErrorAlert,
                    content: {
                        Alert(
                            title: Text( scheduleViewModel.alertTitle),
                            message: Text(scheduleViewModel.alertMessage),
                            dismissButton: .default(Text("Ok"))
                        )
                    }
                )

        }
    }
}

#Preview {
    EditScheduleSheet().environmentObject(SubjectViewModel())
        .environmentObject(SemesterViewModel())
        .environmentObject(ScheduleViewModel(repository: ScheduleRepository()))
}
