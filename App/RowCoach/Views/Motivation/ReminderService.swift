import Foundation
import os
import UserNotifications
import RowCoachKit

/// Lokale Erinnerungen „Wann ruderst du?“ (UNUserNotificationCenter, kein Server). Plan in RowCoachKit
/// (`ReminderPlanner`): höchstens eine pro Tag, nur an Wunschtagen, nie an Ruhetagen laut Plan, nie in einer Pause,
/// eine Woche Ruhe nach zwei unbeachteten. Die Berechtigung wird erst beim Einschalten erfragt.
@MainActor
final class ReminderService {
    static let shared = ReminderService()

    private let center = UNUserNotificationCenter.current()
    private let log = Logger(subsystem: "com.falkue.RowCoach", category: "Motivation")

    /// Berechtigung erfragen (beim Einschalten der Erinnerung); true = erlaubt
    func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            log.error("Mitteilungen: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Erlaubt? (ohne Dialog)
    func isAuthorized() async -> Bool {
        let s = await center.notificationSettings()
        return s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
    }

    /// Alle eigenen geplanten Erinnerungen entfernen und neu planen (bei jedem Neurechnen des Startbildschirms).
    /// - Parameters:
    ///   - planDays: Wochentage des aktiven Plans (nil ohne Plan)
    ///   - trainingDates: Tage mit Planeinheit (nil ohne Plan)
    ///   - suggestions: Kurztext des Vorschlags je Tagesbeginn
    func reschedule(sessions: [TrainingSession], planDays: [Weekday]?, trainingDates: [Date]?,
                    suggestions: [Date: String], now: Date = Date()) async {
        let cal = TrainingCalendar.swiss()
        // zugestellte Erinnerungen merken, noch nicht zugestellte vergessen (werden neu geplant)
        var delivered = MotivationSettings.reminderLog.filter { $0 <= now }
        let pending = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(ReminderPlanner.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier))
        guard let intention = MotivationSettings.intention, intention.remindersOn else {
            MotivationSettings.reminderLog = delivered
            return
        }
        guard await isAuthorized() else {
            MotivationSettings.reminderLog = delivered
            return
        }
        let quiet = ReminderPlanner.quietUntil(reminders: delivered, sessions: sessions, now: now, calendar: cal)
        let slots = ReminderPlanner.plan(intention: intention, days: intention.effectiveDays(planDays: planDays),
                                         now: now, calendar: cal, sessions: sessions,
                                         pauses: MotivationSettings.pauses, trainingDates: trainingDates,
                                         suggestions: suggestions, quietUntil: quiet)
        for slot in slots {
            let content = UNMutableNotificationContent()
            content.title = slot.title
            content.body = slot.body
            content.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: slot.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: slot.identifier, content: content, trigger: trigger))
                delivered.append(slot.date)
            } catch {
                log.error("Erinnerung \(slot.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        // auch die künftigen merken; beim nächsten Neuplanen fallen noch nicht zugestellte wieder weg
        MotivationSettings.reminderLog = delivered
        log.info("Erinnerungen geplant: \(slots.count, privacy: .public)")
    }

    /// Alles entfernen (Erinnerung ausgeschaltet)
    func removeAll() async {
        let pending = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(ReminderPlanner.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier))
        MotivationSettings.reminderLog = MotivationSettings.reminderLog.filter { $0 <= Date() }
    }
}
