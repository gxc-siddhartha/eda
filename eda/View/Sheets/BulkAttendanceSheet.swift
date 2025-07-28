//
//  BulkAttendanceSheet.swift
//  eda
//
//  Simplified sheet for marking bulk attendance
//

import SwiftUI

struct BulkAttendanceSheet: View {
    @StateObject private var bulkViewModel = BulkAttendanceViewModel()
    @EnvironmentObject private var semesterViewModel: SemesterViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingQuickActions = false
    @State private var showingSubmitAlert = false
    
    func formatDateToWeekday(_ date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE"
        return dateFormatter.string(from: date)
    }
    
    
    var body: some View {
        NavigationStack {
            Group {
                if bulkViewModel.loadingState.isLoading {
                    loadingView
                } else if !bulkViewModel.hasSchedules {
                    emptyStateView
                } else {
                    scheduleListView
                }
            }
            .navigationTitle("Mark Attendance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbar {
                toolbarContent
            }
            .confirmationDialog(
                "Quick Actions",
                isPresented: $showingQuickActions,
                titleVisibility: .visible
            ) {
                quickActionsDialog
            }
            .alert("Mark Attendance", isPresented: $showingSubmitAlert) {
                Button("Present") {
                    Task {
                        await submitWithStatus(.present)
                    }
                }
                
                Button("Absent") {
                    Task {
                        await submitWithStatus(.absent)
                    }
                }
                
                Button("Cancel", role: .cancel) { }
                
            } message: {
                Text("Mark \(bulkViewModel.selectedCount) \(bulkViewModel.selectedCount == 1 ? "class" : "classes") as:")
            }
            .alert("Error", isPresented: $bulkViewModel.showErrorAlert) {
                Button("OK") {
                    bulkViewModel.clearAlerts()
                }
                if bulkViewModel.showRetryOption {
                    Button("Retry") {
                        Task {
                            await bulkViewModel.retryLastOperation()
                        }
                    }
                }
            } message: {
                Text(bulkViewModel.alertMessage)
            }
            .alert("Success", isPresented: $bulkViewModel.showSuccessAlert) {
                Button("OK") {
                    bulkViewModel.clearAlerts()
                }
            } message: {
                Text(bulkViewModel.alertMessage)
            }
        }
        .task {
            await bulkViewModel.initialize(with: semesterViewModel.selectedSemesterForUser)
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Loading today's classes...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Text("✅")
                .font(.system(size: 60, weight: .bold, design: .default))
            
            Text("All caught up!")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("You've already marked attendance for all your classes today.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Schedule List View
    
    private var scheduleListView: some View {
        List {
            if bulkViewModel.hasSchedules {
                schedulesSection
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await bulkViewModel.refreshData()
        }
    }
    
    // MARK: - Schedules Section
    
    private var schedulesSection: some View {
        Section("Classes") {
            ForEach(bulkViewModel.scheduleItems) { item in
                ScheduleRowView(
                    item: item,
                    isSelected: bulkViewModel.selectedItems.contains(item.id),
                    onSelectionToggle: {
                        bulkViewModel.toggleSelection(for: item.id)
                    }
                )
            }
        }
        
    }
    
    // MARK: - Toolbar Content
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {

        ToolbarItem(placement: .confirmationAction) {
            Button {
                showingSubmitAlert = true
            } label: {
                Text("Submit")
                    .fontWeight(.semibold)
            }
            .disabled(!bulkViewModel.canSubmit)
        }
    }
    
    // MARK: - Quick Actions Dialog
    
    @ViewBuilder
    private var quickActionsDialog: some View {
        if bulkViewModel.canSelectAll {
            Button("Select All") {
                bulkViewModel.selectAll()
            }
        }
        
        if bulkViewModel.hasSelectedSchedules {
            Button("Clear Selection") {
                bulkViewModel.clearAllSelections()
            }
        }
        
        Button("Refresh") {
            Task {
                await bulkViewModel.refreshData()
            }
        }
        
        Button("Cancel", role: .cancel) { }
    }
    
    // MARK: - Submit Helper
    
    private func submitWithStatus(_ status: ScheduleSelectionItem.AttendanceStatus) async {
        do {
            bulkViewModel.setAttendanceStatusForSelected(status)
            _ = try await bulkViewModel.submitBulkAttendance()
        } catch {
            // Error handling is done in ViewModel
        }
    }
}

// MARK: - Simplified Schedule Row View

private struct ScheduleRowView: View {
    let item: ScheduleSelectionItem
    let isSelected: Bool
    let onSelectionToggle: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Selection checkbox
            Button {
                onSelectionToggle()
            } label: {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor : Color(.systemGray5))
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            
            // Schedule content
            VStack(alignment: .leading, spacing: 4) {
                Text(item.schedule.subject?.subjectName ?? "Unknown Subject")
                    .font(.system(.headline, design: .rounded))
                    .lineSpacing(0.55)
                    .lineLimit(2)
    
                
            }
            
            Spacer()
            
            // Time display
            
                    VStack(alignment: .leading, spacing: -2) {
                        if let startTime = item.schedule.scheduleStartTime {
                            Text(startTime.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                        if let endTime = item.schedule.scheduleEndTime {
                            Text(endTime.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                    }
            
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectionToggle()
        }
    }
    
    private var todaysDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy"
        return formatter.string(from: Date())
    }
}

#Preview {
    BulkAttendanceSheet()
        .environmentObject(SemesterViewModel())
}
