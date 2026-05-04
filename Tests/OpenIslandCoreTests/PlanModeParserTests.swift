import Foundation
import Testing
@testable import OpenIslandCore

struct PlanModeParserTests {
    @Test
    func emptyMarkdownReturnsEmpty() {
        #expect(PlanModeParser.parse("") == [])
    }

    @Test
    func simpleBulletList() {
        let plan = """
        - First step
        - Second step
        - Third step
        """
        let steps = PlanModeParser.parse(plan)
        #expect(steps.map(\.title) == ["First step", "Second step", "Third step"])
        #expect(steps.allSatisfy { $0.depth == 0 })
    }

    @Test
    func numberedList() {
        let plan = """
        1. Initialize state
        2. Render UI
        3) Wire callbacks
        """
        let steps = PlanModeParser.parse(plan)
        #expect(steps.map(\.title) == ["Initialize state", "Render UI", "Wire callbacks"])
    }

    @Test
    func headingsBecomeSteps() {
        let plan = """
        ## Phase 1
        ### Sub-task
        """
        let steps = PlanModeParser.parse(plan)
        #expect(steps.count == 2)
        #expect(steps[0].title == "Phase 1")
        #expect(steps[0].depth == 0)
        #expect(steps[1].title == "Sub-task")
        #expect(steps[1].depth == 1)
    }

    @Test
    func nestedBulletsTrackIndentation() {
        let plan = """
        - Top
          - Nested once
            - Nested twice
        """
        let steps = PlanModeParser.parse(plan)
        #expect(steps.count == 3)
        #expect(steps[0].depth == 0)
        #expect(steps[1].depth == 1)
        #expect(steps[2].depth == 2)
    }

    @Test
    func skipsBlankAndUnstructuredLines() {
        let plan = """
        Some intro text.

        - One

        - Two
        """
        let steps = PlanModeParser.parse(plan)
        #expect(steps.map(\.title) == ["One", "Two"])
    }

    @Test
    func sameTitleProducesSameID() {
        let a = PlanModeParser.parse("- Hello")
        let b = PlanModeParser.parse("- Hello")
        #expect(a == b)
        #expect(a.first?.id == b.first?.id)
    }

    @Test
    func differentDepthsProduceDifferentIDs() {
        let a = PlanModeParser.parse("- Hello").first
        let b = PlanModeParser.parse("  - Hello").first
        #expect(a?.title == b?.title)
        #expect(a?.id != b?.id)
    }

    @Test
    func mixedHeadingsAndBullets() {
        let plan = """
        ## Implementation
        - Edit AppModel.swift
        - Add new view
        ## Verification
        - Run tests
        """
        let steps = PlanModeParser.parse(plan)
        #expect(steps.count == 5)
        #expect(steps[0].title == "Implementation")
        #expect(steps[0].depth == 0)
        #expect(steps[1].title == "Edit AppModel.swift")
        #expect(steps[3].title == "Verification")
    }

    @Test
    func malformedHeadingMissingSpaceIgnored() {
        // `##No space` is not valid markdown — ignored.
        #expect(PlanModeParser.parse("##No space") == [])
    }

    @Test
    func malformedBulletMissingSpaceIgnored() {
        #expect(PlanModeParser.parse("-foo") == [])
    }
}

struct PlanFilePathClassifierTests {
    @Test
    func docsPlansPathRecognized() {
        #expect(PlanFilePathClassifier.looksLikePlan("docs/plans/2026-05-04-foo.md"))
        #expect(PlanFilePathClassifier.looksLikePlan("/abs/path/docs/plans/x-design.md"))
    }

    @Test
    func gsdPlanningRecognized() {
        #expect(PlanFilePathClassifier.looksLikePlan(".planning/phase-1/PLAN.md"))
        #expect(PlanFilePathClassifier.looksLikePlan("/repo/.planning/foo.md"))
    }

    @Test
    func planSuffixRecognized() {
        #expect(PlanFilePathClassifier.looksLikePlan("foo-plan.md"))
        #expect(PlanFilePathClassifier.looksLikePlan("foo_plan.md"))
        #expect(PlanFilePathClassifier.looksLikePlan("plan.md"))
    }

    @Test
    func nonMarkdownIsNotAPlan() {
        #expect(!PlanFilePathClassifier.looksLikePlan("docs/plans/foo.txt"))
        #expect(!PlanFilePathClassifier.looksLikePlan("docs/plans/script.swift"))
    }

    @Test
    func unrelatedMarkdownIsNotAPlan() {
        #expect(!PlanFilePathClassifier.looksLikePlan("README.md"))
        #expect(!PlanFilePathClassifier.looksLikePlan("docs/architecture.md"))
        #expect(!PlanFilePathClassifier.looksLikePlan("CHANGELOG.md"))
    }

    @Test
    func caseInsensitive() {
        #expect(PlanFilePathClassifier.looksLikePlan("DOCS/PLANS/foo.md"))
        #expect(PlanFilePathClassifier.looksLikePlan(".PLANNING/foo.md"))
    }
}
