import AppKit
import Foundation
import UserNotifications

@MainActor
protocol FocusBlockDeadlineAlerting: AnyObject {
    var onDeadlineReached: (@MainActor @Sendable (PomodoroBlock.ID) -> Void)? { get set }

    func scheduleDeadline(for block: PomodoroBlock)
    func cancelDeadline(for blockID: PomodoroBlock.ID)
    func cancelAllDeadlines()
}

@MainActor
final class NoOpFocusBlockDeadlineAlertService: FocusBlockDeadlineAlerting {
    var onDeadlineReached: (@MainActor @Sendable (PomodoroBlock.ID) -> Void)?

    func scheduleDeadline(for block: PomodoroBlock) {}

    func cancelDeadline(for blockID: PomodoroBlock.ID) {}

    func cancelAllDeadlines() {}
}

@MainActor
final class FocusBlockDeadlineAlertService: FocusBlockDeadlineAlerting {
    var onDeadlineReached: (@MainActor @Sendable (PomodoroBlock.ID) -> Void)?

    private let notificationCenter: UNUserNotificationCenter
    private var timer: Timer?
    private var scheduledBlock: ScheduledFocusBlock?
    private var scheduleGeneration = UUID()

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    func scheduleDeadline(for block: PomodoroBlock) {
        guard block.status == .active else {
            return
        }

        cancelAllDeadlines()

        let generation = UUID()
        scheduleGeneration = generation
        scheduledBlock = ScheduledFocusBlock(
            id: block.id,
            blockIndex: block.blockIndex,
            generation: generation,
            shouldPostImmediateNotification: block.remainingSeconds() == 0
        )

        let remainingSeconds = block.remainingSeconds()
        if remainingSeconds == 0 {
            handleDeadlineReached(for: block.id)
            return
        }

        let delay = TimeInterval(max(1, remainingSeconds))
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleDeadlineReached(for: block.id)
            }
        }
        timer?.tolerance = min(5, max(0.5, delay * 0.05))

        Task {
            await scheduleNotification(for: block, after: delay, generation: generation)
        }
    }

    func cancelDeadline(for blockID: PomodoroBlock.ID) {
        if scheduledBlock?.id == blockID {
            timer?.invalidate()
            timer = nil
            scheduledBlock = nil
            scheduleGeneration = UUID()
        }

        let identifier = notificationIdentifier(for: blockID)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func cancelAllDeadlines() {
        timer?.invalidate()
        timer = nil

        if let scheduledBlock {
            let identifier = notificationIdentifier(for: scheduledBlock.id)
            notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
            notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
        }
        scheduledBlock = nil
        scheduleGeneration = UUID()
    }

    private func handleDeadlineReached(for blockID: PomodoroBlock.ID) {
        guard let scheduledBlock, scheduledBlock.id == blockID else {
            return
        }

        timer?.invalidate()
        timer = nil

        if scheduledBlock.shouldPostImmediateNotification {
            Task {
                await postImmediateNotification(for: scheduledBlock)
            }
        }

        NSApp.unhide(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        onDeadlineReached?(blockID)
    }

    private func scheduleNotification(
        for block: PomodoroBlock,
        after delay: TimeInterval,
        generation: UUID
    ) async {
        guard await notificationsAreAllowed() else {
            return
        }
        guard scheduleGeneration == generation,
              scheduledBlock?.id == block.id
        else {
            return
        }

        let request = UNNotificationRequest(
            identifier: notificationIdentifier(for: block.id),
            content: notificationContent(forBlockIndex: block.blockIndex),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            // The in-app prompt and app activation are still the authoritative deadline behavior.
        }
    }

    private func postImmediateNotification(for block: ScheduledFocusBlock) async {
        guard await notificationsAreAllowed() else {
            return
        }
        guard scheduleGeneration == block.generation,
              scheduledBlock?.id == block.id
        else {
            return
        }

        let request = UNNotificationRequest(
            identifier: notificationIdentifier(for: block.id),
            content: notificationContent(forBlockIndex: block.blockIndex),
            trigger: nil
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            // The in-app prompt and app activation are still the authoritative deadline behavior.
        }
    }

    private func notificationsAreAllowed() async -> Bool {
        do {
            return try await notificationCenter.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    private func notificationContent(forBlockIndex blockIndex: Int) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Focus block complete"
        content.body = "Block \(blockIndex) is ready to review. Capture what changed before the next block."
        content.sound = .default
        return content
    }

    private func notificationIdentifier(for blockID: PomodoroBlock.ID) -> String {
        "focus-block-deadline:\(blockID.uuidString)"
    }
}

private struct ScheduledFocusBlock {
    let id: PomodoroBlock.ID
    let blockIndex: Int
    let generation: UUID
    let shouldPostImmediateNotification: Bool
}
