import Foundation
import Testing
@testable import Jarvis

/// The add field is one text field, so the split between amount and item has
/// to be predictable. These pin down where it does and does not split.
struct ShoppingLineParserTests {
    @Test func plainItemKeepsItsWholeName() {
        let parsed = ShoppingLineParser.parse("Chicken breast")
        #expect(parsed?.name == "Chicken breast")
        #expect(parsed?.quantity == nil)
    }

    @Test func splitsANumberAndUnitOffTheFront() {
        let parsed = ShoppingLineParser.parse("2 kg chicken")
        #expect(parsed?.quantity == "2 kg")
        #expect(parsed?.name == "chicken")
    }

    @Test func splitsABareNumber() {
        let parsed = ShoppingLineParser.parse("3 lemons")
        #expect(parsed?.quantity == "3")
        #expect(parsed?.name == "lemons")
    }

    @Test func handlesDecimalsInBothNotations() {
        #expect(ShoppingLineParser.parse("1.5 l milk")?.quantity == "1.5 l")
        #expect(ShoppingLineParser.parse("1,5 l milk")?.quantity == "1,5 l")
        #expect(ShoppingLineParser.parse("1,5 l milk")?.name == "milk")
    }

    @Test func handlesTheTimesShorthand() {
        let parsed = ShoppingLineParser.parse("6x eggs")
        #expect(parsed?.quantity == "6x")
        #expect(parsed?.name == "eggs")
    }

    @Test func doesNotSwallowTheUnitWhenNothingWouldBeLeft() {
        // "500 g" alone is not an item called "500" with unit "g".
        let parsed = ShoppingLineParser.parse("500 g")
        #expect(parsed?.quantity == "500")
        #expect(parsed?.name == "g")
    }

    @Test func leavesUnrecognisedLeadingWordsAlone() {
        let parsed = ShoppingLineParser.parse("Fresh basil")
        #expect(parsed?.name == "Fresh basil")
        #expect(parsed?.quantity == nil)
    }

    @Test func doesNotTreatOrdinalsAsAmounts() {
        let parsed = ShoppingLineParser.parse("2nd birthday candles")
        #expect(parsed?.name == "2nd birthday candles")
        #expect(parsed?.quantity == nil)
    }

    @Test func onlyAbsorbsAUnitItRecognises() {
        // "big" is not a unit, so it stays part of the item name.
        let parsed = ShoppingLineParser.parse("2 big pumpkins")
        #expect(parsed?.quantity == "2")
        #expect(parsed?.name == "big pumpkins")
    }

    @Test func trimsAndRejectsBlankInput() {
        #expect(ShoppingLineParser.parse("   ") == nil)
        #expect(ShoppingLineParser.parse("") == nil)
        #expect(ShoppingLineParser.parse("  milk  ")?.name == "milk")
    }
}

/// Bodyweight detection decides whether the logger shows a weight field, so a
/// wrong guess is a field you have to ignore mid-workout.
struct BodyweightHeuristicTests {
    @Test func recognisesCommonBodyweightMovements() {
        #expect(ExercisePickerView.looksBodyweight("Pull-up"))
        #expect(ExercisePickerView.looksBodyweight("Wide grip pull ups"))
        #expect(ExercisePickerView.looksBodyweight("Push-up"))
        #expect(ExercisePickerView.looksBodyweight("Plank"))
    }

    @Test func leavesLoadedMovementsAlone() {
        #expect(!ExercisePickerView.looksBodyweight("Bench press"))
        #expect(!ExercisePickerView.looksBodyweight("Squat"))
        #expect(!ExercisePickerView.looksBodyweight("Lat pulldown"))
    }
}
