//
//  SimpleBudgetTests.swift
//  SimpleBudgetTests
//
//  Created by Dionicy Tarantino on 12/2/25.
//

import Testing
@testable import SimpleBudget

// Unit tests covering angle calculations and transaction amount parsing
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

    @Test func dialRangeTracksRemainingBudgetAfterPreviousSpending() async throws {
        let monthlyBudget: Double = 1_200
        let transactions = [200.0, 175.0, 25.0]
        let remaining = monthlyBudget - transactions.reduce(0, +)
        let spent = monthlyBudget - remaining

        let halfwaySelection = remaining / 2
        let metrics = BudgetDialScalingMetrics(
            amount: halfwaySelection,
            remainingBudget: remaining,
            monthlyBudget: monthlyBudget,
            currentSpent: spent
        )

        #expect(metrics.dialRange == remaining)
        #expect(metrics.primaryTrim == 0.5)
    }

    @Test func dialWrapsAfterSelectingBeyondRemainingBudget() async throws {
        let monthlyBudget: Double = 800
        let preExistingTransactions = [350.0]
        let remaining = monthlyBudget - preExistingTransactions.reduce(0, +)
        let spent = monthlyBudget - remaining

        let metrics = BudgetDialScalingMetrics(
            amount: 500,
            remainingBudget: remaining,
            monthlyBudget: monthlyBudget,
            currentSpent: spent
        )

        #expect(metrics.dialRange == remaining)
        #expect(metrics.primaryTrim == 1)
        #expect(metrics.knobRotationProgress == 0.25)
    }

    @Test func dialRangeCapsWhenRefundsExceedBudget() async throws {
        let monthlyBudget: Double = 500
        let surplusRemaining = 700.0
        let spent = monthlyBudget - surplusRemaining

        let metrics = BudgetDialScalingMetrics(
            amount: 0,
            remainingBudget: surplusRemaining,
            monthlyBudget: monthlyBudget,
            currentSpent: spent
        )

        #expect(metrics.dialRange == 500)
        #expect(metrics.primaryTrim == 0)
    }

    @Test func dialRangeCapsForPreviewOverage() async throws {
        let monthlyBudget: Double = 300
        let remaining = monthlyBudget
        let spent = monthlyBudget - remaining

        let metrics = BudgetDialScalingMetrics(
            amount: 800,
            remainingBudget: remaining,
            monthlyBudget: monthlyBudget,
            currentSpent: spent
        )

        #expect(metrics.dialRange == 500)
        #expect(metrics.primaryTrim == 1)
        #expect(metrics.knobRotationProgress == 0.6)
    }

    @Test func dialRangeCapsForExistingOverage() async throws {
        let monthlyBudget: Double = 400
        let currentSpent = 550.0
        let remaining = monthlyBudget - currentSpent

        let metrics = BudgetDialScalingMetrics(
            amount: 50,
            remainingBudget: remaining,
            monthlyBudget: monthlyBudget,
            currentSpent: currentSpent
        )

        #expect(metrics.dialRange == 500)
        #expect(metrics.primaryTrim == 0.1)
    }

}
