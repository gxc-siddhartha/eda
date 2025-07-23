//
//  EditAttendanceSheet.swift
//  eda
//
//  Created by Siddhartha Srivastava on 19/07/25.
//

import SwiftUI

struct EditAttendanceSheet: View {
    @EnvironmentObject var attendanceViewModel: AttendanceViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Attendance Details Section
                Section("Attendance Details") {

                    Picker(
                        "Attendance Type",
                        selection: $attendanceViewModel.attendanceType
                    ) {

                        ForEach(
                            attendanceViewModel.availableAttendanceTypes,
                            id: \.self
                        ) { type in
                            Text(type).tag(type)
                        }

                        .pickerStyle(.menu)
                        .disabled(attendanceViewModel.loadingState.isLoading)
                    }
                    .frame(height: 22)

                    Picker(
                        "Presence Status",
                        selection: $attendanceViewModel.attendancePresent
                    ) {
                        ForEach(
                            attendanceViewModel.availablePresenceStatus,
                            id: \.self
                        ) { status in
                            Text(status).tag(status)
                        }

                        .pickerStyle(.segmented)
                        .disabled(attendanceViewModel.loadingState.isLoading)
                    }
                    .frame(height: 22)

                    if attendanceViewModel.attendanceType == "Other" {

                        // Event Description
                        HStack(alignment: .center, spacing: 16) {
                            Text("Event Description")
                                .font(.headline)
                                .foregroundColor(.primary)

                            TextField(
                                "e.g., Regular class, Quiz, Lab session",
                                text: $attendanceViewModel.attendanceEvent
                            )
                            .disabled(
                                attendanceViewModel.loadingState.isLoading
                            )
                        }
                    }

                }

                // MARK: - Date & Time Section
                Section("Date & Time") {
                    // Attendance Date

                    DatePicker(
                        "Attendance Date",
                        selection: $attendanceViewModel.attendanceDate,
                        in: attendanceViewModel
                            .minAllowedDate...attendanceViewModel.maxAllowedDate,
                        displayedComponents: .date
                    )

                    .datePickerStyle(.compact)
                    .disabled(attendanceViewModel.loadingState.isLoading)
                    .frame(height: 22)

                    if let allowedWeekday = attendanceViewModel.allowedWeekday {
                        Text("Must be a \(allowedWeekday)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    DatePicker(
                        "Start Time",
                        selection: $attendanceViewModel.attendanceStartTime,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.compact)
                    .disabled(attendanceViewModel.loadingState.isLoading)
                    .frame(height: 22)

                    DatePicker(
                        "End Time",
                        selection: $attendanceViewModel.attendanceEndTime,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.compact)
                    .disabled(attendanceViewModel.loadingState.isLoading)
                    .frame(height: 22)

                    // Time validation warning
                    if attendanceViewModel.attendanceStartTime
                        >= attendanceViewModel.attendanceEndTime
                    {
                        Label(
                            "End time must be after start time",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundColor(.red)
                    }

                }

                // MARK: - Location Section
                Section("Location") {
                    HStack(alignment: .center, spacing: 16) {
                        Text("Location")
                            .font(.headline)
                            .foregroundColor(.primary)

                        TextField(
                            "e.g., Room 101, Lab A, Online",
                            text: $attendanceViewModel.attendanceLocation
                        )
                        .disabled(attendanceViewModel.loadingState.isLoading)
                    }
                }

            }
            .navigationTitle("Edit Attendance")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                // Cancel button
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        attendanceViewModel.cancelEditing()
                        attendanceViewModel.clearForm()
                        dismiss()
                    }
                    .disabled(attendanceViewModel.loadingState.isLoading)
                }

                // Save button
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            do {
                                _ =
                                    try await attendanceViewModel
                                    .updateAttendance()
                                dismiss()
                            } catch {
                                // Error handling is managed by the view model
                            }
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
            .disabled(attendanceViewModel.loadingState.isLoading)
        }

        .alert("Error", isPresented: $attendanceViewModel.showErrorAlert) {
            Button("OK") {
                attendanceViewModel.clearAlerts()
            }

            if attendanceViewModel.showRetryOption {
                Button("Retry") {
                    Task {
                        do {
                            _ = try await attendanceViewModel.updateAttendance()
                            dismiss()
                        } catch {
                            // Error handling is managed by the view model
                        }
                    }
                }
            }
        } message: {
            Text(attendanceViewModel.alertMessage)
        }

        .onAppear {
            // Ensure we're in edit mode when the sheet appears
            if attendanceViewModel.editingAttendance == nil {
                dismiss()
            }
        }
    }
}
