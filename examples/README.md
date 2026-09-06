# Example applications

Start with [booking exchange](booking_exchange/main.roc) for text input,
availability calculation and text output, or [archive search](archive_search/main.roc)
for dates whose supplied precision and uncertainty must be preserved.

Each application has a `main.roc` entrypoint and a pure type module. From the
repository root, use the compiler pinned in [`.roc-version`](../.roc-version),
then run an entrypoint, for example `roc examples/booking_exchange/main.roc`.
The integration gate checks these applications locally and against the package bundle.

| Application | Demonstrates |
| --- | --- |
| [Room availability](coverage/main.roc) | Retain booking identities, report conflicts and subtract occupied coverage from opening hours |
| [Booking exchange](booking_exchange/main.roc) | Read bookings with different offsets, persist computed availability and serialize restored free windows in UTC |
| [Annotation review](annotation_review/main.roc) | Preserve IXDTF zone/calendar annotations and distinguish an offset conflict from unsupported presentation |
| [Explain event terms](explain_event_terms/main.roc) | Review calendar-day versus clock-duration terms, local/UTC PERIOD inputs and an exact interval with different endpoint offsets |
| [Explain annotations](explain_annotations/main.roc) | Explain a declaration's context requirement and its stored interpretation with unsupported calendar presentation |
| [Review a recurrence](explain_recurrence/main.roc) | Explain COUNT and exclusions, an additional date, and an unbounded zoned meeting before choosing evaluation context |
| [Explain a civil selection](explain_selection/main.roc) | Explain a later fold appointment and a disconnected selection across bounded evaluation and resumption |
| [Civil snapshot archive](civil_snapshot_archive/main.roc) | Restore explicit fold choices and both windows of a repeated local range |
| [Snapshot archive](snapshot_persistence/main.roc) | Restore an interpretation with its original rules, then explicitly reinterpret it under changed data |
| [Archive persistence](archive_persistence/main.roc) | Save and restore an uncertain catalogue date, a recording declaration and its exact POSIX boundary |
| [Archive date](calendar_conversion/main.roc) | Convert an explicitly identified calendar while retaining the source description |
| [Invoice terms](invoice/main.roc) | Calculate a civil due date with explicit month-end clamping |
| [Overnight staffing](staffing/main.roc) | Budget a local overnight shift across a clock change using the optional zone database |
| [Voyage briefing](voyage/main.roc) | Supply a ship's clock schedule and review a rules update while retaining the saved booking |
| [Equipment inspections](inspections/main.roc) | Schedule four inspections on the last Tuesday every three months, with explicit evaluation limits |
| [Equipment reservations](reservations/main.roc) | Import a timed RRULE and PERIOD additions with explicit return times or positive durations |
| [Service calendar](maintenance/main.roc) | Import date-only recurrence values and review rescheduled visits without restarting the original series count |
| [Dispatch deadlines](dispatch_deadlines/main.roc) | Select the final pickup slot of each month’s final Monday, preserving local time across daylight saving and series count across queries |
| [Equipment loans](equipment_loans/main.roc) | Keep monthly loans on the 31st, clamp return dates across clock changes, and add an extra one-week booking |
| [Outage evidence](outage_evidence/main.roc) | Compare paired outage reports with independent endpoint notes without inventing correlations |
| [Archive search](archive_search/main.roc) | Import EDTF dates and offset timestamps; preserve search precision and unresolved qualifications |
| [Recorder handoff](sample_windows/main.roc) | Classify consecutive microsecond sample windows without losing exact boundaries |

