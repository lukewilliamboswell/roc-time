# Example applications

Start with [booking exchange](booking_exchange/main.roc): give it opening hours
and bookings with explicit offsets, and it prints the free UTC windows. For
archive dates such as “June 2026” or an uncertain year, try
[archive search](archive_search/main.roc).

Each application has a `main.roc` entrypoint and companion type modules. In this
repository they depend on the working-tree packages by relative path, so they
show the API on the default branch: clone the repository and run
`roc examples/booking_exchange/main.roc` with a current Roc nightly.

To run them against a published release instead, download that release's
`roc-time-examples-<version>.zip`. It holds these same applications with only the
package dependencies changed to that release's URLs, and its release notes name
the compiler it was built and tested with. Keep each application's folder
together.

CI runs every application here in place. Before publication, it also runs the
generated release archive against the exact bundles being published. Published
archives stay unchanged; repository examples can evolve with the library.

## Choose an application

The catalog below describes this checkout. A release archive contains the
applications available when that release was built, which may be fewer.

| Application | Demonstrates |
| --- | --- |
| [Room availability](coverage/main.roc) | Retain booking identities, report conflicts and subtract occupied coverage from opening hours |
| [Booking exchange](booking_exchange/main.roc) | Read bookings with different offsets and serialize computed free windows in UTC |
| [Clock deadline](clock_deadline/main.roc) | Read the platform clock, check an expiry boundary and emit a typed JSON record with exact UTC microseconds |
| [Annotation review](annotation_review/main.roc) | Preserve IXDTF zone/calendar annotations and distinguish an offset conflict from unsupported presentation |
| [Explain event terms](explain_event_terms/main.roc) | Review calendar-day versus clock-duration terms, local/UTC PERIOD inputs and an exact interval with different endpoint offsets |
| [Explain annotations](explain_annotations/main.roc) | Explain a declaration's context requirement and its stored interpretation with unsupported calendar presentation |
| [Review a recurrence](explain_recurrence/main.roc) | Explain COUNT and exclusions, an additional date, and an unbounded zoned meeting before choosing evaluation context |
| [Explain a civil selection](explain_selection/main.roc) | Explain a later fold appointment and a disconnected selection across bounded evaluation and resumption |
| [Repeated local time](repeated_local_time/main.roc) | Compare explicit fold choices with both windows of a repeated local range |
| [Interpretation context](interpretation_context/main.roc) | Retain an in-memory interpretation with its original rules, then explicitly reinterpret it under changed data |
| [Catalogue storage](catalogue_storage/main.roc) | Store an uncertain date as EDTF and a recording timestamp as RFC 3339 |
| [Archive date](calendar_conversion/main.roc) | Convert an explicitly identified calendar while retaining the source description |
| [Invoice terms](invoice/main.roc) | Calculate a civil due date with explicit month-end clamping |
| [Invoice report](invoice_report/main.roc) | Display accounting dates and group totals by ISO week, including a week crossing New Year |
| [Appointment display](appointment_display/main.roc) | Format local dates and clock labels in English without silently discarding precision |
| [Named-zone appointment](zoned_appointment/main.roc) | Show Paris appointments in New York and handle repeated, skipped and unavailable local times |
| [Overnight staffing](staffing/main.roc) | Budget a local overnight shift across a clock change using the optional zone database |
| [Voyage briefing](voyage/main.roc) | Supply a ship's clock schedule and review a rules update while retaining the saved booking |
| [Equipment inspections](inspections/main.roc) | Schedule four inspections on the last Tuesday every three months, with explicit evaluation limits |
| [Equipment reservations](reservations/main.roc) | Import a timed RRULE and PERIOD additions with explicit return times or positive durations |
| [Service calendar](maintenance/main.roc) | Import date-only recurrence values and review rescheduled visits without restarting the original series count |
| [Schedule exchange](schedule_exchange/main.roc) | Edit and reimport a date-only rule, with additions and exclusions that preserve COUNT |
| [Meeting exchange](meeting_exchange/main.roc) | Edit a Paris meeting, preserve a UTC cancellation and export canonical property values |
| [Upcoming meetings](upcoming_meetings/main.roc) | Page through a reusable Paris meeting definition one result at a time |
| [Dispatch deadlines](dispatch_deadlines/main.roc) | Select the final pickup slot of each month’s final Monday, preserving local time across daylight saving and series count across queries |
| [Equipment loans](equipment_loans/main.roc) | Keep monthly loans on the 31st, clamp return dates across clock changes, and add an extra one-week booking |
| [Outage evidence](outage_evidence/main.roc) | Compare paired outage reports with independent endpoint notes without inventing correlations |
| [Archive intervals](archive_intervals/main.roc) | Import and save mixed-precision creation dates, preserving unknown versus open ends without inventing exact appointments |
| [Archive search](archive_search/main.roc) | Import EDTF dates and offset timestamps; preserve search precision and unresolved qualifications |
| [Recorder handoff](sample_windows/main.roc) | Classify consecutive microsecond sample windows without losing exact boundaries |
