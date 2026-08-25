import Testing
@testable import JarvisAPI

/// Climbs a ladder from zero and collects what the buttons produce.
private func climb(_ style: LoadStyle, steps: Int) -> [Double] {
    var value = 0.0
    return (0..<steps).map { _ in
        value = style.stepped(value, direction: 1)
        return value
    }
}

@Suite("Weight ladders")
struct LoadStyleTests {
    @Test("a cable stack produces the numbers printed on the machine")
    func cableLadder() {
        // Copied off the stack: 5 lb plates, labelled in kilograms.
        let printed: [Double] = [
            2.3, 4.5, 6.8, 9, 11.3, 13.5, 15.8, 18, 20.3, 22.5,
            24.8, 27, 29.3, 31.5, 33.8, 36, 38.3, 40.5, 42.8, 45,
        ]
        #expect(climb(.cable, steps: printed.count) == printed)
    }

    @Test("dumbbells go up 1 kg to 10, then 2 kg")
    func dumbbellLadder() {
        #expect(climb(.dumbbell, steps: 14) == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 16, 18])
    }

    @Test("plates and machines are plain multiples")
    func linearLadders() {
        #expect(climb(.plates, steps: 4) == [2.5, 5, 7.5, 10])
        #expect(climb(.machine, steps: 4) == [5, 10, 15, 20])
        #expect(climb(.free, steps: 3) == [0.5, 1, 1.5])
    }

    @Test("stepping down retraces the way up")
    func downIsTheInverseOfUp() {
        for style in LoadStyle.allCases {
            let up = climb(style, steps: 25)
            for (index, value) in up.enumerated() where index > 0 {
                #expect(style.stepped(value, direction: -1) == up[index - 1])
            }
            #expect(style.stepped(up[0], direction: -1) == 0)
        }
    }

    @Test("zero never goes negative")
    func flooredAtZero() {
        for style in LoadStyle.allCases {
            #expect(style.stepped(0, direction: -1) == 0)
        }
    }

    @Test("a weight typed before the ladder existed snaps onto it")
    func legacyValuesSnap() {
        // Cable pushdowns were saved at 31 kg, which no cable stack can make.
        #expect(LoadStyle.cable.stepped(31, direction: 1) == 31.5)
        #expect(LoadStyle.cable.stepped(31, direction: -1) == 29.3)
        // Leg curls at 77 on a 5 kg stack.
        #expect(LoadStyle.machine.stepped(77, direction: 1) == 80)
        #expect(LoadStyle.machine.stepped(77, direction: -1) == 75)
        // A barbell at 101.
        #expect(LoadStyle.plates.stepped(101, direction: 1) == 102.5)
        #expect(LoadStyle.plates.stepped(101, direction: -1) == 100)
    }

    @Test("the name guess matches the SQL backfill")
    func guessing() {
        #expect(LoadStyle.guessed(fromName: "Cable pushdowns (straight bar)") == .cable)
        #expect(LoadStyle.guessed(fromName: "Lat pulldown") == .cable)
        #expect(LoadStyle.guessed(fromName: "Incline dumbbell press") == .dumbbell)
        #expect(LoadStyle.guessed(fromName: "Leg press") == .machine)
        #expect(LoadStyle.guessed(fromName: "Seated back rows") == .machine)
        #expect(LoadStyle.guessed(fromName: "Supine bench press") == .plates)
        #expect(LoadStyle.guessed(fromName: "Weighted pullups") == .plates)
    }
}
