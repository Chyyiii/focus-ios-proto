import XCTest

private func date(_ iso: String) -> Date {
    return ISO8601DateFormatter().date(from: iso)!
}

private let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func assertParseThrows(_ text: String, _ expected: SnapshotParseError,
                               file: StaticString = #filePath, line: UInt = #line) {
    do {
        _ = try SnapshotParser.parse(Fixtures.data(text))
        XCTFail("ожидалась ошибка \(expected)", file: file, line: line)
    } catch let error as SnapshotParseError {
        XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
        XCTFail("другая ошибка: \(error)", file: file, line: line)
    }
}

// MARK: разбор

final class SnapshotParserTests: XCTestCase {
    func testValidFullSnapshot() throws {
        let s = try SnapshotParser.parse(Fixtures.data(Fixtures.valid))
        XCTAssertEqual(s.schema, 1)
        XCTAssertEqual(s.source, "demo")
        XCTAssertEqual(s.forDate, "2026-11-18")
        XCTAssertEqual(s.generatedAt, date("2026-11-18T05:12:00Z"))
        XCTAssertEqual(s.theme, WidgetSnapshot.Theme(palette: .ember, mode: .auto))
        XCTAssertEqual(s.day?.done, 3)
        XCTAssertEqual(s.day?.total, 7)
        XCTAssertEqual(s.day?.nextTime, "15:30")
        XCTAssertEqual(s.day?.nextText, "Записаться к врачу")
        XCTAssertEqual(s.habits, WidgetSnapshot.Habits(done: 3, total: 4))
        XCTAssertEqual(s.limit?.enabled, true)
        XCTAssertEqual(s.limit?.state, .ok)
        XCTAssertEqual(s.limit?.value, 1306)
        XCTAssertEqual(s.streakBest, 11)
    }

    func testMinimalSnapshotHasDefaults() throws {
        let s = try SnapshotParser.parse(Fixtures.data(Fixtures.minimal))
        XCTAssertEqual(s.day?.total, 0)
        XCTAssertNil(s.day?.nextText)
        XCTAssertNil(s.habits)
        XCTAssertNil(s.limit)
        XCTAssertNil(s.streakBest)
        XCTAssertEqual(s.theme.palette, .ember)
        XCTAssertEqual(s.theme.mode, .auto)
        XCTAssertFalse(s.privacy.locked)
        XCTAssertFalse(s.privacy.hideAmounts)
    }

    func testMissingDayBlockGivesNilDay() throws {
        let s = try SnapshotParser.parse(Fixtures.data(Fixtures.noDay))
        XCTAssertNil(s.day)
    }

    func testUnknownFieldsAreIgnored() throws {
        let s = try SnapshotParser.parse(Fixtures.data(Fixtures.unknownFields))
        XCTAssertEqual(s.day?.done, 1)
        XCTAssertEqual(s.day?.total, 2)
    }

    func testUnknownPaletteAndModeFallBack() throws {
        let s = try SnapshotParser.parse(Fixtures.data(Fixtures.unknownPalette))
        XCTAssertEqual(s.theme.palette, .ember)
        XCTAssertEqual(s.theme.mode, .auto)
    }

    func testDoneGreaterThanTotalDropsDay() throws {
        XCTAssertNil(try SnapshotParser.parse(Fixtures.data(Fixtures.doneGreaterThanTotal)).day)
    }

    func testNegativeTotalDropsDay() throws {
        XCTAssertNil(try SnapshotParser.parse(Fixtures.data(Fixtures.negativeTotal)).day)
    }

    func testWrongTypeHabitsDropped() throws {
        let s = try SnapshotParser.parse(Fixtures.data(Fixtures.habitsWrongType))
        XCTAssertNil(s.habits)
        XCTAssertNotNil(s.day)
    }

    func testLimitWithUnknownStateDropped() throws {
        XCTAssertNil(try SnapshotParser.parse(Fixtures.data(Fixtures.limitBadState)).limit)
    }

    func testLimitDisabledKept() throws {
        let limit = try SnapshotParser.parse(Fixtures.data(Fixtures.limitDisabled)).limit
        XCTAssertEqual(limit?.enabled, false)
        XCTAssertNil(limit?.value)
    }

    func testBadNextTimeAndBlankTextDropped() throws {
        let day = try SnapshotParser.parse(Fixtures.data(Fixtures.badNextTime)).day
        XCTAssertNil(day?.nextTime)
        XCTAssertNil(day?.nextText)
        XCTAssertEqual(day?.total, 2)
    }

    func testRequiredFieldErrors() {
        assertParseThrows(Fixtures.missingGeneratedAt, .missingGeneratedAt)
        assertParseThrows(Fixtures.badGeneratedAt, .badGeneratedAt)
        assertParseThrows(Fixtures.missingForDate, .missingForDate)
        assertParseThrows(Fixtures.badForDate, .badForDate)
        assertParseThrows(Fixtures.missingSchema, .missingSchema)
    }

    func testSchemaOutOfRange() {
        assertParseThrows(Fixtures.schemaZero, .unsupportedSchema(0))
        assertParseThrows(Fixtures.schemaTwo, .unsupportedSchema(2))
    }

    func testGarbageInput() {
        assertParseThrows(Fixtures.notJSON, .notJSON)
        assertParseThrows(Fixtures.arrayRoot, .notObject)
        assertParseThrows("", .notJSON)
    }

    func testTooLarge() {
        let big = Data(repeating: 0x20, count: SnapshotConstants.maxBytes + 1)
        do {
            _ = try SnapshotParser.parse(big)
            XCTFail("ожидалась ошибка tooLarge")
        } catch let error as SnapshotParseError {
            XCTAssertEqual(error, .tooLarge)
        } catch {
            XCTFail("другая ошибка: \(error)")
        }
    }

    func testDayAndTimeValidators() {
        XCTAssertTrue(SnapshotParser.isValidDay("2026-11-18"))
        XCTAssertFalse(SnapshotParser.isValidDay("2026-13-01"))
        XCTAssertFalse(SnapshotParser.isValidDay("2026-1-1"))
        XCTAssertTrue(SnapshotParser.isValidTime("00:00"))
        XCTAssertTrue(SnapshotParser.isValidTime("23:59"))
        XCTAssertFalse(SnapshotParser.isValidTime("24:00"))
        XCTAssertFalse(SnapshotParser.isValidTime("9:30"))
    }
}

// MARK: загрузка с запасной копией

final class SnapshotLoaderTests: XCTestCase {
    private let good = Fixtures.data(Fixtures.valid)
    private let broken = Fixtures.data(Fixtures.notJSON)

    func testPrimaryUsed() {
        guard case .snapshot(_, let fromPrevious) = SnapshotLoader.load(primary: good, previous: good) else {
            return XCTFail("ожидался снимок")
        }
        XCTAssertFalse(fromPrevious)
    }

    func testCorruptPrimaryFallsBackToPrevious() {
        guard case .snapshot(let s, let fromPrevious) = SnapshotLoader.load(primary: broken, previous: good) else {
            return XCTFail("ожидался снимок из .prev")
        }
        XCTAssertTrue(fromPrevious)
        XCTAssertEqual(s.day?.done, 3)
    }

    func testMissingPrimaryFallsBackToPrevious() {
        guard case .snapshot(_, let fromPrevious) = SnapshotLoader.load(primary: nil, previous: good) else {
            return XCTFail("ожидался снимок из .prev")
        }
        XCTAssertTrue(fromPrevious)
    }

    func testBothCorruptGivesNoData() {
        XCTAssertEqual(SnapshotLoader.load(primary: broken, previous: broken), .noData)
    }

    func testNothingGivesNoData() {
        XCTAssertEqual(SnapshotLoader.load(primary: nil, previous: nil), .noData)
    }

    func testNewSchemaIsNotMaskedByPrevious() {
        let newer = Fixtures.data(Fixtures.schemaTwo)
        XCTAssertEqual(SnapshotLoader.load(primary: newer, previous: good), .unsupportedSchema(2))
    }
}

// MARK: устаревание

final class StalenessTests: XCTestCase {
    private func snapshot(_ text: String = Fixtures.valid) throws -> WidgetSnapshot {
        return try SnapshotParser.parse(Fixtures.data(text))
    }

    func testFreshSameDay() throws {
        let state = Staleness.state(of: try snapshot(), now: date("2026-11-18T09:00:00Z"), calendar: utcCalendar)
        XCTAssertEqual(state, .fresh)
        XCTAssertTrue(state.showsDailyNumbers)
    }

    func testDayOldAfterMidnight() throws {
        let state = Staleness.state(of: try snapshot(), now: date("2026-11-19T01:00:00Z"), calendar: utcCalendar)
        XCTAssertEqual(state, .dayOld(forDate: "2026-11-18"))
        XCTAssertFalse(state.showsDailyNumbers)
    }

    func testStaleAfter48Hours() throws {
        let state = Staleness.state(of: try snapshot(), now: date("2026-11-21T00:00:00Z"), calendar: utcCalendar)
        XCTAssertEqual(state, .stale)
        XCTAssertFalse(state.showsDailyNumbers)
    }

    func testExactly48HoursIsNotYetStale() throws {
        let state = Staleness.state(of: try snapshot(), now: date("2026-11-20T05:12:00Z"), calendar: utcCalendar)
        XCTAssertEqual(state, .dayOld(forDate: "2026-11-18"))
    }

    func testOneSecondOver48HoursIsStale() throws {
        let state = Staleness.state(of: try snapshot(), now: date("2026-11-20T05:12:01Z"), calendar: utcCalendar)
        XCTAssertEqual(state, .stale)
    }

    func testLockedWinsOverEverything() throws {
        let locked = Fixtures.valid.replacingOccurrences(of: "\"locked\":false", with: "\"locked\":true")
        let state = Staleness.state(of: try snapshot(locked), now: date("2026-11-30T00:00:00Z"), calendar: utcCalendar)
        XCTAssertEqual(state, .locked)
        XCTAssertFalse(state.showsDailyNumbers)
    }

    func testFutureForDateIsNotFresh() throws {
        let future = Fixtures.valid.replacingOccurrences(of: "\"forDate\":\"2026-11-18\"", with: "\"forDate\":\"2026-11-19\"")
        let state = Staleness.state(of: try snapshot(future), now: date("2026-11-18T09:00:00Z"), calendar: utcCalendar)
        XCTAssertEqual(state, .dayOld(forDate: "2026-11-19"))
    }

    func testDayStringUsesCalendarTimeZone() {
        var perm = Calendar(identifier: .gregorian)
        perm.timeZone = TimeZone(secondsFromGMT: 5 * 3600)!
        // 20:00 UTC = 01:00 следующего дня в UTC+5
        let moment = date("2026-11-18T20:00:00Z")
        XCTAssertEqual(Staleness.dayString(for: moment, calendar: utcCalendar), "2026-11-18")
        XCTAssertEqual(Staleness.dayString(for: moment, calendar: perm), "2026-11-19")
    }
}

// MARK: хранилище

final class SnapshotStoreTests: XCTestCase {
    private var directory: URL!
    private var store: SnapshotStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = SnapshotStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testWriteThenLoad() throws {
        try store.write(Fixtures.data(Fixtures.valid))
        guard case .snapshot(let s, let fromPrevious) = store.load() else {
            return XCTFail("ожидался снимок")
        }
        XCTAssertFalse(fromPrevious)
        XCTAssertEqual(s.day?.done, 3)
    }

    func testInvalidDataIsNotWritten() {
        XCTAssertThrowsError(try store.write(Fixtures.data(Fixtures.notJSON))) {
            XCTAssertEqual($0 as? SnapshotStoreError, .invalid)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.primaryURL.path))
    }

    func testSnapshotWithoutDayIsNotWritten() {
        XCTAssertThrowsError(try store.write(Fixtures.data(Fixtures.noDay))) {
            XCTAssertEqual($0 as? SnapshotStoreError, .invalid)
        }
    }

    func testOversizedDataIsNotWritten() {
        let big = Data(repeating: 0x20, count: SnapshotConstants.maxBytes + 1)
        XCTAssertThrowsError(try store.write(big))
    }

    func testInvalidWriteKeepsGoodPrimaryAndCreatesNoPrev() throws {
        try store.write(Fixtures.data(Fixtures.valid))
        XCTAssertThrowsError(try store.write(Fixtures.data(Fixtures.notJSON)))
        guard case .snapshot(let s, _) = store.load() else {
            return XCTFail("ожидался прежний снимок")
        }
        XCTAssertEqual(s.day?.done, 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.previousURL.path))
    }

    func testSecondWriteKeepsFirstAsPrevious() throws {
        try store.write(Fixtures.data(Fixtures.valid))
        let second = Fixtures.valid.replacingOccurrences(of: "\"done\":3,\"total\":7", with: "\"done\":5,\"total\":7")
        try store.write(Fixtures.data(second))
        guard case .snapshot(let s, _) = store.load() else {
            return XCTFail("ожидался снимок")
        }
        XCTAssertEqual(s.day?.done, 5)
        let prev = try Data(contentsOf: store.previousURL)
        XCTAssertEqual(try SnapshotParser.parse(prev).day?.done, 3)
    }

    func testCorruptedPrimaryOnDiskFallsBackToPrevious() throws {
        try store.write(Fixtures.data(Fixtures.valid))
        let second = Fixtures.valid.replacingOccurrences(of: "\"done\":3,\"total\":7", with: "\"done\":5,\"total\":7")
        try store.write(Fixtures.data(second))
        try Fixtures.data(Fixtures.notJSON).write(to: store.primaryURL)
        guard case .snapshot(let s, let fromPrevious) = store.load() else {
            return XCTFail("ожидался снимок из .prev")
        }
        XCTAssertTrue(fromPrevious)
        XCTAssertEqual(s.day?.done, 3)
    }

    func testEmptyDirectoryGivesNoData() {
        XCTAssertEqual(store.load(), .noData)
    }
}
