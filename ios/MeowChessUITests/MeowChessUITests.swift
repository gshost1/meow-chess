import XCTest

/// End-to-end tests that drive the app like a player. They use the real Chess.com API and the real
/// Rust engine. The AI tests talk to `scripts/mock_ai_server.py` on 127.0.0.1:8765; run everything
/// with `scripts/run-ui-tests.sh`. Tests run in name order and the later ones reuse the games
/// reviewed by the first.
final class MeowChessUITests: XCTestCase {
    let app = XCUIApplication()
    let user = "julius201"
    static let mockURL = "http://127.0.0.1:8765"

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        if let run = testRun, run.failureCount > 0 {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "failure-\(name)"
            shot.lifetime = .keepAlways
            add(shot)
        }
    }

    // MARK: Tests

    /// Fresh install: enter a username, download games, review one, use the quiz and best-move line,
    /// the summary, the coach tab and a practice puzzle.
    func test1_FreshInstallJourney() {
        app.launchArguments = ["-uiTesting", "-uiTestReset", "-strength", "fast"]
        app.launch()

        let name = app.textFields["Chess.com username"]
        XCTAssertTrue(name.waitForExistence(timeout: 15), "welcome screen should ask for a username")
        name.tap()
        name.typeText(user)
        app.buttons["Get my games"].tap()

        openFirstGame()
        waitForReview()

        // Board is drawn with all 32 pieces in the right places.
        XCTAssertTrue(square("e1").label.contains("white king"), square("e1").label)
        XCTAssertTrue(square("d8").label.contains("black queen"), square("d8").label)

        // Step forward to the player's own first move, where Meowy asks about the idea.
        let question = app.staticTexts["quiz-question"]
        for _ in 0..<3 where !question.exists { app.buttons["Next move"].tap() }
        XCTAssertTrue(question.waitForExistence(timeout: 5), "quiz should appear on the player's move")
        XCTAssertTrue(app.staticTexts["move-label"].label.contains("Your move"))

        let options = app.buttons.matching(NSPredicate(format: "identifier IN %@", [
            "quiz-attack", "quiz-kingAttack", "quiz-winMaterial", "quiz-trade", "quiz-defend",
            "quiz-develop", "quiz-castle", "quiz-center", "quiz-pawnPush", "quiz-improve",
        ]))
        XCTAssertEqual(options.count, 4, "quiz should offer four ideas")
        options.element(boundBy: 0).tap()
        XCTAssertTrue(quizFeedback().waitForExistence(timeout: 5), "quiz feedback should appear")
        XCTAssertFalse(question.exists)

        // Best move and its line.
        let showBest = app.buttons["show-best"]
        scrollTo(showBest)
        showBest.tap()
        let status = app.staticTexts["best-line-status"]
        if status.waitForExistence(timeout: 3) {
            XCTAssertEqual(status.label, "Tap → to play the line")
            app.buttons["Next move"].tap()
            XCTAssertTrue(status.label.hasPrefix("Move 1 of"), status.label)
        }
        scrollTo(showBest)
        XCTAssertTrue(showBest.label.contains("Back to the game"), showBest.label)
        showBest.tap()
        XCTAssertFalse(status.exists)

        // Jump to a mistake if the player made one.
        let nextMistake = app.buttons["next-mistake"]
        if nextMistake.isEnabled {
            nextMistake.tap()
            XCTAssertTrue(app.staticTexts["move-label"].label.contains("Your move"))
        }

        // Summary sheet.
        app.buttons["toolbar-summary"].tap()
        let summary = app.navigationBars["Summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your accuracy"].exists)
        dismissSheet()
        XCTAssertTrue(summary.waitForNonExistence(timeout: 5))

        // Ask Meowy without an AI set up explains that it's optional.
        app.buttons["Last position"].tap()
        app.buttons["Previous move"].tap()
        skipQuizIfShown()
        let ask = app.buttons["ask-meowy"]
        scrollTo(ask)
        ask.tap()
        XCTAssertTrue(app.staticTexts["Meowy's AI chat is optional"].waitForExistence(timeout: 5))
        dismissSheet()

        // Coach tab.
        app.tabBars.buttons["Meowy"].tap()
        XCTAssertTrue(app.staticTexts["how you actually play"].waitForExistence(timeout: 10))

        // Practice: make sure there is at least one puzzle, then solve it by tapping squares.
        app.tabBars.buttons["Practice"].tap()
        let prompt = app.staticTexts["puzzle-prompt"]
        if !prompt.waitForExistence(timeout: 3) {
            app.buttons["Review my last 10 games"].tap()
            XCTAssertTrue(prompt.waitForExistence(timeout: 900), "reviewing 10 games should produce a puzzle")
        }
        solvePuzzle()
        XCTAssertTrue(app.staticTexts["solved-count"].label.hasPrefix("Solved 1/"), app.staticTexts["solved-count"].label)

        // Next puzzle: hint, then show the answer.
        let next = app.buttons["Next puzzle"]
        next.tap()
        if app.buttons["Hint"].waitForExistence(timeout: 3) {
            app.buttons["Hint"].tap()
            XCTAssertTrue(feedbackText().contains("Hint"), feedbackText())
            app.buttons["Show answer"].tap()
            XCTAssertTrue(feedbackText().contains("The answer was"), feedbackText())
        }
    }

    /// Settings: sounds, a bring-your-own-key AI (mock server), Meowy chat, Jev reading a typed idea,
    /// and turning the quiz off.
    func test2_SettingsAndOptionalAI() {
        app.launchArguments = [
            "-uiTesting", "-username", user, "-strength", "fast", "-tab", "settings",
            "-aiBaseURL", "\(Self.mockURL)/v1", "-aiModel", "mock-meowy", "-jevURL", "\(Self.mockURL)/decisions",
        ]
        app.launch()

        let sound = app.switches["settings-sound"]
        XCTAssertTrue(sound.waitForExistence(timeout: 10))
        let before = sound.value as? String ?? "1"
        flip(sound)
        XCTAssertTrue(waitForValue(sound, before == "1" ? "0" : "1"), "sound switch should flip")
        flip(sound)
        XCTAssertTrue(waitForValue(sound, before), "sound switch should flip back")

        // Add a key and test the connection.
        let key = app.secureTextFields["settings-ai-key"]
        scrollTo(key)
        key.tap()
        key.typeText("test-key\n")
        let ret = app.keyboards.buttons["Return"].firstMatch
        if ret.exists { ret.tap() }
        let test = app.buttons["settings-ai-test"]
        scrollTo(test)
        test.tap()
        let result = app.staticTexts["settings-ai-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 20))
        XCTAssertTrue(result.label.contains("Connected"), result.label)
        XCTAssertTrue(result.label.contains("Mock Meowy"), result.label)

        let jev = app.switches["settings-jev"]
        scrollTo(jev)
        if jev.value as? String == "0" { flip(jev) }
        XCTAssertTrue(waitForValue(jev, "1"), "Jev switch should turn on")

        // In a review, type an idea in your own words and let Jev read it.
        app.tabBars.buttons["Games"].tap()
        openFirstGame()
        waitForReview()
        let typed = app.textFields["quiz-typed"]
        app.buttons["Last position"].tap()
        for _ in 0..<6 where !typed.exists { app.buttons["Previous move"].tap() }
        XCTAssertTrue(typed.waitForExistence(timeout: 5), "an unanswered move should offer the typed answer")
        typed.tap()
        typed.typeText("I wanted to attack the queen")
        app.buttons["quiz-send"].tap()
        let feedback = quizFeedback()
        XCTAssertTrue(feedback.waitForExistence(timeout: 20), "Jev answer should show feedback")
        XCTAssertTrue(feedback.label.contains("I wanted to attack the queen"), feedback.label)
        XCTAssertTrue(feedback.label.contains("Jev is 90% sure"), feedback.label)

        // Meowy chat with the AI set up.
        let ask = app.buttons["ask-meowy"]
        scrollTo(ask)
        ask.tap()
        let reply = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Mock Meowy here'")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 20), "Meowy's chat reply should appear")
        dismissSheet()

        // Turn the quiz off: an unanswered move shows the explanation straight away.
        app.tabBars.buttons["Settings"].tap()
        let picker = app.buttons["settings-quiz-mode"]
        scrollTo(picker)
        picker.tap()
        app.buttons["Off"].tap()
        app.tabBars.buttons["Games"].tap()
        app.buttons["First position"].tap()
        for _ in 0..<2 { app.buttons["Next move"].tap() }
        XCTAssertFalse(app.staticTexts["quiz-question"].exists, "quiz should be off")
        XCTAssertTrue(app.staticTexts["move-label"].exists)
    }

    // MARK: Helpers

    private func square(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)["square-\(name)"].firstMatch
    }

    private func waitForValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 3) -> Bool {
        let e = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        return XCTWaiter().wait(for: [e], timeout: timeout) == .completed
    }

    /// Half-height sheets close when you tap the dimmed area above them.
    private func dismissSheet() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
    }

    /// Taps the switch knob itself; tapping the middle of a SwiftUI toggle row hits the label.
    private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }

    private func openFirstGame() {
        let first = app.collectionViews.cells.element(boundBy: 0)
        XCTAssertTrue(first.waitForExistence(timeout: 60), "games should download from Chess.com")
        first.tap()
    }

    private func waitForReview() {
        XCTAssertTrue(app.buttons["Next move"].waitForExistence(timeout: 300), "review should finish")
    }

    private func skipQuizIfShown() {
        let skip = app.buttons["quiz-skip"]
        if skip.exists {
            scrollTo(skip)
            skip.tap()
        }
    }

    private func solvePuzzle() {
        let answer = app.staticTexts["puzzle-answer"].label
        XCTAssertGreaterThanOrEqual(answer.count, 4, "puzzle answer should be a UCI move")
        let from = String(answer.prefix(2)), to = String(answer.dropFirst(2).prefix(2))
        square(from).tap()
        XCTAssertTrue(square(from).isSelected, "tapped piece should be selected")
        square(to).tap()
        XCTAssertTrue(feedbackText().contains("Purrfect"), feedbackText())
    }

    private func quizFeedback() -> XCUIElement {
        app.descendants(matching: .any)["quiz-feedback"].firstMatch
    }

    private func feedbackText() -> String {
        app.descendants(matching: .any)["puzzle-feedback"].firstMatch.label
    }

    /// Scrolls the review card (or the Settings form) until the element can be tapped.
    /// Forms load rows lazily, so the element may not exist until it has been scrolled to.
    private func scrollTo(_ element: XCUIElement) {
        let info = app.scrollViews["info-scroll"]
        let container = info.exists && info.isHittable ? info : app.collectionViews.firstMatch
        _ = element.waitForExistence(timeout: 3)
        var tries = 0
        // The floating tab bar and keyboard cover the bottom of the screen, so "hittable" isn't enough.
        let visibleBottom = container == info ? info.frame.maxY + 1 : app.frame.maxY - 160
        func onScreen() -> Bool { element.exists && element.isHittable && element.frame.maxY < visibleBottom }
        while !onScreen() && tries < 16 {
            if tries < 8 { container.swipeUp(velocity: .slow) } else { container.swipeDown(velocity: .slow) }
            tries += 1
        }
        XCTAssertTrue(onScreen(), "\(element) should be on screen")
    }
}
