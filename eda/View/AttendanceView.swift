// MARK: - Updated AttendanceView with proper async data loading

import SwiftUI
import Foundation
import Charts

struct AttendanceView: View {
    @EnvironmentObject var attendanceViewModel: AttendanceViewModel
    var subject: Subject
    @State private var isLoading = false
    
    var body: some View {
        
        List {
            Section {
    
                VStack(alignment: .leading, spacing: 4){
                    if attendanceViewModel.currentWeekChartData.hasAnyData {
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
                                            Color.accentColor.opacity(0.3),
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
                                .symbolSize(100)
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
                        .frame(height: 200)
                        .padding()
                        .padding(.top, 16)
                        .listRowInsets(EdgeInsets())
                    } else {
                        // Show placeholder when no data available
                        VStack {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("No attendance data for this week")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                    }
                    

                }
            } header: {
                Text("Weekly Running Attendance")
                
            }
            
            Section("Attendance Logs") {
                ForEach(attendanceViewModel.attendanceForSelectedSubject, id: \.attendanceId) { attendance in
                    AttendanceListItem(attendance: attendance)
                        .listRowInsets(EdgeInsets())
                }
            }
        }
        .navigationTitle(subject.subjectName ?? "Untitled Subject")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .onAppear {
            loadData()
        }
      
    }
    
    // MARK: - Private Methods
    
    private func loadData() {
        Task {
            self.isLoading = true
            defer { self.isLoading = false }
            
            do {
                // Update selected subject first
                await attendanceViewModel.changeSelectedSubject(subject)
                
                // Load attendance data (this will also update chart data)
                try await attendanceViewModel.loadAttendanceForSubject(subject)
                
            } catch {
                print("Error loading attendance data: \(error.localizedDescription)")
            }
        }
    }
    
    private func refreshData() async {
        await attendanceViewModel.refreshData()
    }
}
