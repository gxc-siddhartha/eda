//
//  TodaysEventsItem.swift
//  eda
//
//  Created by Siddhartha Srivastava on 13/07/25.
//

import SwiftUI

struct TodaysEventsItem: View {

    var todaysSchedules: [Schedule?]

    func formatDateToHourAndMinute(_ date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "hh:mm a"
        return dateFormatter.string(from: date)
    }

    private var countOfEvents: Int {
        return todaysSchedules.filter { $0 != nil }.count
    }

    private var firstScheduleStartTime: String {
        return formatDateToHourAndMinute(
            todaysSchedules[0]?.scheduleStartTime ?? Date()
        )
    }

    private var lastScheduleEndTime: String {
        return formatDateToHourAndMinute(
            todaysSchedules.last??.scheduleEndTime ?? Date()
        )
    }

    init(todaysSchedules: [Schedule?]) {
        self.todaysSchedules = todaysSchedules

    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, ) {
                HStack {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.title3)
                    Text("\(countOfEvents) events today").font(.title3)
                }.padding(.bottom, 4)
                    .foregroundStyle(Color.accentColor)

                Text("Your shift is from").opacity(0.5)
                HStack {
                    Image(systemName: "figure.walk")
                        .font(.title3)
                    Text(firstScheduleStartTime).font(
                        .system(.title2, design: .rounded)
                    ).fontWeight(Font.Weight.medium)
                    Text("to")
                    Text(lastScheduleEndTime).font(
                        .system(.title2, design: .rounded)
                    ).fontWeight(Font.Weight.medium)
                }
            }
            Spacer()
        }.padding(.vertical)
            .padding(.leading)
    }
}
