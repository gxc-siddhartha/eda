// MARK: - Updated AttendanceView with proper async data loading

import SwiftUI
import Foundation
import Charts

struct AttendanceView: View {
    @EnvironmentObject var attendanceViewModel: AttendanceViewModel
    var subject: Subject
    @State private var isLoading = false
    
    @State private var showDeleteAlert = false
    @State private var attendanceToDelete: Attendance?
    
    // MARK: - Computed Properties
    private var isEmpty: Bool {
        attendanceViewModel.attendanceForSelectedSubject.isEmpty
    }
    
    private var emptyStateView: some View {
        VStack {
            Text("📭").font(.system(size: 60, weight: .bold, design: .default))
            Text("Nothing to show. Add some attendance data for this subject first.")
                .padding(.horizontal)
        }
        .multilineTextAlignment(.center)
        .navigationTitle(subject.subjectName ?? "Untitled Subject")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .onAppear {
            loadData()
        }
    }
    
    private var contentView: some View {
        List {
            chartSection
            insightsSection
            attendanceLogsSection
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: -1) {
                    Text(subject.subjectName ?? "")
                        .font(.headline)
                        .fontWeight(.semibold)
                        
                    Text(subject.subjectTeacher ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            loadData()
        }
        .alert(isPresented: $showDeleteAlert) {
            Alert(
                title: Text("Delete Log"),
                message: Text("This operation will delete this attendance log permanently. Are you sure you want to proceed?"),
                primaryButton: .destructive(Text("Delete")) {
                    if let attendance = attendanceToDelete {
                        Task {
                            do {
                                try await attendanceViewModel.deleteAttendance(attendance)
                            } catch {
                                print(error)
                            }
                        }
                    }
                    showDeleteAlert = false
                },
                secondaryButton: .cancel(Text("Cancel")) {
                    showDeleteAlert = false
                }
            )
        }
    }
    
    var body: some View {
        if isEmpty {
            emptyStateView
        } else {
            contentView
        }
    }
    
    // MARK: - Section Views
    private var chartSection: some View {
        Group {
            if attendanceViewModel.currentWeekChartData.hasAnyData {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Chart {
                            // Draw the gradient area under the line
                            ForEach(attendanceViewModel.currentWeekChartData.chartPoints) { point in
                                AreaMark(
                                    x: .value("Day", point.date),
                                    y: .value("Running %", point.runningPercentage)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.accentColor.opacity(0.5),
                                            Color.accentColor.opacity(0.1),
                                            Color.clear
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .interpolationMethod(.monotone)
                            }
                            
                            // Draw the line connecting the percentage points
                            ForEach(attendanceViewModel.currentWeekChartData.chartPoints) { point in
                                LineMark(
                                    x: .value("Day", point.date),
                                    y: .value("Running %", point.runningPercentage)
                                )
                                .foregroundStyle(Color.accentColor)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                                .interpolationMethod(.monotone)
                            }

                            // Highlight today's point
                            ForEach(attendanceViewModel.currentWeekChartData.chartPoints.filter { $0.isToday }) { point in
                                PointMark(
                                    x: .value("Day", point.date),
                                    y: .value("Running %", point.runningPercentage)
                                )
                                .symbolSize(20)
                                .foregroundStyle(Color.accentColor)
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: attendanceViewModel.currentWeekChartData.chartPoints.map { $0.date }) { date in
                                AxisGridLine()
                                AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let percent = value.as(Double.self) {
                                        Text("\(Int(percent))%")
                                    }
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets())
                        .frame(height: 200)
                        .padding(.top, 16)
                        .chartYScale(domain: 10...100)
                        
                        attendancePercentageView
                    }
                } header: {
                    Text("Weekly Running Attendance")
                }
            }
        }
    }
    
    private var attendancePercentageView: some View {
        VStack(alignment: .leading, spacing: -1) {
            Text("Your current attendance percentage is")
                .font(.headline)
                .opacity(0.5)
            
            HStack {
                Text(String(format: "%.1f", attendanceViewModel.attendanceRate) + "%")
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.semibold)
                
                let required = Double(subject.semester?.passingPercentage ?? "0") ?? 0.0
                
                if attendanceViewModel.attendanceRate >= required {
                    Image(systemName: "arrow.up.circle")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var insightsSection: some View {
        Group {
            let required = Double(subject.semester?.passingPercentage ?? "0") ?? 0.0
            let canSkip = attendanceViewModel.maxSkippableClasses(beforeDroppingBelow: required)
            let toAttend = attendanceViewModel.presencesNeeded(toReach: required)
            
            if attendanceViewModel.attendanceRate > required && canSkip != 0 {
                Section("Insights") {
                    HStack {
                        Image(systemName: "star.circle").foregroundStyle(Color.accentColor)
                        Text("You can skip upto ") + Text("\(canSkip)").foregroundStyle(Color.accentColor).fontWeight(.semibold) + Text(canSkip == 1 ? " class before dropping below the required percentage." : " classes before dropping below the required percentage.")
                    }
                }
            } else if attendanceViewModel.attendanceRate < required && toAttend != 0 {
                Section("Insights") {
                    HStack {
                        Image(systemName: "star.circle").foregroundStyle(Color.accentColor)
                        Text("You have to attend at least ") + Text("\(toAttend)").foregroundStyle(Color.accentColor).fontWeight(.semibold) + Text(toAttend == 1 ? " class to reach the required percentage." : " classes to reach the required percentage.")
                    }
                }
            }
        }
    }

    private var attendanceLogsSection: some View {
        Group {
            if !attendanceViewModel.attendanceForSelectedSubject.isEmpty {
                Section("Attendance Logs") {
                    ForEach(attendanceViewModel.attendanceForSelectedSubject, id: \.attendanceId) { attendance in
                        AttendanceListItem(attendance: attendance)
                            .listRowInsets(EdgeInsets())
                        
                            .swipeActions {
                                Button("Delete") {
                                    self.attendanceToDelete = attendance
                                    showDeleteAlert = true
                                }
                                .tint(.red)
                                
                                Button("Edit") {
                                    attendanceViewModel.startEditing(attendance)
                                }
                                .tint(.accentColor)
                            }
                            
                          
                        
                    }
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func loadData() {
        Task {
            self.isLoading = true
            defer { self.isLoading = false }
            // Update selected subject first
            await attendanceViewModel.changeSelectedSubject(subject)
        }
    }
    
    private func refreshData() async {
        await attendanceViewModel.refreshData()
    }
}
