//
//  CreateSemesterSheet.swift
//  eda
//
//  Created by Siddhartha Srivastava on 12/07/25.
//

import SwiftUI

struct CreateScheduleSheet: View {
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

                    }.pickerStyle(.menu)
                        .onAppear {
                            Task {
                                if !subjectViewModel.subjectsList.isEmpty {
                                    scheduleViewModel.selectedSubject =
                                        subjectViewModel.subjectsList.first
                                }
                            }
                        }

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
            }.navigationTitle(Text("Create Schedule"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackgroundVisibility(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task {
                                if scheduleViewModel.isFormValid {
                                    _ =
                                        try await scheduleViewModel
                                        .createSchedule(
                                            semester: semesterViewModel
                                                .selectedSemesterForUser
                                        )
                                }
                            }
                        } label: {
                            Text("Done").disabled(
                                !scheduleViewModel.isFormValid
                            )
                        }
                    }

                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            scheduleViewModel.presentScheduleCreateSheet = false
                        } label: {
                            Text("Close")
                        }
                    }
                }
                .alert(
                    isPresented: $semesterViewModel.showErrorAlert,
                    content: {
                        Alert(
                            title: Text(semesterViewModel.alertTitle),
                            message: Text(semesterViewModel.alertMessage),
                            dismissButton: .default(Text("Ok"))
                        )
                    }
                )

        }
    }
}

#Preview {
    CreateScheduleSheet().environmentObject(SubjectViewModel())
        .environmentObject(SemesterViewModel())
        .environmentObject(ScheduleViewModel(repository: ScheduleRepository()))
}
