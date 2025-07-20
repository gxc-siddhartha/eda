//
//  CreateAttendanceSheet.swift
//  eda
//
//  Created by Siddhartha Srivastava on 13/07/25.
//

import SwiftUI

struct CreateAttendanceSheet: View {
    @EnvironmentObject var semesterViewModel: SemesterViewModel
    @EnvironmentObject var subjectViewModel: SubjectViewModel
    @EnvironmentObject var scheduleViewModel: ScheduleViewModel
    @EnvironmentObject var attendanceViewModel: AttendanceViewModel

    @State private var isLoadingSchedules = false

    var body: some View {
        NavigationStack {
            List {
                Section("Subject Selection") {
                    Picker(selection: $attendanceViewModel.selectedSubject) {
                        ForEach(subjectViewModel.subjectsList, id: \.subjectId)
                        { subject in
                            Text(subject.subjectName ?? "Unknown Subject")
                                .tag(Optional(subject))
                        }
                    } label: {
                        Text("Subject").fontWeight(Font.Weight.semibold)
                    }.pickerStyle(.inline)
                        .onChange(of: attendanceViewModel.selectedSubject) {
                            old,
                            newSubject in
                            Task {
                                try await loadSchedulesForSubject(newSubject)

                            }
                        }
                }

                if let selectedSubject = attendanceViewModel.selectedSubject {
                    Section("Schedule Selection") {
                        if attendanceViewModel.schedulesForSubject.isEmpty {
                            HStack {
                                Text(
                                    "No schedules found for \(selectedSubject.subjectName ?? "this subject")"
                                )
                                .foregroundStyle(.secondary)
                            }
                        } else {
                            Picker(
                                selection: $attendanceViewModel.selectedSchedule
                            ) {
                                ForEach(
                                    attendanceViewModel.schedulesForSubject,
                                    id: \.scheduleId
                                ) { schedule in
                                    HStack(alignment: .top) {
                                        Text(
                                            "\(schedule.scheduleDay ?? "Unknown Day"),"
                                        )

                                        if let startTime = schedule
                                            .scheduleStartTime,
                                            let endTime = schedule
                                                .scheduleEndTime
                                        {
                                            Text(
                                                "\(startTime.formatted(date: .omitted, time: .shortened)) - \(endTime.formatted(date: .omitted, time: .shortened))"
                                            )
                                            .foregroundStyle(.secondary)
                                        }
                                    }
                                    .tag(Optional(schedule))
                                }
                            } label: {
                                Text("Schedule").fontWeight(
                                    Font.Weight.semibold
                                )
                            }
                            .pickerStyle(.inline)
                            .onChange(of: attendanceViewModel.selectedSchedule)
                            { oldValue, newValue in
                                // Debug log when schedule changes
                                if let schedule = newValue {
                                    print(
                                        "🔍 DEBUG: Schedule selected - \(schedule.scheduleDay ?? "Unknown") at \(schedule.scheduleStartTime?.formatted(date: .omitted, time: .shortened) ?? "Unknown time")"
                                    )

                                    // Ensure times are properly set
                                    if let startTime = schedule
                                        .scheduleStartTime,
                                        let endTime = schedule.scheduleEndTime
                                    {
                                        attendanceViewModel
                                            .attendanceStartTime = startTime
                                        attendanceViewModel.attendanceEndTime =
                                            endTime
                                        print(
                                            "🔍 DEBUG: Times updated - Start: \(startTime.formatted(date: .omitted, time: .shortened)), End: \(endTime.formatted(date: .omitted, time: .shortened))"
                                        )
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Attendance Details") {
                    DatePicker(
                        "Attendance Date",
                        selection: $attendanceViewModel.attendanceDate,
                        displayedComponents: .date
                    ).datePickerStyle(.compact)

                    Picker(
                        "Type",
                        selection: $attendanceViewModel.attendanceType
                    ) {
                        ForEach(
                            attendanceViewModel.availableAttendanceTypes,
                            id: \.self
                        ) { type in
                            Text(type).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(height: 22)

                    Picker(
                        "Status",
                        selection: $attendanceViewModel.attendancePresent
                    ) {
                        ForEach(
                            attendanceViewModel.availablePresenceStatus,
                            id: \.self
                        ) { status in
                            HStack {
                                Text(status).tag(status)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .pickerStyle(.menu)
                    .frame(height: 22)

                    if attendanceViewModel.attendanceType == "Event" {
                        HStack(spacing: 16) {
                            Text("Event Name").lineLimit(1)
                            TextField(
                                "Morning Lecture",
                                text: $attendanceViewModel.attendanceEvent
                            )
                            .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
            .navigationTitle(Text("Create Attendance"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            if attendanceViewModel.isFormValid {
                                do {
                                    _ =
                                        try await attendanceViewModel
                                        .createAttendance()
                                } catch {
                                    print(
                                        "Error creating attendance: \(error.localizedDescription)"
                                    )
                                }
                            }
                        }
                    } label: {
                        Text("Done")
                    }
                    .disabled(!attendanceViewModel.isFormValid)
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        attendanceViewModel.clearForm()
                        attendanceViewModel.presentAttendanceCreateSheet = false
                    } label: {
                        Text("Close")
                    }
                }
            }
            .alert(isPresented: $attendanceViewModel.showErrorAlert) {
                Alert(
                    title: Text(attendanceViewModel.alertTitle),
                    message: Text(attendanceViewModel.alertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }

            .onAppear {
                Task {
                    // Set default values if not already set
                    if attendanceViewModel.attendanceType.isEmpty {
                        attendanceViewModel.attendanceType =
                            attendanceViewModel.availableAttendanceTypes.first
                            ?? "Theory"
                    }
                    if attendanceViewModel.attendancePresent.isEmpty {
                        attendanceViewModel.attendancePresent = "Present"
                    }

                    // Clear any previous selections to ensure fresh state
                    attendanceViewModel.selectedSubject = nil
                    attendanceViewModel.selectedSchedule = nil
                    attendanceViewModel.schedulesForSubject = []

                    // Reset times to neutral values
                    let calendar = Calendar.current
                    let startOfDay = calendar.startOfDay(for: Date())
                    attendanceViewModel.attendanceStartTime =
                        calendar.date(byAdding: .hour, value: 9, to: startOfDay)
                        ?? startOfDay
                    attendanceViewModel.attendanceEndTime =
                        calendar.date(
                            byAdding: .hour,
                            value: 10,
                            to: startOfDay
                        ) ?? startOfDay
                }
            }
        }
    }

    // MARK: - Private Methods

    private func loadSchedulesForSubject(_ subject: Subject?) async throws {
        guard let subject = subject,
            let subjectId = subject.subjectId
        else {
            attendanceViewModel.schedulesForSubject = []
            attendanceViewModel.selectedSchedule = nil
            return
        }

        isLoadingSchedules = true

        Task {
            do {
                let schedules =
                    try await scheduleViewModel.getSchedulesForSubject(
                        subjectId
                    )

                await MainActor.run {
                    attendanceViewModel.schedulesForSubject = schedules
                    // Clear selected schedule when subject changes
                    attendanceViewModel.selectedSchedule = nil
                    isLoadingSchedules = false
                }

            } catch {
                await MainActor.run {
                    print(
                        "Error loading schedules for subject: \(error.localizedDescription)"
                    )
                    attendanceViewModel.schedulesForSubject = []
                    attendanceViewModel.selectedSchedule = nil
                    isLoadingSchedules = false
                }
            }
        }
    }
}

#Preview {
    CreateAttendanceSheet()
        .environmentObject(SemesterViewModel())
        .environmentObject(SubjectViewModel())
        .environmentObject(ScheduleViewModel())
        .environmentObject(AttendanceViewModel())
}
