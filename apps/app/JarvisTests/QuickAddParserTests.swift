import Foundation
import JarvisAPI
import Testing
@testable import Jarvis

/// 2026-07-31 is a Friday — every relative expectation below is anchored to it.
private let friday = "2026-07-31"

private func category(_ id: String, _ name: String) -> TaskCategoryDTO {
    TaskCategoryDTO(id: id, name: name, emoji: nil, colorHex: nil, sortOrder: 0, archivedAt: nil)
}

@MainActor
struct QuickAddParserTests {
    @Test func plainTitleIsUntouched() {
        let parse = QuickAddParser.parse("Buy 2 litres of milk", today: friday)
        #expect(parse.title == "Buy 2 litres of milk")
        #expect(parse.dueDate == nil)
        #expect(parse.dueTime == nil)
    }

    @Test func todayAndTomorrow() {
        #expect(QuickAddParser.parse("Call bank today", today: friday).dueDate == friday)
        #expect(QuickAddParser.parse("Call bank tomorrow", today: friday).dueDate == "2026-08-01")
        #expect(QuickAddParser.parse("Call bank tmrw", today: friday).dueDate == "2026-08-01")
    }

    @Test func datePhraseLeavesTheRestOfTheTitle() {
        let parse = QuickAddParser.parse("Send invoice tomorrow", today: friday)
        #expect(parse.title == "Send invoice")
    }

    @Test func weekdaysAlwaysLandInTheFuture() {
        // Friday → "friday" means the next one, not today.
        #expect(QuickAddParser.parse("standup friday", today: friday).dueDate == "2026-08-07")
        #expect(QuickAddParser.parse("standup mon", today: friday).dueDate == "2026-08-03")
        #expect(QuickAddParser.parse("standup next tuesday", today: friday).dueDate == "2026-08-04")
    }

    @Test func relativeSpans() {
        #expect(QuickAddParser.parse("review in 3 days", today: friday).dueDate == "2026-08-03")
        #expect(QuickAddParser.parse("review next week", today: friday).dueDate == "2026-08-07")
        #expect(QuickAddParser.parse("review in 2 weeks", today: friday).dueDate == "2026-08-14")
        #expect(QuickAddParser.parse("review next month", today: friday).dueDate == "2026-08-31")
    }

    @Test func weekendIsSaturday() {
        #expect(QuickAddParser.parse("clean garage this weekend", today: friday).dueDate == "2026-08-01")
    }

    @Test func calendarDatesRollIntoTheNextYear() {
        #expect(QuickAddParser.parse("book flight aug 5", today: friday).dueDate == "2026-08-05")
        #expect(QuickAddParser.parse("book flight 5 august", today: friday).dueDate == "2026-08-05")
        // January is already behind us in July, so it means next January.
        #expect(QuickAddParser.parse("taxes jan 3rd", today: friday).dueDate == "2027-01-03")
    }

    @Test func times() {
        #expect(QuickAddParser.parse("gym at 7pm", today: friday).dueTime == "19:00")
        #expect(QuickAddParser.parse("gym 5:30pm", today: friday).dueTime == "17:30")
        #expect(QuickAddParser.parse("standup 09:15", today: friday).dueTime == "09:15")
        #expect(QuickAddParser.parse("lunch noon", today: friday).dueTime == "12:00")
        // A bare number is quantity, not a time.
        #expect(QuickAddParser.parse("buy 6 eggs", today: friday).dueTime == nil)
    }

    @Test func tonightIsTodayAtEight() {
        let parse = QuickAddParser.parse("call mum tonight", today: friday)
        #expect(parse.dueDate == friday)
        #expect(parse.dueTime == "20:00")
        #expect(parse.title == "call mum")
    }

    @Test func priorityFlags() {
        #expect(QuickAddParser.parse("ship release !1", today: friday).priority == .high)
        #expect(QuickAddParser.parse("water plants !3", today: friday).priority == .low)
        #expect(QuickAddParser.parse("ship release !1", today: friday).title == "ship release")
    }

    @Test func categoryHashtag() {
        let categories = [category("c1", "Work"), category("c2", "Deep Work")]
        let parse = QuickAddParser.parse("write spec #work", today: friday, categories: categories)
        #expect(parse.categoryId == "c1")
        #expect(parse.title == "write spec")

        // Longest match wins, and a multi-word category can be typed unspaced.
        #expect(
            QuickAddParser.parse("write spec #deep work", today: friday, categories: categories)
                .categoryId == "c2",
        )
        #expect(
            QuickAddParser.parse("write spec #deepwork", today: friday, categories: categories)
                .categoryId == "c2",
        )
    }

    @Test func unknownCategoryStaysInTheTitle() {
        let parse = QuickAddParser.parse("write spec #nope", today: friday, categories: [category("c1", "Work")])
        #expect(parse.categoryId == nil)
        #expect(parse.title == "write spec #nope")
    }

    @Test func everythingAtOnce() {
        let categories = [category("c1", "Health")]
        let parse = QuickAddParser.parse("gym tomorrow 7pm !1 #health", today: friday, categories: categories)
        #expect(parse.title == "gym")
        #expect(parse.dueDate == "2026-08-01")
        #expect(parse.dueTime == "19:00")
        #expect(parse.priority == .high)
        #expect(parse.categoryId == "c1")
    }

    @Test func onlyTheFirstDatePhraseCounts() {
        // "monday" after "tomorrow" is part of the title, not a second date.
        let parse = QuickAddParser.parse("prep tomorrow for monday", today: friday)
        #expect(parse.dueDate == "2026-08-01")
        #expect(parse.title == "prep for monday")
    }
}
