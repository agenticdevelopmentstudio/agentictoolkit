import AppKit
import Testing
import AgenticDeveloperToolkit
import AgenticToolkitSystemMonitor
@testable import AgenticToolkitSystemMonitorUI

private func reading(
    _ id: String, _ level: MonitorLevel, value: String = "1 GB", detail: String = "detail", fraction: Double? = 0.5
) -> MonitorReading {
    MonitorReading(id: id, title: id.capitalized, level: level, value: value, detail: detail, fraction: fraction)
}

private struct Fixed: SystemMonitor {
    let id: String
    let title: String
    let level: MonitorLevel
    func sample() -> MonitorReading { MonitorReading(id: id, title: title, level: level, value: "sampled") }
}

@MainActor
@Suite("Monitor level colors")
struct MonitorLevelThemeTests {

    @Test func eachLevelHasItsOwnThemeRole() {
        #expect(MonitorLevel.unknown.themeRole == .tertiaryText)
        #expect(MonitorLevel.normal.themeRole == .success)
        #expect(MonitorLevel.warning.themeRole == .warning)
        #expect(MonitorLevel.critical.themeRole == .danger)
        #expect(Set(MonitorLevel.allCases.map(\.accessibilityLabel)).count == MonitorLevel.allCases.count)
    }
}

@MainActor
@Suite("Monitor reading row")
struct MonitorReadingRowViewTests {

    @Test func showsTheReading() {
        let row = MonitorReadingRowView(reading: reading("disk", .warning, value: "12 GB free", detail: "5% of 1 TB"))
        #expect(row.titleLabel.stringValue == "Disk")
        #expect(row.valueLabel.stringValue == "12 GB free")
        #expect(row.detailLabel.stringValue == "5% of 1 TB")
        #expect(!row.detailLabel.isHidden)
        #expect(row.gauge.fraction == 0.5)
    }

    @Test func theDotAndGaugeTakeTheLevelsThemeColor() {
        let row = MonitorReadingRowView(reading: reading("cpu", .critical))
        let palette = row.resolvedThemeScope.palette
        #expect(row.dot.layer?.backgroundColor == palette.nsColor(.danger).cgColor)
        #expect(row.gauge.fillLayer.backgroundColor == palette.nsColor(.danger).cgColor)

        row.update(with: reading("cpu", .normal))
        #expect(row.dot.layer?.backgroundColor == palette.nsColor(.success).cgColor)
        #expect(row.gauge.level == .normal)
    }

    @Test func anEmptyDetailIsHidden() {
        let row = MonitorReadingRowView(reading: reading("docker", .normal, detail: ""))
        #expect(row.detailLabel.isHidden)
    }

    @Test func theGaugeFillsToItsFraction() {
        let gauge = MonitorGaugeView()
        gauge.frame = NSRect(x: 0, y: 0, width: 200, height: MonitorGaugeView.height)
        gauge.update(fraction: 0.25, level: .warning)
        gauge.layout()
        #expect(gauge.fillLayer.frame.width == 50)

        gauge.update(fraction: nil, level: .unknown)
        gauge.layout()
        #expect(gauge.fillLayer.frame.width == 0)
    }
}

@MainActor
@Suite("System status view")
struct SystemStatusViewTests {

    @Test func oneRowPerReadingInOrder() {
        let view = SystemStatusView()
        view.show([reading("disk", .normal), reading("memory", .warning)], refreshedAt: nil)
        #expect(view.rows.map(\.reading.id) == ["disk", "memory"])
        #expect(view.updatedLabel.stringValue.hasPrefix("Waiting"))
    }

    @Test func theSameMonitorsUpdateTheirRowsInPlace() {
        let view = SystemStatusView()
        view.show([reading("disk", .normal)], refreshedAt: nil)
        let row = view.rows[0]
        view.show([reading("disk", .critical, value: "1 GB free")], refreshedAt: Date())
        #expect(view.rows[0] === row)
        #expect(row.valueLabel.stringValue == "1 GB free")
        #expect(view.updatedLabel.stringValue.hasPrefix("Updated "))
    }

    @Test func aDifferentSetOfMonitorsRebuildsTheRows() {
        let view = SystemStatusView()
        view.show([reading("disk", .normal)], refreshedAt: nil)
        view.show([reading("cpu", .normal), reading("disk", .normal)], refreshedAt: nil)
        #expect(view.rows.map(\.reading.id) == ["cpu", "disk"])
        #expect(view.rows.allSatisfy { $0.superview != nil })
    }
}

@MainActor
@Suite("System status window")
struct SystemStatusWindowTests {

    @Test func theWindowIsTitledAndSized() {
        let engine = SystemMonitorEngine(monitors: [Fixed(id: "a", title: "A", level: .normal)])
        let controller = SystemStatusWindowController(engine: engine)
        #expect(controller.windowID == SystemStatusWindowController.windowID)
        #expect(controller.windowTitle == "System Status")
        #expect(controller.minSize == controller.windowSpec?.minSize)
        #expect(controller.viewController?.engine === engine)
    }

    @Test func theViewFollowsTheEngineOnlyWhileOnScreen() async {
        let engine = SystemMonitorEngine(monitors: [Fixed(id: "a", title: "A", level: .warning)])
        let controller = SystemStatusViewController(engine: engine)
        _ = controller.view

        controller.viewWillAppear()
        #expect(controller.contentView.rows.map(\.reading.level) == [.unknown])
        await engine.refresh()
        #expect(controller.contentView.rows.map(\.reading.level) == [.warning])
        #expect(controller.contentView.updatedLabel.stringValue.hasPrefix("Updated "))

        controller.viewDidDisappear()
        let rowsBefore = controller.contentView.rows.map(\.reading)
        await engine.refresh()
        #expect(controller.contentView.rows.map(\.reading) == rowsBefore)
    }
}
