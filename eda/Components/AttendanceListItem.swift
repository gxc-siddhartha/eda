//
//  ActiveScheduleItem.swift
//  eda
//
//  Created by Siddhartha Srivastava on 13/07/25.
//

import SwiftUI

struct AttendanceListItem: View {
   @ObservedObject var attendance: Attendance

    func formatDateToTimeAndHour(_ date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "h:mm a"
        return dateFormatter.string(from: date)
    }
    
    func formatDateToWeekday(_ date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE"
        return dateFormatter.string(from: date)
    }
    
    var body: some View {
        HStack {
            if(attendance.attendancePresence == "Medical Substitution") {
                ZStack{
                    Rectangle().fill(Color.accentColor).opacity(0.1)
                        .frame(width: 55)
                    Image(systemName: "bandage.fill")
                        .font(.title3)
                        .padding()
                        .foregroundStyle(Color.accentColor)
                }
            
            } else if(attendance.attendancePresence == "Present") {
                ZStack{
                    Rectangle().fill(Color.green).opacity(0.1)
                        .frame(width: 55)
                    Image(systemName: "p.circle.fill")
                        .font(.title3)
                        .padding()
                        .foregroundStyle(Color.green)
                }
            
            } else {
                ZStack{
                    Rectangle().fill(Color.red).opacity(0.1)
                        .frame(width: 55)
                    Image(systemName: "a.circle.fill")
                        .font(.title3)
                        .padding()
                        .foregroundStyle(Color.red)
                }
            
            }
            
            
            VStack(alignment: .leading, spacing: 0){
                HStack {
                    Text(formatDateToWeekday(attendance.attendanceDate ?? Date())).lineLimit(1)
                        .font(.headline)
                        
                    Text(attendance.attendanceType ?? "N/A").font(.system(.subheadline, design: .rounded)).fontWeight(Font.Weight.semibold).opacity(0.4)
                }.padding(.top, 6)
                
                HStack(alignment: .lastTextBaseline) {
                    Image(systemName: "calendar").font(.caption)
                    Text(attendance.attendanceDate ?? Date(), format: .dateTime.day().month().year()).font(.subheadline).lineLimit(1)
                }.padding(.bottom, 6)
                
//                Text("\(formatDateToTimeAndHour(schedule.scheduleStartTime ?? Date())) to \(formatDateToTimeAndHour(schedule.scheduleEndTime ?? Date()))")
//                    .opacity(0.5)
//                    .padding(.bottom, 6)
            }
            Spacer()
            
            HStack {
                Image(systemName: "applewatch.side.right")
                    .font(.title3)

                  
                VStack(alignment: .leading, spacing: -2){
                    Text("\(formatDateToTimeAndHour(attendance.attendanceStartTime ?? Date()))").font(.caption)
                        .fontWeight(Font.Weight.medium).opacity(0.6).lineLimit(1)
                    Text("\(formatDateToTimeAndHour(attendance.attendanceEndTime ?? Date()))")
                        .fontWeight(Font.Weight.medium).font(.caption).opacity(0.6).lineLimit(1)
                }
            }.padding(.trailing, 16)

        }
    }
}
//
//#Preview {
//    AttendanceListItem()
//}
