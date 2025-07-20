//
//  ActiveScheduleItem.swift
//  eda
//
//  Created by Siddhartha Srivastava on 13/07/25.
//

import SwiftUI

struct ScheduleViewListItem: View {
   @ObservedObject var schedule: Schedule
    
    func formatDateToTimeAndHour(_ date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "h:mm a"
        return dateFormatter.string(from: date)
    }
    
    var body: some View {
        HStack {
            
            ZStack{
                Rectangle().fill(Color("a\(schedule.subject?.subjectColor ?? "AccentColor")").opacity(0.15))
                    .frame(width: 55)
                Image(systemName: "applewatch.watchface")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(Color("a\(schedule.subject?.subjectColor ?? "Blue")"))
                    .frame(width: 20, height:20)
                    .padding()
            }
            
            VStack(alignment: .leading, spacing: 0){
                Text(schedule.subject?.subjectName ?? "Untitled Subject").lineLimit(1)
                    .font(.headline)
                    
                    .padding(.top, 6)
                HStack {
                    Image(systemName: "location.fill").font(.caption)   
                    Text(schedule.scheduleLocation ?? "Unkwown").font(.subheadline).lineLimit(1)
                }.foregroundStyle(Color("a\(schedule.subject?.subjectColor ?? "AccentColor")"))
                    .padding(.bottom, 6)
                
            }.padding(.trailing)
            Spacer()
            
            HStack {
                Image(systemName: "applewatch.side.right")
                    .font(.title3)

                  
                VStack(alignment: .leading, spacing: -2){
                    Text("\(formatDateToTimeAndHour(schedule.scheduleStartTime ?? Date()))").font(.caption)
                        .fontWeight(Font.Weight.medium).opacity(0.6).lineLimit(1)
                    Text("\(formatDateToTimeAndHour(schedule.scheduleEndTime ?? Date()))")
                        .fontWeight(Font.Weight.medium).font(.caption).opacity(0.6).lineLimit(1)
                }
            }
        }
    }
}
//
//#Preview {
//    ScheduleViewListItem()
//}
