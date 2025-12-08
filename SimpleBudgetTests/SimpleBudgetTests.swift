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

        #expect(metrics.dialRange == remaining + 500)
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

        #expect(metrics.dialRange == remaining + 500)
        #expect(metrics.primaryTrim == 1)
        #expect(metrics.knobRotationProgress == 1.1)
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

        #expect(metrics.dialRange == 1_000)
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

        #expect(metrics.dialRange == 800)
        #expect(metrics.primaryTrim == 1)
        #expect(metrics.knobRotationProgress == 2)
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
        #expect(metrics.primaryTrim == 1)
        #expect(metrics.normalizedProgress == 1.1)
    }

    @Test func normalizedProgressRemainsContinuousOverBudgetBoundary() async throws {
        let monthlyBudget: Double = 600
        let remaining = 450.0
        let spent = monthlyBudget - remaining

        let metrics = BudgetDialScalingMetrics(
            amount: remaining,
            remainingBudget: remaining,
            monthlyBudget: monthlyBudget,
            currentSpent: spent
        )

        #expect(metrics.normalizedProgress == 1)

        let overageMetrics = BudgetDialScalingMetrics(
            amount: remaining + 75,
            remainingBudget: remaining,
            monthlyBudget: monthlyBudget,
            currentSpent: spent
        )

        #expect(overageMetrics.normalizedProgress == 1.15)
    }

    @Test func categoriesAreFilteredAndUniquePerSettings() async throws {
        let activeSettings = BudgetSettings()
        let otherSettings = BudgetSettings()

        let food = BudgetCategory(name: "Food")
        food.settings = activeSettings

        let duplicateFood = BudgetCategory(name: "food")
        duplicateFood.settings = activeSettings

        let travel = BudgetCategory(name: "Travel")
        travel.settings = otherSettings

        let groceries = BudgetCategory(name: "Groceries")
        groceries.settings = activeSettings

        let sanitized = ContentView.sanitizedCategories(
            for: activeSettings,
            from: [food, duplicateFood, travel, groceries]
        )

        #expect(sanitized == ["Food", "Groceries"])
    }

    @Test func amountRoundTripsThroughProgressMapping() async throws {
        let monthlyBudget: Double = 1_000
        let remaining = 250.0
        let spent = monthlyBudget - remaining

        let metrics = BudgetDialScalingMetrics(
            amount: 0,
            remainingBudget: remaining,
            monthlyBudget: monthlyBudget,
            currentSpent: spent
        )

        let overBudgetProgress = metrics.progress(for: remaining + 125)
        #expect(metrics.amount(for: overBudgetProgress) == remaining + 125)

        let withinBudgetProgress = metrics.progress(for: remaining / 2)
        #expect(metrics.amount(for: withinBudgetProgress) == remaining / 2)
    }

    @Test func monthSummaryCardProgressHandlesInvalidBudgets() async throws {
        let cases: [(spent: Double, limit: Double, expected: Double)] = [
            (spent: 50, limit: 0, expected: 0),
            (spent: .nan, limit: 500, expected: 0),
            (spent: 100, limit: .nan, expected: 0),
            (spent: .infinity, limit: 200, expected: 0),
            (spent: 150, limit: .infinity, expected: 0),
            (spent: 100, limit: 200, expected: 0.5),
            (spent: 300, limit: 200, expected: 1)
        ]

        for scenario in cases {
            let progress = MonthSummaryCard.progress(for: scenario.spent, limit: scenario.limit)
            #expect(progress == scenario.expected)
        }
    }

}
