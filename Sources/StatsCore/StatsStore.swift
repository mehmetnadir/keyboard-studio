import Foundation
import SQLite3

// MARK: - Constants

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - Types

/// Statistics for a specific keycode.
public struct KeyStat: Sendable, Equatable {
  public let keycode: Int
  public let count: Int

  public init(keycode: Int, count: Int) {
    self.keycode = keycode
    self.count = count
  }
}

/// Aggregated activity statistics for a calendar day.
public struct DayStat: Sendable, Equatable {
  public let day: String
  public let presses: Int
  public let activeMinutes: Int

  public init(day: String, presses: Int, activeMinutes: Int) {
    self.day = day
    self.presses = presses
    self.activeMinutes = activeMinutes
  }
}

/// Summary records including streaks, peak usage hour, and busiest day.
public struct Records: Sendable, Equatable {
  public let busiestDay: DayStat?
  public let currentStreak: Int
  public let longestStreak: Int
  public let peakHour: Int?

  public init(
    busiestDay: DayStat?,
    currentStreak: Int,
    longestStreak: Int,
    peakHour: Int?
  ) {
    self.busiestDay = busiestDay
    self.currentStreak = currentStreak
    self.longestStreak = longestStreak
    self.peakHour = peakHour
  }
}

// MARK: - Errors

public enum StatsError: Error, CustomStringConvertible {
  case sqlite(code: Int32, message: String)
  case invalidPath(String)

  public var description: String {
    switch self {
    case .sqlite(let code, let message):
      return "SQLite error (\(code)): \(message)"
    case .invalidPath(let path):
      return "Invalid database path: \(path)"
    }
  }
}

// MARK: - StatsStore

/// Thread-safe SQLite store for persisting keystroke statistics.
///
/// Stores aggregate counters only — never key sequences, typed text, or
/// per-keypress timestamps. See the schema in `init(path:)` for the full
/// list of tables; every one of them is a rollup, not an event log.
public final class StatsStore: @unchecked Sendable {
  private var db: OpaquePointer?
  private var isClosed: Bool = false
  private let lock: NSLock = NSLock()

  // MARK: - Lifecycle

  /// Opens (or creates) the SQLite database at `path` and runs migrations.
  public init(path: String) throws {
    guard !path.isEmpty else {
      throw StatsError.invalidPath(path)
    }

    var dbPointer: OpaquePointer?
    let flags: Int32 = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
    let openResult: Int32 = sqlite3_open_v2(path, &dbPointer, flags, nil)
    guard openResult == SQLITE_OK, let dbHandle: OpaquePointer = dbPointer else {
      let message: String
      if let dbPointer: OpaquePointer = dbPointer,
        let errmsg: UnsafePointer<CChar> = sqlite3_errmsg(dbPointer) {
        message = String(cString: errmsg)
        sqlite3_close_v2(dbPointer)
      } else {
        message = "Unable to open database at path: \(path)"
      }
      throw StatsError.sqlite(code: openResult, message: message)
    }
    self.db = dbHandle

    // The app and `kstudio watch` can hold the same file open; without a busy
    // timeout the second writer's BEGIN IMMEDIATE fails instantly and its whole
    // flush is rolled back.
    sqlite3_busy_timeout(dbHandle, 5000)

    do {
      try StatsStore.exec("PRAGMA journal_mode=WAL;", db: dbHandle)
      try StatsStore.exec("PRAGMA synchronous=NORMAL;", db: dbHandle)
      try StatsStore.exec("PRAGMA foreign_keys=ON;", db: dbHandle)

      let createDailyCounts: String = """
      CREATE TABLE IF NOT EXISTS daily_counts (
        day TEXT NOT NULL,
        keycode INTEGER NOT NULL,
        count INTEGER NOT NULL,
        PRIMARY KEY (day, keycode)
      );
      """
      try StatsStore.exec(createDailyCounts, db: dbHandle)

      let createDailyActivity: String = """
      CREATE TABLE IF NOT EXISTS daily_activity (
        day TEXT PRIMARY KEY,
        active_minutes INTEGER NOT NULL DEFAULT 0,
        total_presses INTEGER NOT NULL DEFAULT 0
      );
      """
      try StatsStore.exec(createDailyActivity, db: dbHandle)

      let createHourlyTotals: String = """
      CREATE TABLE IF NOT EXISTS hourly_totals (
        hour INTEGER PRIMARY KEY,
        count INTEGER NOT NULL DEFAULT 0
      );
      """
      try StatsStore.exec(createHourlyTotals, db: dbHandle)

      let createMeta: String = """
      CREATE TABLE IF NOT EXISTS meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
      """
      try StatsStore.exec(createMeta, db: dbHandle)

      let setSchemaVersion: String = """
      INSERT OR REPLACE INTO meta (key, value) VALUES ('schema_version', '1');
      """
      try StatsStore.exec(setSchemaVersion, db: dbHandle)
    } catch {
      sqlite3_close_v2(dbHandle)
      self.db = nil
      self.isClosed = true
      throw error
    }
  }

  deinit {
    if let dbHandle: OpaquePointer = db {
      sqlite3_close_v2(dbHandle)
    }
  }

  // MARK: - Public API

  /// `~/Library/Application Support/KeyboardStudio/stats.sqlite`, creating the
  /// directory if it does not already exist.
  public static func defaultPath() -> String {
    let fileManager: FileManager = FileManager.default
    let directoryURL: URL
    if let appSupportURL: URL = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first {
      directoryURL = appSupportURL.appendingPathComponent("KeyboardStudio", isDirectory: true)
    } else {
      directoryURL = fileManager.homeDirectoryForCurrentUser
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("KeyboardStudio", isDirectory: true)
    }
    // 0o700: the file holds a per-key frequency profile, so keep it to the user.
    try? fileManager.createDirectory(
      at: directoryURL, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    return directoryURL.appendingPathComponent("stats.sqlite").path
  }

  /// Atomically merges one flush batch into the store.
  ///
  /// `counts` and `hourBuckets` are added via UPSERT (existing rows accumulate
  /// rather than being overwritten), so calling this twice for the same day is
  /// safe and simply adds the deltas together.
  public func flush(
    day: String,
    counts: [Int: Int],
    hourBuckets: [Int: Int],
    activeMinutes: Int
  ) throws {
    lock.lock()
    defer { lock.unlock() }

    guard let db: OpaquePointer = self.db, !isClosed else {
      throw StatsError.sqlite(code: SQLITE_MISUSE, message: "Database is closed")
    }

    try StatsStore.exec("BEGIN IMMEDIATE TRANSACTION;", db: db)
    do {
      // Only recorded once — INSERT OR IGNORE is a no-op once the key exists.
      let metaSQL: String = "INSERT OR IGNORE INTO meta (key, value) VALUES ('first_seen', ?);"
      var metaStmt: OpaquePointer?
      try check(sqlite3_prepare_v2(db, metaSQL, -1, &metaStmt, nil), db: db)
      defer { sqlite3_finalize(metaStmt) }

      // Date only, no clock time: a precise timestamp would pin down when the
      // first key was struck, which the privacy contract rules out.
      let firstSeen: String = day
      try check(sqlite3_bind_text(metaStmt, 1, firstSeen, -1, SQLITE_TRANSIENT), db: db)
      try stepDone(metaStmt, db: db)

      if !counts.isEmpty {
        let countSQL: String = """
        INSERT INTO daily_counts (day, keycode, count) VALUES (?, ?, ?)
        ON CONFLICT(day, keycode) DO UPDATE SET count = count + excluded.count;
        """
        var countStmt: OpaquePointer?
        try check(sqlite3_prepare_v2(db, countSQL, -1, &countStmt, nil), db: db)
        defer { sqlite3_finalize(countStmt) }

        for (keycode, count) in counts {
          sqlite3_reset(countStmt)
          sqlite3_clear_bindings(countStmt)
          try check(sqlite3_bind_text(countStmt, 1, day, -1, SQLITE_TRANSIENT), db: db)
          try check(sqlite3_bind_int64(countStmt, 2, Int64(keycode)), db: db)
          try check(sqlite3_bind_int64(countStmt, 3, Int64(count)), db: db)
          try stepDone(countStmt, db: db)
        }
      }

      if !hourBuckets.isEmpty {
        let hourSQL: String = """
        INSERT INTO hourly_totals (hour, count) VALUES (?, ?)
        ON CONFLICT(hour) DO UPDATE SET count = count + excluded.count;
        """
        var hourStmt: OpaquePointer?
        try check(sqlite3_prepare_v2(db, hourSQL, -1, &hourStmt, nil), db: db)
        defer { sqlite3_finalize(hourStmt) }

        for (hour, count) in hourBuckets {
          sqlite3_reset(hourStmt)
          sqlite3_clear_bindings(hourStmt)
          try check(sqlite3_bind_int64(hourStmt, 1, Int64(hour)), db: db)
          try check(sqlite3_bind_int64(hourStmt, 2, Int64(count)), db: db)
          try stepDone(hourStmt, db: db)
        }
      }

      let totalDelta: Int = counts.values.reduce(0, +)
      let activitySQL: String = """
      INSERT INTO daily_activity (day, active_minutes, total_presses) VALUES (?, ?, ?)
      ON CONFLICT(day) DO UPDATE SET
        active_minutes = active_minutes + excluded.active_minutes,
        total_presses = total_presses + excluded.total_presses;
      """
      var activityStmt: OpaquePointer?
      try check(sqlite3_prepare_v2(db, activitySQL, -1, &activityStmt, nil), db: db)
      defer { sqlite3_finalize(activityStmt) }

      try check(sqlite3_bind_text(activityStmt, 1, day, -1, SQLITE_TRANSIENT), db: db)
      try check(sqlite3_bind_int64(activityStmt, 2, Int64(activeMinutes)), db: db)
      try check(sqlite3_bind_int64(activityStmt, 3, Int64(totalDelta)), db: db)
      try stepDone(activityStmt, db: db)

      try StatsStore.exec("COMMIT;", db: db)
    } catch {
      _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
      throw error
    }
  }

  /// Total keystrokes recorded across every day in the store.
  public func lifetimeTotal() throws -> Int {
    lock.lock()
    defer { lock.unlock() }

    guard let db: OpaquePointer = self.db, !isClosed else {
      throw StatsError.sqlite(code: SQLITE_MISUSE, message: "Database is closed")
    }

    let sql: String = "SELECT COALESCE(SUM(total_presses), 0) FROM daily_activity;"
    var stmt: OpaquePointer?
    try check(sqlite3_prepare_v2(db, sql, -1, &stmt, nil), db: db)
    defer { sqlite3_finalize(stmt) }

    let stepResult: Int32 = sqlite3_step(stmt)
    if stepResult == SQLITE_ROW {
      return Int(sqlite3_column_int64(stmt, 0))
    } else if stepResult == SQLITE_DONE {
      return 0
    } else {
      try check(stepResult, db: db)
      return 0
    }
  }

  /// Total keystrokes between `from` and `to`, inclusive of both dates.
  public func total(from: String, to: String) throws -> Int {
    lock.lock()
    defer { lock.unlock() }

    guard let db: OpaquePointer = self.db, !isClosed else {
      throw StatsError.sqlite(code: SQLITE_MISUSE, message: "Database is closed")
    }

    let sql: String = """
    SELECT COALESCE(SUM(total_presses), 0)
    FROM daily_activity
    WHERE day BETWEEN ? AND ?;
    """
    var stmt: OpaquePointer?
    try check(sqlite3_prepare_v2(db, sql, -1, &stmt, nil), db: db)
    defer { sqlite3_finalize(stmt) }

    try check(sqlite3_bind_text(stmt, 1, from, -1, SQLITE_TRANSIENT), db: db)
    try check(sqlite3_bind_text(stmt, 2, to, -1, SQLITE_TRANSIENT), db: db)

    let stepResult: Int32 = sqlite3_step(stmt)
    if stepResult == SQLITE_ROW {
      return Int(sqlite3_column_int64(stmt, 0))
    } else if stepResult == SQLITE_DONE {
      return 0
    } else {
      try check(stepResult, db: db)
      return 0
    }
  }

  /// The busiest keycodes between `from` and `to`, inclusive, ordered by count descending.
  public func topKeys(from: String, to: String, limit: Int) throws -> [KeyStat] {
    lock.lock()
    defer { lock.unlock() }

    guard let db: OpaquePointer = self.db, !isClosed else {
      throw StatsError.sqlite(code: SQLITE_MISUSE, message: "Database is closed")
    }

    let sql: String = """
    SELECT keycode, SUM(count) AS total
    FROM daily_counts
    WHERE day BETWEEN ? AND ?
    GROUP BY keycode
    ORDER BY total DESC
    LIMIT ?;
    """
    var stmt: OpaquePointer?
    try check(sqlite3_prepare_v2(db, sql, -1, &stmt, nil), db: db)
    defer { sqlite3_finalize(stmt) }

    try check(sqlite3_bind_text(stmt, 1, from, -1, SQLITE_TRANSIENT), db: db)
    try check(sqlite3_bind_text(stmt, 2, to, -1, SQLITE_TRANSIENT), db: db)
    try check(sqlite3_bind_int64(stmt, 3, Int64(limit)), db: db)

    var results: [KeyStat] = []
    while true {
      let stepResult: Int32 = sqlite3_step(stmt)
      if stepResult == SQLITE_ROW {
        let keycode: Int = Int(sqlite3_column_int64(stmt, 0))
        let count: Int = Int(sqlite3_column_int64(stmt, 1))
        results.append(KeyStat(keycode: keycode, count: count))
      } else if stepResult == SQLITE_DONE {
        break
      } else {
        try check(stepResult, db: db)
      }
    }
    return results
  }

  /// The stats for a single day, or `nil` if that day has no recorded activity.
  public func dayStat(_ day: String) throws -> DayStat? {
    lock.lock()
    defer { lock.unlock() }

    guard let db: OpaquePointer = self.db, !isClosed else {
      throw StatsError.sqlite(code: SQLITE_MISUSE, message: "Database is closed")
    }

    let sql: String = """
    SELECT day, total_presses, active_minutes
    FROM daily_activity
    WHERE day = ?;
    """
    var stmt: OpaquePointer?
    try check(sqlite3_prepare_v2(db, sql, -1, &stmt, nil), db: db)
    defer { sqlite3_finalize(stmt) }

    try check(sqlite3_bind_text(stmt, 1, day, -1, SQLITE_TRANSIENT), db: db)

    let stepResult: Int32 = sqlite3_step(stmt)
    if stepResult == SQLITE_ROW {
      let dayString: String
      if let textPtr: UnsafePointer<UInt8> = sqlite3_column_text(stmt, 0) {
        dayString = String(cString: textPtr)
      } else {
        dayString = day
      }
      let presses: Int = Int(sqlite3_column_int64(stmt, 1))
      let activeMinutes: Int = Int(sqlite3_column_int64(stmt, 2))
      return DayStat(day: dayString, presses: presses, activeMinutes: activeMinutes)
    } else if stepResult == SQLITE_DONE {
      return nil
    } else {
      try check(stepResult, db: db)
      return nil
    }
  }

  /// Busiest day, activity streaks, and the peak hour-of-day across all recorded history.
  ///
  /// `currentStreak` is only non-zero when the run reaches `asOf` (or the day
  /// before it — today may simply not have started yet). Without that anchor a
  /// streak abandoned weeks ago would still be reported as current.
  /// `asOf` is injectable so tests stay deterministic.
  public func records(asOf asOfDay: String = KeyMonitor.today()) throws -> Records {
    lock.lock()
    defer { lock.unlock() }

    guard let db: OpaquePointer = self.db, !isClosed else {
      throw StatsError.sqlite(code: SQLITE_MISUSE, message: "Database is closed")
    }

    let activitySQL: String = """
    SELECT day, total_presses, active_minutes
    FROM daily_activity
    WHERE total_presses > 0
    ORDER BY day ASC;
    """
    var activityStmt: OpaquePointer?
    try check(sqlite3_prepare_v2(db, activitySQL, -1, &activityStmt, nil), db: db)
    defer { sqlite3_finalize(activityStmt) }

    var activeDays: [DayStat] = []
    while true {
      let stepResult: Int32 = sqlite3_step(activityStmt)
      if stepResult == SQLITE_ROW {
        let dayString: String
        if let textPtr: UnsafePointer<UInt8> = sqlite3_column_text(activityStmt, 0) {
          dayString = String(cString: textPtr)
        } else {
          dayString = ""
        }
        let presses: Int = Int(sqlite3_column_int64(activityStmt, 1))
        let activeMinutes: Int = Int(sqlite3_column_int64(activityStmt, 2))
        activeDays.append(DayStat(day: dayString, presses: presses, activeMinutes: activeMinutes))
      } else if stepResult == SQLITE_DONE {
        break
      } else {
        try check(stepResult, db: db)
      }
    }

    var busiestDay: DayStat?
    var currentStreak: Int = 0
    var longestStreak: Int = 0

    if !activeDays.isEmpty {
      var maxPresses: Int = -1
      for dayStat in activeDays {
        // Strict `>` keeps the earliest day on a tie (activeDays is day-ascending).
        if dayStat.presses > maxPresses {
          maxPresses = dayStat.presses
          busiestDay = dayStat
        }
      }

      var calendar: Calendar = Calendar(identifier: .gregorian)
      if let utcTimeZone: TimeZone = TimeZone(identifier: "UTC") {
        calendar.timeZone = utcTimeZone

        let dateFormatter: DateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.timeZone = utcTimeZone
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        let dates: [Date] = activeDays.compactMap { dateFormatter.date(from: $0.day) }

        if !dates.isEmpty {
          var currentRun: Int = 1
          var maxRun: Int = 1

          for i in 1..<dates.count {
            let prevDate: Date = dates[i - 1]
            let currDate: Date = dates[i]
            let diff: Int? = calendar.dateComponents([.day], from: prevDate, to: currDate).day

            if diff == 1 {
              currentRun += 1
            } else if diff != 0 {
              currentRun = 1
            }

            if currentRun > maxRun {
              maxRun = currentRun
            }
          }

          longestStreak = maxRun
          // A run only counts as "current" if it reaches today, or yesterday
          // (today may not have any presses yet).
          if let lastDay: String = activeDays.last?.day,
            let lastDate: Date = dateFormatter.date(from: lastDay),
            let asOfDate: Date = dateFormatter.date(from: asOfDay),
            let gap: Int = calendar.dateComponents([.day], from: lastDate, to: asOfDate).day,
            (0...1).contains(gap) {
            currentStreak = currentRun
          }
        }
      }
    }

    let peakSQL: String = """
    SELECT hour
    FROM hourly_totals
    WHERE count > 0
    ORDER BY count DESC, hour ASC
    LIMIT 1;
    """
    var peakStmt: OpaquePointer?
    try check(sqlite3_prepare_v2(db, peakSQL, -1, &peakStmt, nil), db: db)
    defer { sqlite3_finalize(peakStmt) }

    var peakHour: Int?
    let peakStepResult: Int32 = sqlite3_step(peakStmt)
    if peakStepResult == SQLITE_ROW {
      peakHour = Int(sqlite3_column_int64(peakStmt, 0))
    } else if peakStepResult != SQLITE_DONE {
      try check(peakStepResult, db: db)
    }

    return Records(
      busiestDay: busiestDay,
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      peakHour: peakHour
    )
  }

  /// Every day with recorded activity, ascending by date.
  public func allDays() throws -> [DayStat] {
    lock.lock()
    defer { lock.unlock() }

    guard let db: OpaquePointer = self.db, !isClosed else {
      throw StatsError.sqlite(code: SQLITE_MISUSE, message: "Database is closed")
    }

    let sql: String = """
    SELECT day, total_presses, active_minutes
    FROM daily_activity
    ORDER BY day ASC;
    """
    var stmt: OpaquePointer?
    try check(sqlite3_prepare_v2(db, sql, -1, &stmt, nil), db: db)
    defer { sqlite3_finalize(stmt) }

    var results: [DayStat] = []
    while true {
      let stepResult: Int32 = sqlite3_step(stmt)
      if stepResult == SQLITE_ROW {
        let dayString: String
        if let textPtr: UnsafePointer<UInt8> = sqlite3_column_text(stmt, 0) {
          dayString = String(cString: textPtr)
        } else {
          dayString = ""
        }
        let presses: Int = Int(sqlite3_column_int64(stmt, 1))
        let activeMinutes: Int = Int(sqlite3_column_int64(stmt, 2))
        results.append(DayStat(day: dayString, presses: presses, activeMinutes: activeMinutes))
      } else if stepResult == SQLITE_DONE {
        break
      } else {
        try check(stepResult, db: db)
      }
    }
    return results
  }

  /// Closes the underlying database connection. Safe to call more than once.
  public func close() {
    lock.lock()
    defer { lock.unlock() }

    guard !isClosed else { return }
    isClosed = true
    if let dbHandle: OpaquePointer = db {
      sqlite3_close_v2(dbHandle)
      db = nil
    }
  }

  // MARK: - Private helpers

  private static func exec(_ sql: String, db: OpaquePointer) throws {
    var errMsg: UnsafeMutablePointer<CChar>?
    let rc: Int32 = sqlite3_exec(db, sql, nil, nil, &errMsg)
    if rc != SQLITE_OK {
      let message: String
      if let errMsg: UnsafeMutablePointer<CChar> = errMsg {
        message = String(cString: errMsg)
        sqlite3_free(errMsg)
      } else if let dbErr: UnsafePointer<CChar> = sqlite3_errmsg(db) {
        message = String(cString: dbErr)
      } else {
        message = "Unknown SQLite error"
      }
      throw StatsError.sqlite(code: rc, message: message)
    }
  }

  private func check(
    _ code: Int32,
    db: OpaquePointer,
    expected: Int32 = SQLITE_OK
  ) throws {
    if code != expected {
      let message: String
      if let errmsg: UnsafePointer<CChar> = sqlite3_errmsg(db) {
        message = String(cString: errmsg)
      } else {
        message = "Unknown SQLite error"
      }
      throw StatsError.sqlite(code: code, message: message)
    }
  }

  private func stepDone(_ stmt: OpaquePointer?, db: OpaquePointer) throws {
    let rc: Int32 = sqlite3_step(stmt)
    if rc != SQLITE_DONE {
      let message: String
      if let errmsg: UnsafePointer<CChar> = sqlite3_errmsg(db) {
        message = String(cString: errmsg)
      } else {
        message = "Unknown SQLite error"
      }
      throw StatsError.sqlite(code: rc, message: message)
    }
  }
}
