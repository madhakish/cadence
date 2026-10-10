import XCTest

final class VisualProofUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "--visual-proof",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"
        ]
        app.launch()
        XCTAssertTrue(element("home-screen").waitForExistence(timeout: 20))
    }

    func test01HomeAndAdHocWork() {
        capture("after-01-home-iphone")

        let activity = app.buttons["activity-quick-log"]
        for _ in 0..<4 where !activity.isHittable { app.swipeUp() }
        XCTAssertTrue(activity.waitForExistence(timeout: 3))
        activity.tap()
        XCTAssertTrue(element("activity-log-screen").waitForExistence(timeout: 5))
        capture("after-02-ad-hoc-work-iphone")
    }

    func test02CurrentSessionAndExactPlateStack() {
        app.buttons["resume-session"].tap()
        XCTAssertTrue(element("active-session-screen").waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["CURRENT SET · NEXT ACTION"].waitForExistence(timeout: 3))
        capture("after-03-current-session-iphone")
        let inspect = app.buttons["expand-loaded-bar"].firstMatch
        let window = app.windows.firstMatch.frame
        let visible = CGRect(x: window.minX, y: window.minY + 100,
                             width: window.width, height: window.height - 220)
        for _ in 0..<5 where !visible.contains(inspect.frame) { app.swipeUp() }
        XCTAssertTrue(inspect.isHittable)
        XCTAssertTrue(visible.contains(inspect.frame))
        capture("after-03b-current-set-plates-iphone")
    }

    func test03ExercisePaneAndPreservedAnatomy() {
        app.buttons["resume-session"].tap()
        XCTAssertTrue(element("active-session-screen").waitForExistence(timeout: 8))
        app.buttons["exercise-info-Back Squat"].tap()
        XCTAssertTrue(element("exercise-detail-screen").waitForExistence(timeout: 6))
        capture("after-04-exercise-pane-iphone")

        // #184: tiers 2 and 3 open beneath tier 1, which does not move. The
        // list is scrolled back to its top before the frame is compared.
        let prescription = app.staticTexts["CURRENT PRESCRIPTION"]
        XCTAssertTrue(prescription.waitForExistence(timeout: 3))
        let tierOne = prescription.frame
        openDisclosure("Previous performance & programming")
        XCTAssertTrue(app.staticTexts["Last done"].waitForExistence(timeout: 3))
        openDisclosure("Muscles & relationship")
        for rotation in 1...4 {
            let reps = element("cycle-plan-reps-\(rotation)")
            XCTAssertTrue(reps.waitForExistence(timeout: 3))
            XCTAssertGreaterThanOrEqual(reps.frame.minX, 0)
            XCTAssertLessThanOrEqual(reps.frame.maxX, app.windows.firstMatch.frame.maxX,
                                     "Expanded programming prescriptions must fit the phone width")
        }
        capture("after-04b-exercise-pane-tiers-open-iphone")
        for _ in 0..<6 where !prescription.isHittable { app.swipeDown() }
        XCTAssertEqual(prescription.frame.origin.y, tierOne.origin.y, accuracy: 1,
                       "tier 1 moved when tiers 2 and 3 opened")

        let frontLabel = app.staticTexts["Front"]
        for _ in 0..<4 where !frontLabel.isHittable { app.swipeUp() }
        XCTAssertTrue(frontLabel.waitForExistence(timeout: 3))
        capture("after-05-anatomy-unselected-iphone")

        let quads = app.buttons["Quads, primary muscle"]
        for _ in 0..<4 where !quads.isHittable { app.swipeUp() }
        XCTAssertTrue(quads.waitForExistence(timeout: 3))
        quads.tap()
        for _ in 0..<4 where !frontLabel.isHittable { app.swipeDown() }
        XCTAssertTrue(frontLabel.isHittable)
        capture("after-06-anatomy-selected-iphone")
    }

    func test04PlateCalculatorHero() {
        app.buttons["Plate calculator"].tap()
        XCTAssertTrue(element("plate-calculator-screen").waitForExistence(timeout: 6))
        let target = app.textFields["plate-target"]
        XCTAssertTrue(target.waitForExistence(timeout: 3))
        target.tap()
        target.typeText("139")
        let keyboardDone = app.buttons["plate-target-done"]
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: 3))
        keyboardDone.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        let achieved = app.staticTexts["ACHIEVED WITH BAR"]
        for _ in 0..<3 where !achieved.isHittable { app.swipeUp() }
        XCTAssertTrue(achieved.isHittable)
        capture("after-07-plate-calculator-iphone")

        let inspect = element("expand-loaded-bar")
        for _ in 0..<3 where !inspect.isHittable { app.swipeUp() }
        XCTAssertTrue(inspect.isHittable)
        inspect.tap()
        XCTAssertTrue(app.navigationBars["Loaded bar"].waitForExistence(timeout: 5))
        let toggle = app.buttons["barbell-explode-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        assertInspectorState("Assembled", button: toggle)
        // The calculator beneath this sheet has its own accessible bar.
        // The artwork is the SceneKit solid where Metal is available and the
        // sprite scroll view otherwise; both expose the same plate children.
        let artwork = element("barbell-inspection-artwork")
        let firstLeft = artwork.staticTexts["barbell-plate-left-0"]
        XCTAssertTrue(firstLeft.waitForExistence(timeout: 3))
        XCTAssertTrue(firstLeft.label.contains("plate, 1 from inside, left side"), firstLeft.label)
        XCTAssertTrue(firstLeft.label.contains("kg"), "a kg plate on the lb proof bar keeps its unit")
        XCTAssertTrue(artwork.staticTexts["barbell-plate-right-0"].exists)
        capture("barbell-assembled-iphone")
        toggle.tap()
        assertInspectorState("Exploded", button: toggle)
        capture("barbell-exploded-iphone")
        XCTAssertFalse(app.buttons["barbell-reset-view"].exists, "inspection has exactly two authored views")
        XCTAssertFalse(app.segmentedControls["barbell-backdrop"].exists)
        toggle.tap()
        assertInspectorState("Assembled", button: toggle)

        app.navigationBars["Loaded bar"].buttons["Done"].tap()
        let equipment = app.buttons["Equipment & loading"]
        for _ in 0..<10 where !equipment.isHittable { app.swipeUp() }
        XCTAssertTrue(equipment.isHittable)
        equipment.tap()
        app.segmentedControls.buttons["Bumper"].tap()
        for _ in 0..<10 where !inspect.isHittable { app.swipeDown() }
        XCTAssertTrue(inspect.isHittable)
        inspect.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        toggle.tap()
        assertInspectorState("Exploded", button: toggle)
        capture("barbell-bumper-exploded-iphone")
    }

    /// #196: the floating plate button must never sit on top of a control.
    /// Every tab root is scrolled to its end, then every hittable control's
    /// frame is checked against the button's. The reserved band
    /// (plateCalculatorClearance on each root list) is what makes this hold
    /// at large text too. The active session is a cover with its own bottom
    /// bar and no floating button, which the test states rather than
    /// measures. Failures accumulate so one run reports every surface.
    func test08PlateButtonNeverCoversContent() {
        continueAfterFailure = true
        let plate = app.buttons["Plate calculator"]
        XCTAssertTrue(plate.waitForExistence(timeout: 5))
        for tab in ["Settings", "History", "Program", "Body", "Today"] {
            app.tabBars.buttons[tab].tap()
            assertScrolledEndClearsPlateButton(tab.lowercased(), button: plate)
        }
        // Today was just scrolled to its end; bring the resume card back.
        let resume = app.buttons["resume-session"]
        for _ in 0..<6 where !resume.isHittable { app.swipeDown() }
        XCTAssertTrue(resume.isHittable)
        resume.tap()
        XCTAssertTrue(element("active-session-screen").waitForExistence(timeout: 8))
        for _ in 0..<6 { app.swipeUp() }
        capture("after-11-session-end-clears-plate-button-iphone")
        XCTAssertFalse(plate.isHittable, "the session cover has no floating plate button; its bottom bar owns that band")
    }

    private func assertScrolledEndClearsPlateButton(_ surface: String, button plate: XCUIElement) {
        for _ in 0..<6 { app.swipeUp() }
        // Capture BEFORE asserting so the artifact shows the state that was
        // judged, pass or fail.
        capture("after-11-\(surface)-end-clears-plate-button-iphone")
        let button = plate.frame
        let queries = [app.buttons, app.cells, app.switches, app.textFields, app.segmentedControls, app.staticTexts]
        for query in queries {
            for control in query.allElementsBoundByIndex
            where control.isHittable && control.label != "Plate calculator" && !control.frame.isEmpty {
                XCTAssertFalse(control.frame.intersects(button),
                               "\(surface): '\(control.label)' \(control.frame) sits under the plate calculator button \(button)")
            }
        }
    }

    func test09WorkoutPreviewInspection() {
        let preview = app.buttons["preview-program-day"]
        for _ in 0..<10 where !preview.isHittable { app.swipeUp() }
        XCTAssertTrue(preview.isHittable)
        preview.tap()
        XCTAssertTrue(element("workout-preview-screen").waitForExistence(timeout: 5))
        capture("barbell-workout-preview-iphone")
        let inspect = app.buttons["expand-loaded-bar"].firstMatch
        for _ in 0..<5 where !inspect.isHittable { app.swipeUp() }
        XCTAssertTrue(inspect.isHittable)
        inspect.tap()
        XCTAssertTrue(app.buttons["barbell-explode-toggle"].waitForExistence(timeout: 3))
        capture("barbell-workout-preview-inspection-iphone")
    }

    func test10PlankCountdownAndLog() {
        app.terminate()
        app.launchArguments += ["--hold-timer-proof", "--hold-short-proof"]
        app.launch()
        XCTAssertTrue(app.buttons["resume-session"].waitForExistence(timeout: 20))
        app.buttons["resume-session"].tap()
        let start = app.buttons["start-hold-timer"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        allowHoldNotificationsIfPrompted()
        let log = app.buttons["hold-timer-log"]
        XCTAssertTrue(log.waitForExistence(timeout: 10))
        XCTAssertEqual(element("hold-timer-status").label, "HOLD COMPLETE")
        XCTAssertEqual(element("hold-timer-clock").value as? String, "3 seconds")
        capture("plank-target-complete-iphone")
        log.tap()
        XCTAssertTrue(app.navigationBars["Hold timer"].waitForNonExistence(timeout: 5))
    }

    func test11PlankTimerAtAccessibilityTextSize() {
        app.terminate()
        app.launchArguments += ["--hold-timer-proof",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["resume-session"].waitForExistence(timeout: 20))
        app.buttons["resume-session"].tap()
        let start = app.buttons["start-hold-timer"].firstMatch
        for _ in 0..<6 where !start.isHittable { app.swipeUp() }
        XCTAssertTrue(start.isHittable)
        start.tap()
        allowHoldNotificationsIfPrompted()
        let stop = app.buttons["hold-timer-stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        capture("plank-countdown-accessibility-iphone")
        for _ in 0..<3 where !stop.isHittable { app.swipeUp() }
        stop.tap()
        XCTAssertEqual(element("hold-timer-status").label, "STOPPED")
        app.navigationBars["Hold timer"].buttons["Close"].tap()
        app.buttons["Discard attempt"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5), "Discard keeps the set planned")
    }

    private func allowHoldNotificationsIfPrompted() {
        for owner in [app!, XCUIApplication(bundleIdentifier: "com.apple.springboard")] {
            let allow = owner.alerts.buttons["Allow"].firstMatch
            if allow.waitForExistence(timeout: 2) { allow.tap(); return }
        }
    }

    func test05SettingsAndHistory() {
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(element("settings-screen").waitForExistence(timeout: 5))
        capture("after-09-settings-iphone")
        openDisclosure("Rest & training behavior")
        let duration = app.buttons["Squat & deadlift mains"]
        XCTAssertTrue(duration.waitForExistence(timeout: 3))
        // Bring the whole row below navigation chrome before tapping it;
        // isHittable alone can be true for a partially obscured list row.
        let window = app.windows.firstMatch.frame
        let visible = CGRect(x: window.minX, y: window.minY + 100,
                             width: window.width, height: window.height - 220)
        for _ in 0..<10 where !visible.contains(duration.frame) {
            // Full-screen swipes bounce this short row across the viewport
            // in a plain List. Pan by about 130 points to land it in the cut.
            let above = duration.frame.minY < visible.minY
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.45 : 0.65))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.60 : 0.50))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        XCTAssertTrue(visible.contains(duration.frame))
        capture("after-settings-rest-iphone")
        duration.tap()
        XCTAssertTrue(app.textFields["Hours"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Minutes"].exists)
        XCTAssertTrue(app.textFields["Seconds"].exists)
        capture("after-duration-picker-iphone")
        app.navigationBars.buttons["Cancel"].firstMatch.tap()

        let sound = app.switches["Completion sound"]
        for _ in 0..<10 where !visible.contains(sound.frame) {
            let above = sound.frame.minY < visible.minY
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.45 : 0.65))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.60 : 0.50))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        XCTAssertTrue(sound.isHittable)
        XCTAssertTrue(visible.contains(sound.frame), "The complete audio switch must be clear of the tab bar")
        capture("after-settings-audio-iphone")

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(element("history-screen").waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Log"].tap()
        let activitySummary = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Ad-hoc work ·'")
        ).firstMatch
        XCTAssertTrue(activitySummary.waitForExistence(timeout: 5))
        capture("after-10-history-ad-hoc-iphone")

        let activityRow = app.staticTexts["Wood Splitting"].firstMatch
        XCTAssertTrue(activityRow.waitForExistence(timeout: 3))
        activityRow.swipeLeft()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.tap()
        let deleteConfirmation = app.buttons["Delete activity"]
        XCTAssertTrue(deleteConfirmation.waitForExistence(timeout: 3))
        let cancel = app.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 1) {
            cancel.tap()
        } else {
            let dismissRegion = element("PopoverDismissRegion")
            XCTAssertTrue(dismissRegion.waitForExistence(timeout: 3))
            dismissRegion.tap()
        }
        XCTAssertTrue(deleteConfirmation.waitForNonExistence(timeout: 3))
        XCTAssertTrue(activitySummary.waitForExistence(timeout: 3), "cancelling keeps the banked activity")
    }

    func test06ComplementaryTrainingFocusIsTruthful() {
        app.buttons["resume-session"].tap()
        XCTAssertTrue(element("active-session-screen").waitForExistence(timeout: 8))
        let complementary = app.buttons["exercise-info-Romanian Deadlift"]
        for _ in 0..<8 where !complementary.isHittable { app.swipeUp() }
        XCTAssertTrue(complementary.waitForExistence(timeout: 4))
        complementary.tap()
        XCTAssertTrue(element("exercise-detail-screen").waitForExistence(timeout: 6))
        // The relationship is tier 3 context: one expand, never in the prescription.
        openDisclosure("Muscles & relationship")
        let focus = element("training-focus-context")
        XCTAssertTrue(focus.waitForExistence(timeout: 3))
        XCTAssertEqual(focus.label, "Complementary lift · Hypertrophy focus")
        XCTAssertFalse(app.staticTexts["Target 2–3 reps left. Adjust the next set if the load misses that range."].exists)
    }

    func test07FinalSetAdvancesToNextAuthoredExercise() {
        app.buttons["resume-session"].tap()
        XCTAssertTrue(element("active-session-screen").waitForExistence(timeout: 8))
        XCTAssertTrue(element("current-exercise-Back Squat").waitForExistence(timeout: 3))

        // The proof fixture starts on squat work set 2 of 3. Resolve both;
        // focus must move to the next authored lift without another tap.
        for _ in 0..<2 {
            let status = app.buttons["Set status"].firstMatch
            XCTAssertTrue(status.waitForExistence(timeout: 3))
            status.tap()
        }
        XCTAssertTrue(element("current-exercise-Romanian Deadlift").waitForExistence(timeout: 5))
        XCTAssertFalse(element("current-exercise-Back Squat").exists)
    }

    /// Xcode's accessibility audit over the surfaces a lifter touches most.
    /// Every issue on a surface is collected and reported together, so one
    /// run names the whole list instead of the first unlabeled control (#61).
    func test12AccessibilityAudit() throws {
        // Captures pin one text size for comparisons. The audit must be able
        // to vary the system preference, so remove that override for this test.
        app.terminate()
        let category = try XCTUnwrap(app.launchArguments.firstIndex(of: "-UIPreferredContentSizeCategoryName"))
        app.launchArguments.removeSubrange(category...(category + 1))
        app.launch()
        XCTAssertTrue(element("home-screen").waitForExistence(timeout: 20))
        continueAfterFailure = true
        try auditSurface("today")

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(element("settings-screen").waitForExistence(timeout: 5))
        try auditSurface("settings")

        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(element("home-screen").waitForExistence(timeout: 5))
        app.buttons["resume-session"].tap()
        XCTAssertTrue(element("active-session-screen").waitForExistence(timeout: 8))
        try auditSurface("current-session")

        // The session is a full-screen cover with no floating button; a fresh
        // launch lands on Today, where the calculator is one tap away.
        app.launch()
        XCTAssertTrue(element("home-screen").waitForExistence(timeout: 20))
        let calculator = app.buttons["Plate calculator"]
        XCTAssertTrue(calculator.waitForExistence(timeout: 3))
        calculator.tap()
        XCTAssertTrue(element("plate-calculator-screen").waitForExistence(timeout: 6))
        try auditSurface("plate-calculator")
    }

    private func auditSurface(_ name: String) throws {
        var issues: [String] = []
        var advisories: [String] = []
        // Judged against the app's surface, not system chrome or artwork:
        // - contrast under the translucent tab bar / floating plate button
        //   measures chrome (the first device run flagged exactly those);
        // - contrast of a plate badge measures the photographic plate face
        //   behind it, not the badge's own ink/fill pair;
        // - hit-region findings on non-interactive nodes (static text, a
        //   progress bar, plain containers) are not tap targets;
        // - clipping is left out because SwiftUI Labels audit as clipped
        //   while the captures show them intact;
        // - Dynamic Type findings remain raw advisories, except plate-target;
        //   neither a passing audit nor screenshots establish full AA.
        let chrome = [app.tabBars.firstMatch.frame, app.buttons["Plate calculator"].frame]
        let nonInteractive: [XCUIElement.ElementType] = [.staticText, .other, .progressIndicator, .image]
        let types: XCUIAccessibilityAuditType = [
            .sufficientElementDescription, .hitRegion, .contrast, .dynamicType,
            .trait, .elementDetection,
        ]
        try app.performAccessibilityAudit(for: types) { issue in
            let element = issue.element
            let identifier = element?.identifier ?? ""
            if issue.auditType == .contrast, let frame = element?.frame,
               chrome.contains(where: { $0.intersects(frame) }) || identifier.hasPrefix("barbell-plate-") {
                return true
            }
            if issue.auditType == .hitRegion, let element, nonInteractive.contains(element.elementType) {
                return true
            }
            let line = "\(issue.auditType): \(issue.detailedDescription) — \(element.map { "\($0)" } ?? "(no element)")"
            // A finding with no element names nothing a fix could target; it
            // is recorded with the advisories rather than failing the surface.
            if issue.auditType == .dynamicType && identifier == "plate-target" {
                issues.append(line) // #238: the calculator input must scale.
            } else if issue.auditType == .dynamicType || element == nil {
                advisories.append(line)
            } else {
                issues.append(line)
            }
            return true // keep collecting; the assertion below reports the full list
        }
        capture("after-12-audit-\(name)-iphone")
        if !advisories.isEmpty {
            let note = XCTAttachment(string: advisories.joined(separator: "\n"))
            note.name = "dynamic-type-advisories-\(name)"
            note.lifetime = .keepAlways
            add(note)
            print("Dynamic Type advisories on \(name):\n" + advisories.joined(separator: "\n"))
        }
        XCTAssertTrue(issues.isEmpty,
                      "\(name) failed the accessibility audit:\n" + issues.joined(separator: "\n"))
    }

    /// #185: completing a set must not move the dominant block. The set track
    /// and the current-set hero keep their frames; only their content
    /// advances to the next set.
    func test13SetCompletionKeepsDominantBlockStill() {
        app.buttons["resume-session"].tap()
        XCTAssertTrue(element("active-session-screen").waitForExistence(timeout: 8))
        let track = app.otherElements["Working sets"].firstMatch
        let hero = element("current-set-hero")
        XCTAssertTrue(track.waitForExistence(timeout: 3))
        XCTAssertTrue(hero.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["WORKING SET 2 OF 3"].exists)
        let trackBefore = track.frame
        let heroBefore = hero.frame
        capture("after-13-session-before-set-iphone")

        let status = app.buttons["Set status"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        status.tap()
        XCTAssertTrue(app.staticTexts["WORKING SET 3 OF 3"].waitForExistence(timeout: 3))
        capture("after-13-session-after-set-iphone")
        XCTAssertEqual(track.frame.origin.y, trackBefore.origin.y, accuracy: 0.5, "set track moved on completion")
        XCTAssertEqual(track.frame.height, trackBefore.height, accuracy: 0.5, "set track resized on completion")
        XCTAssertEqual(hero.frame.origin.y, heroBefore.origin.y, accuracy: 0.5, "current-set hero moved on completion")
        XCTAssertEqual(hero.frame.height, heroBefore.height, accuracy: 0.5, "current-set hero resized on completion")
    }

    /// #238: the editable load follows Dynamic Type without pushing its unit
    /// control offscreen or changing the entered value when units switch.
    func test14CalculatorTargetAtAccessibilityTextSize() {
        var standardHeight: CGFloat = 0
        for (category, name) in [
            ("UICTContentSizeCategoryL", "standard"),
            ("UICTContentSizeCategoryAccessibilityXXXL", "accessibility")
        ] {
            app.terminate()
            app.launchArguments[app.launchArguments.count - 1] = category
            app.launch()
            XCTAssertTrue(element("home-screen").waitForExistence(timeout: 20))
            app.buttons["Plate calculator"].tap()
            XCTAssertTrue(element("plate-calculator-screen").waitForExistence(timeout: 6))
            let target = app.textFields["plate-target"]
            for _ in 0..<4 where !target.isHittable { app.swipeUp() }
            XCTAssertTrue(target.isHittable)
            target.tap()
            target.typeText("139")
            let done = app.buttons["plate-target-done"]
            XCTAssertTrue(done.waitForExistence(timeout: 6))
            done.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))

            let units = app.segmentedControls["plate-target-unit"]
            let window = app.windows.firstMatch.frame
            let top = app.navigationBars["Plates"].frame.maxY
            let inputViewport = CGRect(x: window.minX, y: top, width: window.width,
                                       height: window.maxY - top - 34)
            let inputRow = app.cells.containing(.textField, identifier: "plate-target").firstMatch
            revealRootListRows([inputRow], viewport: inputViewport)
            // The plain List pins the scrolled section's header over the top
            // of this row at accessibility sizes, and the frame check above
            // cannot see that. Nudge the row back below the header, then wait.
            for _ in 0..<2 where !target.isHittable {
                scrollRootList(by: 80, viewport: inputViewport)
            }
            let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: target)
            XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 6), .completed,
                           "the target must be tappable once the keyboard has closed; field \(target.frame), row \(inputRow.frame), viewport \(inputViewport)")
            XCTAssertTrue(units.buttons["lb"].isHittable)
            XCTAssertTrue(units.buttons["kg"].isHittable)
            XCTAssertTrue(app.windows.firstMatch.frame.contains(target.frame))
            XCTAssertEqual(target.value as? String, "139")
            if name == "standard" {
                standardHeight = target.frame.height
            } else {
                XCTAssertGreaterThan(target.frame.height, standardHeight * 1.25,
                                     "the target must grow with accessibility text size")
                XCTAssertGreaterThanOrEqual(units.frame.minY, target.frame.maxY,
                                           "units must flow below the enlarged input")
            }
            capture("after-14-calculator-target-\(name)-iphone")
            units.buttons["kg"].tap()
            XCTAssertTrue(units.buttons["kg"].isSelected)
            XCTAssertEqual(target.value as? String, "139", "switching units preserves the entered number")
        }
    }

    /// Scrolls a DisclosureGroup's label into the window and taps it. XCUI
    /// never reports SwiftUI disclosure labels as hittable, so the tap goes
    /// through a coordinate once the label's frame sits inside the window.
    private func openDisclosure(_ label: String) {
        let text = app.staticTexts[label]
        // List rows are lazy: a label far below the fold does not exist in
        // the hierarchy until the list scrolls near it.
        for _ in 0..<8 where !text.exists { app.swipeUp() }
        XCTAssertTrue(text.waitForExistence(timeout: 3), "\(label) is on this screen")
        let window = app.windows.firstMatch.frame.insetBy(dx: 0, dy: 120)
        for _ in 0..<6 where !window.contains(text.frame) { app.swipeUp() }
        XCTAssertTrue(window.contains(text.frame), "\(label) scrolled into view")
        text.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func assertInspectorState(_ expected: String, button: XCUIElement) {
        // Wait for the actual accessible state after one tap; no second tap
        // or test retry can mask a non-working toggle.
        let state = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [state], timeout: 3), .completed,
                       "Inspector must reach \(expected) after one action")
        XCTAssertEqual(button.value as? String, expected)
    }

    /// #55: the loaded-bar inspection under each shipped plate theme. The
    /// proof seed reads `--plate-theme=<id>` and puts it on the fixture gym,
    /// so every relaunch shows the same 139 lb target in a different theme:
    /// both authored views, captured for the owner's visual judgement.
    func test15PlateThemesLoadedBar() {
        for theme in ["iwfCompetition", "iwfTraining", "ipfCalibrated", "ipfCalibratedGloss",
                      "lbColourBumpers", "lbBlackIron", "lbGreyHammertone", "lbMachinedSteel",
                      "blackBumpersBand", "cadenceHouse"] {
            app.terminate()
            app.launchArguments.removeAll { $0.hasPrefix("--plate-theme=") }
            app.launchArguments.append("--plate-theme=\(theme)")
            app.launch()
            XCTAssertTrue(element("home-screen").waitForExistence(timeout: 20))
            app.buttons["Plate calculator"].tap()
            XCTAssertTrue(element("plate-calculator-screen").waitForExistence(timeout: 6))
            let target = app.textFields["plate-target"]
            XCTAssertTrue(target.waitForExistence(timeout: 3))
            target.tap()
            target.typeText("139")
            let done = app.buttons["plate-target-done"]
            XCTAssertTrue(done.waitForExistence(timeout: 3))
            done.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
            let inspect = element("expand-loaded-bar")
            for _ in 0..<3 where !inspect.isHittable { app.swipeUp() }
            XCTAssertTrue(inspect.isHittable)
            inspect.tap()
            XCTAssertTrue(app.navigationBars["Loaded bar"].waitForExistence(timeout: 5))
            let toggle = app.buttons["barbell-explode-toggle"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 3))
            assertInspectorState("Assembled", button: toggle)
            capture("after-15-theme-\(theme)-assembled-iphone")
            toggle.tap()
            assertInspectorState("Exploded", button: toggle)
            capture("after-15-theme-\(theme)-exploded-iphone")
            app.buttons["Done"].tap()
        }
    }

    func test16FavoritesInLibraryAndSessionPicker() {
        openExerciseLibrary()
        XCTAssertTrue(element("exercise-search").waitForExistence(timeout: 3))
        XCTAssertTrue(element("exercise-search").isHittable, "Search must be visible on arrival, without a pull-down gesture")
        capture("favorites-01-library-empty-iphone")
        openDisclosure("Main")
        capture("favorites-library-category-iphone")
        openDisclosure("Main")

        let search = element("exercise-search")
        for _ in 0..<3 where !search.isHittable { app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap(); search.typeText("Back Squat")
        let submitSearch = app.buttons["exercise-search-done"]
        XCTAssertTrue(submitSearch.waitForExistence(timeout: 5))
        submitSearch.tap()
        let add = app.buttons["Add Back Squat to Favorites"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let remove = app.buttons["Remove Back Squat from Favorites"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        XCTAssertEqual(remove.value as? String, "Favorite")
        capture("favorites-02-library-filtered-iphone")
        XCTAssertTrue(app.navigationBars["Library"].exists, "Starring must not open or select the lift")

        let movement = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Movement'")).firstMatch
        for _ in 0..<4 where !movement.isHittable { app.swipeDown() }
        XCTAssertTrue(movement.isHittable); movement.tap()
        app.buttons["Squat"].firstMatch.tap()
        let equipment = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Equipment'")).firstMatch
        equipment.tap(); app.buttons["barbell"].firstMatch.tap()
        capture("favorites-library-composed-iphone")
        equipment.tap(); app.buttons["dumbbell"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'No exercises match.'"))
            .firstMatch.waitForExistence(timeout: 3))
        capture("favorites-library-no-results-iphone")
        app.buttons["Clear filters"].firstMatch.tap()

        let cancelSearch = app.buttons["Cancel"].firstMatch
        if cancelSearch.exists { cancelSearch.tap() }
        capture("favorites-03-library-starred-iphone")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Today"].tap()
        app.buttons["resume-session"].tap()
        XCTAssertTrue(element("active-session-screen").waitForExistence(timeout: 8))
        let addExercise = app.buttons["Add exercise"]
        for _ in 0..<14 where !addExercise.isHittable { app.swipeUp() }
        XCTAssertTrue(addExercise.waitForExistence(timeout: 3))
        addExercise.tap()
        XCTAssertTrue(app.navigationBars["Add exercise"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("exercise-search").waitForExistence(timeout: 3))
        XCTAssertTrue(element("exercise-search").isHittable, "The shared picker must also open with visible search")
        let pickerFavorite = app.buttons["Remove Back Squat from Favorites"].firstMatch
        XCTAssertTrue(pickerFavorite.waitForExistence(timeout: 5), "The same saved shortcut appears in the session picker")
        capture("favorites-04-session-picker-iphone")
        let select = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Back Squat' AND NOT label CONTAINS 'settings'")).firstMatch
        XCTAssertTrue(select.exists)
        select.tap()
        XCTAssertTrue(app.navigationBars["Add exercise"].waitForNonExistence(timeout: 5))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// The root List ends above the opaque 72 pt calculator band. XCTest
    /// can report a row below that band as hittable; use its whole frame.
    private var rootListViewport: CGRect {
        let window = app.windows.firstMatch.frame
        let top = app.navigationBars.firstMatch.frame.maxY
        let bottom = app.tabBars.firstMatch.frame.minY - 72
        return CGRect(x: window.minX, y: top, width: window.width, height: bottom - top)
    }

    private func revealRootListRows(_ rows: [XCUIElement], viewport suppliedViewport: CGRect? = nil) {
        // SwiftUI List creates cells lazily. Reach the last requested row
        // before measuring the union, then move by the actual overflow.
        for _ in 0..<20 where !rows.allSatisfy({ $0.exists }) {
            scrollRootList(by: -100, viewport: suppliedViewport)
        }
        XCTAssertTrue(rows.allSatisfy { $0.exists }, "All requested rows exist")
        for _ in 0..<20 {
            let frame = rows.dropFirst().reduce(rows[0].frame) { $0.union($1.frame) }
            let viewport = suppliedViewport ?? rootListViewport
            if viewport.contains(frame) { break }
            XCTAssertLessThanOrEqual(frame.height, viewport.height,
                                     "The complete requested content must fit above the calculator band")
            let delta = frame.minY < viewport.minY
                ? viewport.minY - frame.minY + 4
                : viewport.maxY - frame.maxY - 4
            // A drag shorter than the pan threshold becomes a Menu tap.
            let distance = max(64, min(80, abs(delta)))
            scrollRootList(by: delta < 0 ? -distance : distance, viewport: suppliedViewport)
        }
        for row in rows {
            let viewport = suppliedViewport ?? rootListViewport
            XCTAssertTrue(viewport.contains(row.frame),
                          "Complete row \(row.label) \(row.frame) must fit in \(viewport)")
        }
    }

    private func scrollRootList(by delta: CGFloat, viewport suppliedViewport: CGRect? = nil) {
        let viewport = suppliedViewport ?? rootListViewport
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.midY))
        let end = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.midY + delta))
        // No momentum: a flung 80pt drag carried a 362pt row ~280pt on the
        // 375pt device, overshooting its 438pt viewport in both directions.
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
    }

    private func openExerciseLibrary() {
        app.tabBars.buttons["Settings"].tap()
        let programming = app.staticTexts["Programming & library"]
        revealRootListRows([programming])
        programming.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let library = app.buttons["Exercise library"]
        revealRootListRows([library])
        XCTAssertTrue(library.isHittable)
        library.tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
    }

    func test17FavoritesAtAccessibilityTextSize() {
        app.terminate()
        app.launchArguments[app.launchArguments.count - 1] = "UICTContentSizeCategoryAccessibilityXXXL"
        app.launch()
        XCTAssertTrue(element("home-screen").waitForExistence(timeout: 20))
        openExerciseLibrary()
        let search = element("exercise-search")
        for _ in 0..<4 where !search.isHittable { app.swipeDown() }
        XCTAssertTrue(search.isHittable)
        search.tap(); search.typeText("Back Squat")
        let submitSearch = app.buttons["exercise-search-done"]
        XCTAssertTrue(submitSearch.waitForExistence(timeout: 5))
        submitSearch.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "Submitting search must leave the results unobstructed")
        XCTAssertTrue(app.windows.firstMatch.frame.contains(search.frame))
        capture("favorites-accessibility-search-iphone")
        for (id, value) in [("exercise-movement-filter", "All movements"),
                            ("exercise-equipment-filter", "All equipment")] {
            let filter = app.buttons[id]
            XCTAssertTrue(filter.waitForExistence(timeout: 3))
            XCTAssertEqual(filter.value as? String, value)
            revealRootListRows([filter])
            XCTAssertTrue(filter.isHittable)
            capture("favorites-accessibility-\(id)-iphone")
        }
        let star = app.buttons["Add Back Squat to Favorites"].firstMatch
        revealRootListRows([star])
        XCTAssertTrue(star.isHittable)
        XCTAssertGreaterThanOrEqual(star.frame.width, 44)
        XCTAssertGreaterThanOrEqual(star.frame.height, 44)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(star.frame))
        star.tap()
        XCTAssertTrue(app.buttons["Remove Back Squat from Favorites"].firstMatch.waitForExistence(timeout: 5))
        // A reachable star alone does not prove the lift name/metadata are
        // clear of navigation chrome. Retain the entire favorite row.
        // Starring adds a second Back Squat row, in Favorites, and List rows
        // are lazy: firstMatch named whichever copy was on screen and the
        // reveal chased it. Return to the top so it names the Favorites row.
        // At this size that row starts below the fold and is not built yet;
        // the reveal scrolls down in short steps and asserts it exists.
        for _ in 0..<6 where !search.isHittable { app.swipeDown() }
        XCTAssertTrue(search.isHittable)
        let favorite = app.cells.containing(.button, identifier: "Remove Back Squat from Favorites").firstMatch
        revealRootListRows([favorite])
        capture("favorites-accessibility-iphone")
    }

    func test18DP1CalculatorStates() {
        CalculatorProofCases.run(in: self)
        // Light single-disc loads expose shaft/sleeve and bore alignment that
        // a tall stack can hide. Use only the synthetic pound-denominated rack.
        for (target, plate) in [("95", "25 lb"), ("115", "35 lb")] {
            app.terminate()
            app.launchArguments = ["--visual-proof", "--plate-proof=lb-exact",
                "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
            app.launch()
            XCTAssertTrue(element("home-screen").waitForExistence(timeout: 20))
            app.buttons["Plate calculator"].tap()
            let field = app.textFields["plate-target"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap(); field.typeText(target)
            app.buttons["plate-target-done"].tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
            let window = app.windows.firstMatch.frame
            let top = app.navigationBars["Plates"].frame.maxY
            let viewport = CGRect(x: window.minX, y: top, width: window.width,
                                  height: window.maxY - top - 34)
            let stage = app.cells.containing(.button, identifier: "expand-loaded-bar").firstMatch
            revealRootListRows([stage], viewport: viewport)
            for side in ["left", "right"] {
                let disc = element("barbell-plate-\(side)-0")
                XCTAssertTrue(disc.waitForExistence(timeout: 3))
                XCTAssertTrue(disc.label.contains(plate), "The visible plate must match the solved denomination")
                XCTAssertFalse(element("barbell-plate-\(side)-1").exists)
            }
            capture("after-calculator-single-\(plate.replacingOccurrences(of: " ", with: "-"))-iphone")
        }
    }

    func test20EquipmentContextAndEmptyStates() {
        app.terminate()
        app.launchArguments += ["--equipment-empty-proof"]
        app.launch()
        XCTAssertTrue(element("home-screen").waitForExistence(timeout: 20))
        app.tabBars.buttons["Program"].tap()
        XCTAssertTrue(app.staticTexts["No program"].waitForExistence(timeout: 5))
        revealRootListRows([app.cells.containing(.staticText, identifier: "No program").firstMatch])
        capture("equipment-program-empty-iphone")

        openExerciseLibrary()
        let categories = ["Main", "Accessory", "Conditioning"].map {
            app.cells.containing(.staticText, identifier: $0).firstMatch
        }
        revealRootListRows(categories)
        capture("equipment-categories-iphone")

        let search = element("exercise-search")
        for _ in 0..<8 where !search.isHittable { app.swipeDown() }
        XCTAssertTrue(search.isHittable)
        search.tap(); search.typeText("Synthetic unlogged accessory")
        let submit = app.buttons["exercise-search-done"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5)); submit.tap()
        let lift = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Synthetic unlogged accessory'")).firstMatch
        revealRootListRows([lift])
        XCTAssertTrue(lift.isHittable); lift.tap()
        XCTAssertTrue(element("exercise-detail-screen").waitForExistence(timeout: 5))
        let programming = app.staticTexts["Previous performance & programming"]
        revealRootListRows([programming])
        programming.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let empty = app.staticTexts["No sessions yet."]
        let emptyRow = app.cells.containing(.staticText, identifier: "No sessions yet.").firstMatch
        revealRootListRows([emptyRow])
        XCTAssertTrue(empty.isHittable)
        capture("equipment-exercise-empty-iphone")
    }

    /// The Program tab's "Edit program" row is the only way into the
    /// whole-program editor on iOS (#307). Prove the tap opens it for the
    /// seeded program and for a blank one, and that back and reopen work.
    func test21EditProgramRowOpensEditor() {
        app.tabBars.buttons["Program"].tap()
        XCTAssertTrue(app.navigationBars["Program"].waitForExistence(timeout: 5))
        let rows = app.descendants(matching: .any).matching(identifier: "edit-program")
        let populated = rows.firstMatch
        for _ in 0..<10 where !populated.isHittable { app.swipeUp() }
        XCTAssertTrue(populated.isHittable, "each program section ends with its editor row")
        populated.tap()
        XCTAssertTrue(app.navigationBars["Foundry Hypertrophy"].waitForExistence(timeout: 5),
                      "the row pushes the whole-program editor")
        let nextDay = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Next day'")).firstMatch
        // Form rows are lazy: a row below the fold does not exist until it
        // scrolls on, so scroll until it is hittable rather than waiting.
        for _ in 0..<8 where !nextDay.isHittable { app.swipeUp() }
        XCTAssertTrue(nextDay.isHittable, "the schedule position is on screen in the editor")
        capture("after-21-edit-program-populated-iphone")
        app.navigationBars.buttons["Program"].tap()
        XCTAssertTrue(app.navigationBars["Program"].waitForExistence(timeout: 5))
        for _ in 0..<10 where !populated.isHittable { app.swipeUp() }
        populated.tap()
        XCTAssertTrue(app.navigationBars["Foundry Hypertrophy"].waitForExistence(timeout: 5), "reopening works")
        app.navigationBars.buttons["Program"].tap()
        XCTAssertTrue(app.navigationBars["Program"].waitForExistence(timeout: 5))

        // A blank program has no day cards, so this row is its only editor.
        app.navigationBars["Program"].buttons["Add program"].tap()
        let blankButton = app.buttons["Blank program"]
        XCTAssertTrue(blankButton.waitForExistence(timeout: 5))
        blankButton.tap()
        let blank = rows.element(boundBy: 1)
        XCTAssertTrue(blank.waitForExistence(timeout: 5), "the new program gets its own editor row")
        for _ in 0..<10 where !blank.isHittable { app.swipeUp() }
        XCTAssertTrue(blank.isHittable)
        blank.tap()
        XCTAssertTrue(app.navigationBars["Program 2"].waitForExistence(timeout: 5), "a blank program opens its editor")
        let addDay = app.buttons["Add day"]
        for _ in 0..<8 where !addDay.isHittable { app.swipeUp() }
        XCTAssertTrue(addDay.isHittable, "days can be added to a blank program")
        capture("after-21-edit-program-blank-iphone")

        // Deleting a program is confirmed, never one tap: cancel keeps it,
        // back and reopen keep it, confirming removes it.
        let deleteRow = app.buttons["Delete program"]
        for _ in 0..<12 where !deleteRow.isHittable { app.swipeUp() }
        XCTAssertTrue(deleteRow.isHittable)
        deleteRow.tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 3), "deleting a program asks first")
        cancel.tap()
        XCTAssertTrue(app.navigationBars["Program 2"].waitForExistence(timeout: 3), "cancel keeps the editor open")
        app.navigationBars.buttons["Program"].tap()
        XCTAssertTrue(app.navigationBars["Program"].waitForExistence(timeout: 5))
        for _ in 0..<10 where !blank.isHittable { app.swipeUp() }
        XCTAssertTrue(blank.isHittable, "cancel kept the program")
        blank.tap()
        XCTAssertTrue(app.navigationBars["Program 2"].waitForExistence(timeout: 5), "back and reopen keep the program")
        for _ in 0..<12 where !deleteRow.isHittable { app.swipeUp() }
        deleteRow.tap()
        let confirm = app.buttons["Delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        capture("after-21-delete-program-confirmation-iphone")
        confirm.tap()
        XCTAssertTrue(app.navigationBars["Program"].waitForExistence(timeout: 5),
                      "confirming deletes the program and returns to the Program tab")
        XCTAssertTrue(blank.waitForNonExistence(timeout: 5), "the blank program's row is gone")
        XCTAssertTrue(populated.exists, "the seeded program keeps its row")
    }

    /// App palettes are distinct from the ten equipment themes. Retain both
    /// the primary task index and load-entry canvas under every saved palette.
    func test19AppThemeCanvases() {
        for (theme, label) in [("carbon", "Foundry"), ("memento", "Heritage Gold"),
                               ("titanium", "Titanium"), ("slate", "Slate"), ("system", "System")] {
            app.terminate()
            app.launchArguments.removeAll { $0.hasPrefix("--app-theme=") }
            app.launchArguments.append("--app-theme=\(theme)")
            app.launch()
            XCTAssertTrue(element("home-screen").waitForExistence(timeout: 20))
            // Five cold relaunches on a slow runner: a launch used its whole
            // 20s and the Settings tab then missed a 5s wait (#177 follow-up).
            // Screens get the launch budget, elements half of it.
            app.tabBars.buttons["Settings"].tap()
            XCTAssertTrue(element("settings-screen").waitForExistence(timeout: 20))
            XCTAssertTrue(app.staticTexts[label].firstMatch.waitForExistence(timeout: 10))
            capture("after-19-app-theme-\(theme)-settings-iphone")
            app.buttons["Plate calculator"].tap()
            let target = app.textFields["plate-target"]
            XCTAssertTrue(target.waitForExistence(timeout: 10))
            target.tap()
            target.typeText("139")
            let done = app.buttons["plate-target-done"]
            XCTAssertTrue(done.waitForExistence(timeout: 10))
            done.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 10))
            capture("after-19-app-theme-\(theme)-calculator-iphone")
        }
    }

    private func capture(_ name: String) {
        // XCTest can finish a tap before a disclosure's painted transition.
        // The earlier proof caught ghosted rows; settle only the screenshot,
        // beyond the 260 ms authored cut and the platform navigation animation.
        Thread.sleep(forTimeInterval: 0.6)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let frame = app.windows.firstMatch.frame
        let geometry = XCTAttachment(string: "window: \(frame.width) x \(frame.height) pt\nlaunchArguments: \(app.launchArguments.joined(separator: " "))")
        geometry.name = "\(name)-geometry"
        geometry.lifetime = .keepAlways
        add(geometry)
    }
}
