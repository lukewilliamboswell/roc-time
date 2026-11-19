import fuzz.Fuzz
import RecurrenceCase
import "../fuzz/corpus/recurrence/boundary-exclusion-merge-buffer" as regression_0 : List(U8)
import "../fuzz/corpus/recurrence/local-gap-boundary-exclusion" as regression_1 : List(U8)

RecurrenceTarget := [].{
	target = Fuzz.target({
		name: "recurrence-v1",
		examples: [
			Fuzz.saved({
				name: "boundary-exclusion-merge-buffer",
				revision: "1",
				bytes: regression_0,
			}),
			Fuzz.saved({
				name: "local-gap-boundary-exclusion",
				revision: "1",
				bytes: regression_1,
			}),
			Fuzz.example({
				name: "month-end-small-budget",
				revision: "1",
				make: || RecurrenceCase.{
					last_monday: Bool.False,
					interval: 1,
					count: 6,
					query_month: 1,
					exclude_anchor: Bool.True,
					work: 1,
				},
			}),
			Fuzz.example({
				name: "last-monday-later-window",
				revision: "1",
				make: || RecurrenceCase.{
					last_monday: Bool.True,
					interval: 3,
					count: 6,
					query_month: 12,
					exclude_anchor: Bool.False,
					work: 128,
				},
			}),
		],
		test: RecurrenceCase.check,
		show: Str.inspect,
	})
}
