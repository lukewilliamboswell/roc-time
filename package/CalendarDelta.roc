## Ordered calendar components, not an elapsed or POSIX displacement.
## Arithmetic applies years, then months, then civil days.
CalendarDelta :: [Parts({ years : I64, months : I64, days : I64 })].{
	Components : { years : I64, months : I64, days : I64 }
	from_components : Components -> CalendarDelta
	from_components = |components| Parts(components)
	to_components : CalendarDelta -> Components
	to_components = |Parts(components)| components
	years : I64 -> CalendarDelta
	years = |n| Parts({ years: n, months: 0, days: 0 })
	months : I64 -> CalendarDelta
	months = |n| Parts({ years: 0, months: n, days: 0 })
	days : I64 -> CalendarDelta
	days = |n| Parts({ years: 0, months: 0, days: n })
}
