//
//  AttendanceViewModel+Charts.swift
//  eda
//
//  Created by Siddhartha Srivastava on 13/07/25.
//
import Foundation
import SwiftUI
import Charts
// MARK: - Chart Data Structures
struct RunningPercentagePoint: Identifiable {
    let dayName: String
    let date: Date
    let runningPercentage: Double      // Overall % after including this day
    let daySessionsAdded: Int          // How many records added this day
    let dayPresentCount: Int           // Present records added this day
    let dayAbsentCount: Int            // Absent records added this day
    let totalRecordsIncluded: Int      // Cumulative total records
    let percentageChange: Double       // Change from previous day
    let isToday: Bool                  // Is this today's date
    let isFuture: Bool                 // Is this a future date
    let hasData: Bool                  // Does this day have any attendance data
    
    // Identifiable conformance
    var id: Date { date }
    
    // Additional computed properties for UI
    var formattedPercentage: String {
        return String(format: "%.1f%%", runningPercentage)
    }
    
    var changeDirection: PercentageChangeDirection {
        if percentageChange > 0.5 { return .up }
        if percentageChange < -0.5 { return .down }
        return .stable
    }
    
    var daySuccessRate: Double {
        let totalDay = dayPresentCount + dayAbsentCount
        guard totalDay > 0 else { return 0.0 }
        return (Double(dayPresentCount) / Double(totalDay)) * 100.0
    }
}

enum PercentageChangeDirection {
    case up, down, stable
}

struct WeeklyAttendanceChartData {
    let weekStartDate: Date
    let weekEndDate: Date
    let chartPoints: [RunningPercentagePoint]
    let overallTrend: WeeklyTrend
    let weekSummary: WeekSummary
    let hasAnyData: Bool
    
    var isCurrentWeek: Bool {
        Calendar.current.isDateInToday(Date()) &&
        Calendar.current.isDate(Date(), inSameDayAs: weekStartDate) ||
        (weekStartDate...weekEndDate).contains(Date())
    }
}

struct WeekSummary {
    let totalSessionsThisWeek: Int
    let presentSessionsThisWeek: Int
    let absentSessionsThisWeek: Int
    let weekSuccessRate: Double
    let startingPercentage: Double?
    let endingPercentage: Double?
    let totalPercentageChange: Double
}

enum WeeklyTrend {
    case improving    // Generally upward trend
    case declining    // Generally downward trend
    case stable       // Little change
    case volatile     // Mixed up and down
    case noData       // No data available
}

// MARK: - Chart Data Extension
extension AttendanceViewModel {
    
    // MARK: - Main Chart Data Method
    func getWeeklyRunningPercentageData(for weekStartDate: Date? = nil) -> WeeklyAttendanceChartData {
        logger.info("📊 Generating weekly running percentage chart data")
        
        guard let subject = selectedSubject else {
            logger.warning("⚠️ No subject selected for chart data")
            return createEmptyChartData()
        }
        
        let weekDates = getCurrentWeekDates(startingFrom: weekStartDate)
        let chronologicalAttendance = getSortedAttendanceForSubject()
        
        var chartPoints: [RunningPercentagePoint] = []
        var runningTotal = 0
        var runningPresent = 0
        var runningAbsent = 0
        var previousPercentage: Double = 0.0
        
        // Get attendance data before this week for baseline
        let preWeekAttendance = getAttendanceBeforeWeek(weekDates.start, from: chronologicalAttendance)
        runningTotal = preWeekAttendance.total
        runningPresent = preWeekAttendance.present
        runningAbsent = preWeekAttendance.absent
        
        if runningTotal > 0 {
            previousPercentage = (Double(runningPresent) / Double(runningTotal)) * 100.0
        }
        
        // Process each day of the week
        for (index, date) in weekDates.weekdays.enumerated() {
            let dayAttendance = getAttendanceForSpecificDate(date, from: chronologicalAttendance)
            var dayPresent = dayAttendance.filter { $0.attendancePresence == "Present"}.count
            let dayMedical = dayAttendance.filter { $0.attendancePresence == "Medical Substitution"}.count
            dayPresent = dayPresent + dayPresent
            let dayAbsent = dayAttendance.filter { $0.attendancePresence == "Absent" }.count
            let dayTotal = dayPresent + dayAbsent
            
            // Update running totals
            runningTotal += dayTotal
            runningPresent += dayPresent
            runningAbsent += dayAbsent
            
            // Calculate running percentage
            let currentPercentage: Double
            if runningTotal > 0 {
                currentPercentage = (Double(runningPresent) / Double(runningTotal)) * 100.0
            } else {
                currentPercentage = 0.0
            }
            
            // Calculate percentage change
            let percentageChange = currentPercentage - previousPercentage
            
            // Create chart point
            let point = RunningPercentagePoint(
                dayName: getDayAbbreviation(for: date),
                date: date,
                runningPercentage: currentPercentage,
                daySessionsAdded: dayTotal,
                dayPresentCount: dayPresent,
                dayAbsentCount: dayAbsent,
                totalRecordsIncluded: runningTotal,
                percentageChange: percentageChange,
                isToday: Calendar.current.isDateInToday(date),
                isFuture: date > Date(),
                hasData: dayTotal > 0
            )
            
            chartPoints.append(point)
            previousPercentage = currentPercentage
            
            logger.debug("📈 Day \(point.dayName): \(point.formattedPercentage) (\(dayTotal) sessions)")
        }
        
        let weekSummary = calculateWeekSummary(chartPoints: chartPoints, preWeekPercentage: preWeekAttendance.total > 0 ? (Double(preWeekAttendance.present) / Double(preWeekAttendance.total)) * 100.0 : nil)
        let weeklyTrend = determineWeeklyTrend(chartPoints: chartPoints)
        
        let chartData = WeeklyAttendanceChartData(
            weekStartDate: weekDates.start,
            weekEndDate: weekDates.end,
            chartPoints: chartPoints,
            overallTrend: weeklyTrend,
            weekSummary: weekSummary,
            hasAnyData: !chartPoints.allSatisfy { !$0.hasData }
        )
        return chartData
    }
    
    // MARK: - Helper Methods
    
    private func getCurrentWeekDates(startingFrom date: Date?) -> (start: Date, end: Date, weekdays: [Date]) {
        let calendar = Calendar.current
        let referenceDate = date ?? Date()
        
        // Find Monday of the week
        let weekdayComponent = calendar.component(.weekday, from: referenceDate)
        let daysFromMonday = (weekdayComponent == 1) ? 6 : weekdayComponent - 2 // Sunday = 1, Monday = 2
        let mondayDate = calendar.date(byAdding: .day, value: -daysFromMonday, to: referenceDate)!
        
        // Generate Monday through Friday
        let weekdays = (0..<5).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: mondayDate)
        }
        
        let fridayDate = weekdays.last ?? mondayDate
        
        return (start: mondayDate, end: fridayDate, weekdays: weekdays)
    }
    
    private func getSortedAttendanceForSubject() -> [Attendance] {
        return attendanceForSelectedSubject
            .filter { attendance in
                // Only include Present and Absent (exclude Medical Substitution for percentage calculation)
                attendance.attendancePresence == "Present" || attendance.attendancePresence == "Absent"
            }
            .sorted { first, second in
                guard let firstDate = first.attendanceDate,
                      let secondDate = second.attendanceDate else {
                    return false
                }
                return firstDate < secondDate
            }
    }
    
    private func getAttendanceBeforeWeek(_ weekStart: Date, from attendance: [Attendance]) -> (total: Int, present: Int, absent: Int) {
        let beforeWeek = attendance.filter { record in
            guard let attendanceDate = record.attendanceDate else { return false }
            return attendanceDate < weekStart
        }
        
        let present = beforeWeek.filter { $0.attendancePresence == "Present" }.count
        let absent = beforeWeek.filter { $0.attendancePresence == "Absent" }.count
        
        return (total: present + absent, present: present, absent: absent)
    }
    
    private func getAttendanceForSpecificDate(_ date: Date, from attendance: [Attendance]) -> [Attendance] {
        let calendar = Calendar.current
        return attendance.filter { record in
            guard let attendanceDate = record.attendanceDate else { return false }
            return calendar.isDate(attendanceDate, inSameDayAs: date)
        }
    }
    
    private func getDayAbbreviation(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE" // Mon, Tue, Wed, etc.
        return formatter.string(from: date)
    }
    
    private func calculateWeekSummary(chartPoints: [RunningPercentagePoint], preWeekPercentage: Double?) -> WeekSummary {
        let totalSessions = chartPoints.reduce(0) { $0 + $1.daySessionsAdded }
        let presentSessions = chartPoints.reduce(0) { $0 + $1.dayPresentCount }
        let absentSessions = chartPoints.reduce(0) { $0 + $1.dayAbsentCount }
        
        let weekSuccessRate: Double
        if totalSessions > 0 {
            weekSuccessRate = (Double(presentSessions) / Double(totalSessions)) * 100.0
        } else {
            weekSuccessRate = 0.0
        }
        
        let startingPercentage = preWeekPercentage
        let endingPercentage = chartPoints.last?.runningPercentage
        
        let totalChange: Double
        if let start = startingPercentage, let end = endingPercentage {
            totalChange = end - start
        } else if let end = endingPercentage {
            totalChange = end
        } else {
            totalChange = 0.0
        }
        
        return WeekSummary(
            totalSessionsThisWeek: totalSessions,
            presentSessionsThisWeek: presentSessions,
            absentSessionsThisWeek: absentSessions,
            weekSuccessRate: weekSuccessRate,
            startingPercentage: startingPercentage,
            endingPercentage: endingPercentage,
            totalPercentageChange: totalChange
        )
    }
    
    private func determineWeeklyTrend(chartPoints: [RunningPercentagePoint]) -> WeeklyTrend {
        let pointsWithData = chartPoints.filter { $0.hasData }
        
        guard pointsWithData.count >= 2 else {
            return pointsWithData.isEmpty ? .noData : .stable
        }
        
        let changes = pointsWithData.map { $0.percentageChange }
        let positiveChanges = changes.filter { $0 > 0.5 }.count
        let negativeChanges = changes.filter { $0 < -0.5 }.count
        
        // Determine overall trend
        if let first = pointsWithData.first, let last = pointsWithData.last {
            let overallChange = last.runningPercentage - first.runningPercentage
            
            if abs(overallChange) < 1.0 {
                return .stable
            } else if overallChange > 0 {
                return positiveChanges >= negativeChanges ? .improving : .volatile
            } else {
                return negativeChanges >= positiveChanges ? .declining : .volatile
            }
        }
        
        return .stable
    }
    
    private func createEmptyChartData() -> WeeklyAttendanceChartData {
        let weekDates = getCurrentWeekDates(startingFrom: nil)
        let emptyPoints = weekDates.weekdays.map { date in
            RunningPercentagePoint(
                dayName: getDayAbbreviation(for: date),
                date: date,
                runningPercentage: 0.0,
                daySessionsAdded: 0,
                dayPresentCount: 0,
                dayAbsentCount: 0,
                totalRecordsIncluded: 0,
                percentageChange: 0.0,
                isToday: Calendar.current.isDateInToday(date),
                isFuture: date > Date(),
                hasData: false
            )
        }
        
        let emptySummary = WeekSummary(
            totalSessionsThisWeek: 0,
            presentSessionsThisWeek: 0,
            absentSessionsThisWeek: 0,
            weekSuccessRate: 0.0,
            startingPercentage: nil,
            endingPercentage: nil,
            totalPercentageChange: 0.0
        )
        
        return WeeklyAttendanceChartData(
            weekStartDate: weekDates.start,
            weekEndDate: weekDates.end,
            chartPoints: emptyPoints,
            overallTrend: .noData,
            weekSummary: emptySummary,
            hasAnyData: false
        )
    }
    
    // MARK: - Additional Chart Utilities
    
    func getChartDataForPreviousWeek() -> WeeklyAttendanceChartData {
        let calendar = Calendar.current
        let lastWeekDate = calendar.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date()
        return getWeeklyRunningPercentageData(for: lastWeekDate)
    }
    
    func getChartDataForNextWeek() -> WeeklyAttendanceChartData {
        let calendar = Calendar.current
        let nextWeekDate = calendar.date(byAdding: .weekOfYear, value: 1, to: Date()) ?? Date()
        return getWeeklyRunningPercentageData(for: nextWeekDate)
    }
    
    // MARK: - Updated Chart Data Loading Method (Add this method to refresh chart data)
     func updateWeeklyChartData() {
        guard selectedSubject != nil else {
            weeklyChartData = createEmptyChartData()
            return
        }
        
        weeklyChartData = getWeeklyRunningPercentageData()
        logger.debug("📊 Weekly chart data updated")
    }

    
    func getTrendDescription(for trend: WeeklyTrend) -> String {
        switch trend {
        case .improving:
            return "Your attendance is improving this week! 📈"
        case .declining:
            return "Your attendance needs attention this week. 📉"
        case .stable:
            return "Your attendance is consistent this week. ➡️"
        case .volatile:
            return "Your attendance is inconsistent this week. 📊"
        case .noData:
            return "No attendance data available for this week."
        }
    }
    
    func getDetailedSummary(for chartData: WeeklyAttendanceChartData) -> String {
        let summary = chartData.weekSummary
        
        guard chartData.hasAnyData else {
            return "No attendance data for this week."
        }
        
        var description = "Week Summary: "
        description += "\(summary.totalSessionsThisWeek) sessions "
        description += "(\(summary.presentSessionsThisWeek) present, \(summary.absentSessionsThisWeek) absent). "
        
        if let ending = summary.endingPercentage {
            description += "Overall: \(String(format: "%.1f%%", ending)). "
        }
        
        if abs(summary.totalPercentageChange) > 0.5 {
            let direction = summary.totalPercentageChange > 0 ? "improved" : "declined"
            description += "You \(direction) by \(String(format: "%.1f", abs(summary.totalPercentageChange)))% this week."
        } else {
            description += "Steady week with minimal change."
        }
        
        return description
    }
}

// MARK: - Published Properties for Chart
extension AttendanceViewModel {
    

    var currentWeekChartData: WeeklyAttendanceChartData {
        return weeklyChartData ?? createEmptyChartData()
    }
    
    var hasChartData: Bool {
        !attendanceForSelectedSubject.isEmpty && selectedSubject != nil
    }
    
    var chartDataLastUpdated: Date {
        Date()
    }
}
