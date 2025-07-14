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
                    Picker( selection: $attendanceViewModel.selectedSubject) {
                        ForEach(subjectViewModel.subjectsList, id: \.subjectId) { subject in
                            HStack {
                                Text(subject.subjectName ?? "Unknown Subject")
                            }
                            .tag(Subject?.some(subject))
                        }
                    } label: {
                        Text("Subject").fontWeight(Font.Weight.semibold)
                    } .pickerStyle(.inline )
                    .onChange(of: attendanceViewModel.selectedSubject) { old, newSubject in
                        Task {
                            try await loadSchedulesForSubject(newSubject)

                        }
                    }
                }
                
                if let selectedSubject = attendanceViewModel.selectedSubject {
                    Section("Schedule Selection") {
                        if isLoadingSchedules {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Loading schedules...")
                                    .foregroundStyle(.secondary)
                            }
                        } else if attendanceViewModel.schedulesForSubject.isEmpty {
                            HStack {
                                Text("No schedules found for \(selectedSubject.subjectName ?? "this subject")")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Picker( selection: $attendanceViewModel.selectedSchedule) {
                                ForEach(attendanceViewModel.schedulesForSubject, id: \.scheduleId) { schedule in
                                    HStack(alignment: .top) {
                                        Text("\(schedule.scheduleDay ?? "Unknown Day"),")
                                            
                                        if let startTime = schedule.scheduleStartTime,
                                           let endTime = schedule.scheduleEndTime {
                                            Text("\(startTime.formatted(date: .omitted, time: .shortened)) - \(endTime.formatted(date: .omitted, time: .shortened))")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .tag(Schedule?.some(schedule))
                                }
                            }label: {
                                Text("Schedule").fontWeight(Font.Weight.semibold)
                            }
                            .pickerStyle(.inline)
                        }
                    }
                }
                
                Section("Attendance Details") {
                    DatePicker("Attendance Date", selection: $attendanceViewModel.attendanceDate, displayedComponents: .date).datePickerStyle(.compact)
                   
                    Picker("Type", selection: $attendanceViewModel.attendanceType) {
                        ForEach(attendanceViewModel.availableAttendanceTypes, id: \.self) { type in
                            Text(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(height:22)
                    
                    Picker("Status", selection: $attendanceViewModel.attendancePresent) {
                        ForEach(attendanceViewModel.availablePresenceStatus, id: \.self) { status in
                            HStack {
                                Text(status)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .pickerStyle(.menu)
                    .frame(height:22)

                    if(attendanceViewModel.attendanceType == "Event") {
                        HStack(spacing: 16) {
                            Text("Event Name").lineLimit(1)
                            TextField("Morning Lecture", text: $attendanceViewModel.attendanceEvent)
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
                                    _ = try await attendanceViewModel.createAttendance()
                                } catch {
                                    print("Error creating attendance: \(error.localizedDescription)")
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
            .alert("Success", isPresented: $attendanceViewModel.showSuccessAlert) {
                Button("OK") {
                    attendanceViewModel.clearAlerts()
                }
            } message: {
                Text(attendanceViewModel.alertMessage)
            }
            .onAppear {
                Task {
                    if attendanceViewModel.attendanceType.isEmpty {
                        attendanceViewModel.attendanceType = attendanceViewModel.availableAttendanceTypes.first ?? "Theory"
                    }
                    if attendanceViewModel.attendancePresent.isEmpty {
                        attendanceViewModel.attendancePresent = "Present"
                    }
                    
//                    // Auto-select first subject if available and none selected
//                    if attendanceViewModel.selectedSubject == nil && !subjectViewModel.subjectsList.isEmpty {
//                        attendanceViewModel.selectedSubject = subjectViewModel.subjectsList.first
//                        // Load schedules for the preselected subject
//                        try await loadSchedulesForSubject(attendanceViewModel.selectedSubject)
//                    }
                }
                // Set default values if not already set
               
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func loadSchedulesForSubject(_ subject: Subject?) async throws{
        guard let subject = subject,
              let subjectId = subject.subjectId else {
            attendanceViewModel.schedulesForSubject = []
            attendanceViewModel.selectedSchedule = nil
            return
        }
        
        isLoadingSchedules = true
        
        Task {
            do {
                let schedules = try await scheduleViewModel.getSchedulesForSubject(subjectId)
                
                await MainActor.run {
                    attendanceViewModel.schedulesForSubject = schedules
                    // Clear selected schedule when subject changes
                    attendanceViewModel.selectedSchedule = nil
                    isLoadingSchedules = false
                }
                
            } catch {
                await MainActor.run {
                    print("Error loading schedules for subject: \(error.localizedDescription)")
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
