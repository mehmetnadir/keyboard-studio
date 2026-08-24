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
        } else if model.pausedBySecureInput {
          secureInputBanner
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
        Text("stats.counting_off.title")
          .font(.headline)
        Text("stats.counting_off.detail")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button("stats.start_counting") { model.startMonitoring() }
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
        Text("stats.not_detected.title")
          .font(.headline)
        Text("stats.not_detected.detail")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button("stats.stop") { model.stopMonitoring() }
    }
    .padding(14)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
  }

  /// Shown while macOS withholds keyboard events — worth surfacing, because a
  /// counter that silently stops looks broken rather than trustworthy.
  private var secureInputBanner: some View {
    HStack(spacing: 12) {
      Image(systemName: "lock.fill")
        .font(.title2)
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 2) {
        Text("stats.secure_input.title")
          .font(.headline)
        Text("stats.secure_input.detail")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
    .padding(14)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
  }

  private var headline: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(model.lifetimeTotal, format: .number)
        .font(.system(size: 44, weight: .semibold, design: .rounded))
        .contentTransition(.numericText())
      Text("stats.lifetime")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  private var cards: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
      StatCard(
        title: "stats.today", value: model.today?.presses ?? 0,
        detail: "stats.active_minutes".localized(model.today?.activeMinutes ?? 0))
      StatCard(title: "stats.this_month", value: model.monthTotal, detail: nil)
      StatCard(title: "stats.this_year", value: model.yearTotal, detail: nil)
      if let peak = model.records?.peakHour {
        StatCard(
          title: "stats.peak_hour", text: String(format: "%02d:00", peak),
          detail: "stats.peak_hour.detail".localized)
      }
    }
  }

  private func streaks(_ records: Records) -> some View {
    HStack(spacing: 12) {
      StatCard(
        title: "stats.current_streak", text: "\(records.currentStreak)",
        detail: (records.currentStreak == 1 ? "stats.streak.day" : "stats.streak.days").localized)
      StatCard(
        title: "stats.longest_streak", text: "\(records.longestStreak)",
        detail: "stats.streak.days_short".localized)
      if let busiest = records.busiestDay {
        StatCard(
          title: "stats.busiest_day", text: busiest.day,
          detail: "stats.busiest_day.detail".localized(busiest.presses.formatted()))
      }
    }
  }

  private var champions: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("stats.champions")
        .font(.headline)
      if model.monthChampions.isEmpty {
        Text("stats.champions.empty")
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
  let title: LocalizedStringKey
  var value: Int?
  var text: String?
  /// Already-localized text (these carry interpolated numbers).
  let detail: String?

  init(title: LocalizedStringKey, value: Int, detail: String?) {
    self.title = title
    self.value = value
    self.detail = detail
  }

  init(title: LocalizedStringKey, text: String, detail: String?) {
    self.title = title
    self.text = text
    self.detail = detail
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
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
