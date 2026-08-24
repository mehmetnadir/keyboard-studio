import StatsCore
import SwiftUI

struct StatsView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        if !model.monitoringEnabled {
          permissionBanner
        } else if model.keyboardNotDetected {
          notDetectedBanner
        }
        headline
        cards
        if let records = model.records {
          streaks(records)
        }
        champions
        if let error = model.statsError {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
        }
      }
      .padding(20)
    }
    .background(.background)
  }

  // MARK: - Sections

  private var permissionBanner: some View {
    HStack(spacing: 12) {
      Image(systemName: "keyboard.badge.eye")
        .font(.title2)
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 2) {
        Text("Counting is off")
          .font(.headline)
        Text("Only your K86 is counted, and only how many times each key was pressed.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button("Start counting") { model.startMonitoring() }
        .buttonStyle(.borderedProminent)
    }
    .padding(14)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
  }

  private var notDetectedBanner: some View {
    HStack(spacing: 12) {
      Image(systemName: "exclamationmark.triangle")
        .font(.title2)
        .foregroundStyle(.orange)
      VStack(alignment: .leading, spacing: 2) {
        Text("Counting is on, but no K86 is visible")
          .font(.headline)
        Text("Nothing will be counted until the keyboard is connected.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button("Stop") { model.stopMonitoring() }
    }
    .padding(14)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
  }

  private var headline: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(model.lifetimeTotal, format: .number)
        .font(.system(size: 44, weight: .semibold, design: .rounded))
        .contentTransition(.numericText())
      Text("keys pressed, all time")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  private var cards: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
      StatCard(
        title: "Today", value: model.today?.presses ?? 0,
        detail: "\(model.today?.activeMinutes ?? 0) active min")
      StatCard(title: "This month", value: model.monthTotal, detail: nil)
      StatCard(title: "This year", value: model.yearTotal, detail: nil)
      if let peak = model.records?.peakHour {
        StatCard(
          title: "Peak hour", text: String(format: "%02d:00", peak),
          detail: "when you type most")
      }
    }
  }

  private func streaks(_ records: Records) -> some View {
    HStack(spacing: 12) {
      StatCard(
        title: "Current streak", text: "\(records.currentStreak)",
        detail: records.currentStreak == 1 ? "day" : "days in a row")
      StatCard(
        title: "Longest streak", text: "\(records.longestStreak)", detail: "days")
      if let busiest = records.busiestDay {
        StatCard(
          title: "Busiest day", text: busiest.day,
          detail: "\(busiest.presses.formatted()) presses")
      }
    }
  }

  private var champions: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("This month's champions")
        .font(.headline)
      if model.monthChampions.isEmpty {
        Text("No presses recorded yet this month.")
          .font(.callout)
          .foregroundStyle(.secondary)
      } else {
        let top = model.monthChampions.first?.count ?? 1
        ForEach(Array(model.monthChampions.enumerated()), id: \.element.keycode) { index, stat in
          ChampionRow(rank: index + 1, stat: stat, maxCount: top)
        }
      }
    }
  }
}

private struct StatCard: View {
  let title: String
  var value: Int?
  var text: String?
  let detail: String?

  init(title: String, value: Int, detail: String?) {
    self.title = title
    self.value = value
    self.detail = detail
  }

  init(title: String, text: String, detail: String?) {
    self.title = title
    self.text = text
    self.detail = detail
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Group {
        if let value {
          Text(value, format: .number)
        } else {
          Text(text ?? "—")
        }
      }
      .font(.system(size: 22, weight: .medium, design: .rounded))
      if let detail {
        Text(detail)
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
  }
}

private struct ChampionRow: View {
  let rank: Int
  let stat: KeyStat
  let maxCount: Int

  var body: some View {
    HStack(spacing: 10) {
      Text("\(rank)")
        .font(.caption.monospacedDigit())
        .foregroundStyle(.tertiary)
        .frame(width: 18, alignment: .trailing)
      Text(KeyNames.name(for: stat.keycode))
        .font(.system(.callout, design: .rounded))
        .frame(width: 110, alignment: .leading)
      GeometryReader { geometry in
        RoundedRectangle(cornerRadius: 4)
          .fill(.tint.opacity(0.75))
          .frame(width: max(4, geometry.size.width * fraction))
      }
      .frame(height: 14)
      Text(stat.count, format: .number)
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(width: 70, alignment: .trailing)
    }
  }

  private var fraction: Double {
    maxCount > 0 ? Double(stat.count) / Double(maxCount) : 0
  }
}
