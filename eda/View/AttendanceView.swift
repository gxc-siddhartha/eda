// MARK: - Updated AttendanceView with proper async data loading

import SwiftUI
import Foundation
import Charts

struct AttendanceView: View {
    @EnvironmentObject var attendanceViewModel: AttendanceViewModel
    var subject: Subject
    @State private var isLoading = false
    
    var body: some View {
        
        if(attendanceViewModel.attendanceForSelectedSubject.isEmpty) {
            VStack {
                Text("📭").font(.system(size: 60, weight: .bold, design: .default))
                Text("Nothing to show. Add some attendance data for this subject first.")
                    .padding(.horizontal)
               
            }.multilineTextAlignment(.center)
                    
            .navigationTitle(subject.subjectName ?? "Untitled Subject")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .onAppear {
                loadData()
            }
        }else {
            List {
                if attendanceViewModel.currentWeekChartData.hasAnyData {
                    Section {
                        VStack(alignment: .leading, spacing: 4){
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
                                
                       
                            VStack(alignment: .leading, spacing: -1) {
                                Text("Your current attendance percentage is").font(.headline
                                ).opacity(0.5)
                                HStack {
                                    Text(String(format: "%.1f", attendanceViewModel.attendanceRate) + "%")
                                        .font(.system(.title, design: .rounded)).fontWeight(Font.Weight.semibold)
        //
                                    // Convert the passing percentage string → Double, defaulting to 0.0 if it fails
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
                    } header: {
                        Text("Weekly Running Attendance")
                        
                    }
                }
                
                let required = Double(subject.semester?.passingPercentage ?? "0") ?? 0.0
                let canSkip = attendanceViewModel.maxSkippableClasses(beforeDroppingBelow: required)
                let toAttend = attendanceViewModel.presencesNeeded(toReach: required)

        
                     if(attendanceViewModel.attendanceRate > required && canSkip != 0) {
                         
                         Section ("Insights"){
                             HStack {
                                 Image(systemName: "star.circle").foregroundStyle(Color.accentColor)
                                 Text("You can skip upto ") + Text("\(canSkip)").foregroundStyle(Color.accentColor).fontWeight(Font.Weight.semibold) + Text(canSkip == 1 ? " class before dropping below the required percentage." : " classes before dropping below the required percentage.")
                             }
                         }
                        
                            
                        } else if (attendanceViewModel.attendanceRate < required && toAttend != 0) {
                            
                            Section("Insights"){
                                HStack{
                                    Image(systemName: "star.circle").foregroundStyle(Color.accentColor)

                                    Text("You have to attend at least ") + Text("\(toAttend)").foregroundStyle(Color.accentColor).fontWeight(Font.Weight.semibold) + Text(toAttend == 1 ? " class to reach the required percentage." : " classes to reach the required percentage.")
                                }
                            }

                        }
                    
                
                if(!attendanceViewModel.attendanceForSelectedSubject.isEmpty) {
                    Section("Attendance Logs") {
                        ForEach(attendanceViewModel.attendanceForSelectedSubject, id: \.attendanceId) { attendance in
                            AttendanceListItem(attendance: attendance)
                                .listRowInsets(EdgeInsets())
                        }
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
