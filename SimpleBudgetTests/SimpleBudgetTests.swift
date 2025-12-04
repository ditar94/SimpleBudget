//
//  SimpleBudgetTests.swift
//  SimpleBudgetTests
//
//  Created by Dionicy Tarantino on 12/2/25.
//

import Testing
@testable import SimpleBudget

struct SimpleBudgetTests {

    @Test func clockwiseCrossesZeroWithSmallDelta() async throws {
        let delta = smallestSignedAngleDelta(from: 350, to: 10)
        #expect(delta == 20)
    }

    @Test func counterclockwiseCrossesZeroWithSmallDelta() async throws {
        let delta = smallestSignedAngleDelta(from: 10, to: 350)
        #expect(delta == -20)
    }

    @Test func clockwiseCrossesOneEightyWithSmallDelta() async throws {
        let delta = smallestSignedAngleDelta(from: 170, to: 190)
        #expect(delta == 20)
    }

    @Test func counterclockwiseCrossesOneEightyWithSmallDelta() async throws {
        let delta = smallestSignedAngleDelta(from: 190, to: 170)
        #expect(delta == -20)
    }

    @Test func accumulationRemainsContinuousAcrossWraps() async throws {
        let angles: [Double] = [350, 10, 30, 50]
        let totalDelta = angles
            .adjacentPairs()
            .map { previous, current in
                smallestSignedAngleDelta(from: previous, to: current)
            }
            .reduce(0, +)

        #expect(totalDelta == 60)
    }

    @Test func parsesThousandsSeparatedAmounts() async throws {
        var draft = TransactionDraft()
        draft.amountText = "1,200.50"

        #expect(draft.amount == 1200.5)
    }

    @Test func roundTripFormattingPreservesLargeAmount() async throws {
        var draft = TransactionDraft()
        draft.setAmount(1_523.75)

        var parsedDraft = TransactionDraft()
        parsedDraft.amountText = draft.amountText

        #expect(parsedDraft.amount == 1_523.75)
    }

}
