import Foundation
import Testing
@testable import AmbientCore

private let t0 = Date(timeIntervalSince1970: 1_790_700_000)

/// A flow that has swapped the wallpaper for a lock.
private func swapped() -> WallpaperSwapFlow {
    var flow = WallpaperSwapFlow(pending: false)
    _ = flow.lock(now: t0)
    _ = flow.began(ok: true, now: t0)
    return flow
}

@Suite struct WallpaperSwapFlowTests {
    @Test func aLockSwapsAndItsUnlockRestoresWithoutTheShortcut() {
        var flow = WallpaperSwapFlow(pending: false)
        #expect(flow.lock(now: t0) == [.begin])
        #expect(flow.began(ok: true, now: t0) == [.render])
        #expect(flow.pending)
        // This lock set Ambient's image, so the restore doesn't first check that it's still set (review I2).
        #expect(flow.unlock() == [.restore(force: true)])
        #expect(flow.restoreFinished(ok: true, now: t0.addingTimeInterval(3)) == [])
        #expect(flow.phase == .idle)
        #expect(!flow.pending)
    }

    @Test func aRelockDuringARestoreWaitsForIt() {
        // Review C1: a swap must never run while a restore is still putting the wallpaper back.
        var flow = swapped()
        #expect(flow.unlock() == [.restore(force: true)])
        #expect(flow.lock(now: t0.addingTimeInterval(3)) == [])
        #expect(flow.phase == .restoring)
        #expect(flow.restoreFinished(ok: true, now: t0.addingTimeInterval(5)) == [.begin])
        #expect(flow.began(ok: true, now: t0.addingTimeInterval(5)) == [.render])
        #expect(flow.unlock() == [.restore(force: true)])
    }

    @Test func anUnlockDuringARestoreCancelsTheWaitingRelock() {
        var flow = swapped()
        _ = flow.unlock()
        _ = flow.lock(now: t0.addingTimeInterval(2))
        #expect(flow.unlock() == [])
        #expect(flow.restoreFinished(ok: true, now: t0.addingTimeInterval(5)) == [])
        #expect(flow.phase == .idle)
    }

    @Test func aFailedRestoreIsRetriedCarefullyOnTheNextUnlock() {
        var flow = swapped()
        _ = flow.unlock()
        #expect(flow.restoreFinished(ok: false, now: t0.addingTimeInterval(5)) == [])
        #expect(flow.pending)
        // Live lock screen next time: no swap, but the owed restore is tried again.
        #expect(flow.unlock() == [.restore(force: false)])
        #expect(flow.restoreFinished(ok: true, now: t0.addingTimeInterval(9)) == [])
        #expect(!flow.pending)
    }

    @Test func aSwapLeftBehindIsRestoredAtLaunchUnlessLocked() {
        var unlocked = WallpaperSwapFlow(pending: true)
        #expect(unlocked.launched(locked: false) == [.restore(force: false)])
        var locked = WallpaperSwapFlow(pending: true)
        #expect(locked.launched(locked: true) == [])
        #expect(locked.unlock() == [.restore(force: false)])
        var clean = WallpaperSwapFlow(pending: false)
        #expect(clean.launched(locked: false) == [])
    }

    @Test func restoreFromSettingsOnlyWhenOwedAndIdle() {
        var flow = WallpaperSwapFlow(pending: true)
        #expect(flow.retry() == [.restore(force: false)])
        #expect(flow.retry() == [])
        var nothingOwed = WallpaperSwapFlow(pending: false)
        #expect(nothingOwed.retry() == [])
    }

    @Test func aBackupThatFailsMeansNoSwap() {
        var flow = WallpaperSwapFlow(pending: false)
        _ = flow.lock(now: t0)
        #expect(flow.began(ok: false, now: t0) == [])
        #expect(flow.phase == .idle)
        #expect(!flow.pending)
        #expect(flow.unlock() == [])
    }

    @Test func nothingIsDrawnWhileTheDisplaysSleep() {
        // Review M1: no PNG every 30 seconds all night.
        var flow = swapped()
        flow.displaysSlept()
        #expect(flow.tick(now: t0.addingTimeInterval(30)) == [])
        #expect(flow.moodsChanged(now: t0.addingTimeInterval(40)) == [])
        #expect(flow.screensChanged(now: t0.addingTimeInterval(45)) == [])
        #expect(flow.displaysWoke(now: t0.addingTimeInterval(50)) == [.render])
        #expect(flow.tick(now: t0.addingTimeInterval(80)) == [.render])
    }

    @Test func moodRedrawsAreAtLeastEightSecondsApart() {
        var flow = swapped()
        #expect(flow.moodsChanged(now: t0.addingTimeInterval(3)) == [])
        #expect(flow.moodsChanged(now: t0.addingTimeInterval(9)) == [.render])
        #expect(flow.moodsChanged(now: t0.addingTimeInterval(12)) == [])
    }

    @Test func nothingIsDrawnUnlessSwapped() {
        var flow = WallpaperSwapFlow(pending: false)
        #expect(flow.tick(now: t0) == [])
        #expect(flow.moodsChanged(now: t0) == [])
        #expect(flow.displaysWoke(now: t0) == [])
    }
}

@Suite struct WallpaperBackupTests {
    @Test func theUsersOwnWallpaperIsAlwaysBackedUp() {
        // Review I3: a marker left by an unfinished swap doesn't stop a fresh backup of what's really set now.
        #expect(WallpaperBackup.decide(backupPresent: true, storeShowsAmbient: false) == .takeNew)
        #expect(WallpaperBackup.decide(backupPresent: false, storeShowsAmbient: false) == .takeNew)
    }

    @Test func whileAmbientsImageIsSetTheBackupIsTheOnlyRecord() {
        #expect(WallpaperBackup.decide(backupPresent: true, storeShowsAmbient: true) == .keepExisting)
        #expect(WallpaperBackup.decide(backupPresent: false, storeShowsAmbient: true) == .refuse)
    }
}

@Suite struct LockLayerCheckTests {
    @Test func anUnseenLayerFallsBackOnlyWithTheDisplaysAwake() {
        // Review I1: a window on a sleeping display is never "visible"; that says nothing about the lock screen.
        #expect(LockLayerCheck.shouldFallBack(windowVisible: false, displaysAsleep: false))
        #expect(!LockLayerCheck.shouldFallBack(windowVisible: false, displaysAsleep: true))
        #expect(!LockLayerCheck.shouldFallBack(windowVisible: true, displaysAsleep: false))
    }
}
