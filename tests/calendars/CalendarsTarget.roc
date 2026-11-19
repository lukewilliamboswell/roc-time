import fuzz.Fuzz
import CalendarCase

CalendarsTarget := [].{
	target = Fuzz.target({
		name: "calendars-v1",
		examples: [
			Fuzz.example({
				name: "provider-start",
				revision: "1",
				make: || CalendarCase.{
					number: -784369121962,
				},
			}),
			Fuzz.example({
				name: "provider-end",
				revision: "1",
				make: || CalendarCase.{
					number: 784367682901,
				},
			}),
			Fuzz.example({
				name: "shared-epoch",
				revision: "1",
				make: || CalendarCase.{
					number: 0,
				},
			}),
		],
		test: CalendarCase.check,
		show: Str.inspect,
	})
}
