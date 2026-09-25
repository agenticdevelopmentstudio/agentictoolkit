import Foundation
import AgenticToolkitCore

// The one piece of billing editing that can't live in `AgenticToolkitCore`:
// `RecordDetailItem` is an AppKit-side protocol of this framework, and Core
// can't see it. The editing helpers themselves (`replacing`, `repriced`,
// `billingRate(parsing:)`, `BillingRecordTitle`) are Core's.

extension BillingClientDTO: RecordDetailItem {
    public var recordTitle: String { BillingRecordTitle.of(name) }
}

extension BillingProjectDTO: RecordDetailItem {
    public var recordTitle: String { BillingRecordTitle.of(name) }
}
