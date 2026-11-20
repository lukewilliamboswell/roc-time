import Calendar
import CivilDay
import ClockTime
import GregorianDate
import LocalDateTime
import LocalLabel
import MicrosecondRounding
import NanoClockTime

## An unresolved civil date and clock label at nanosecond precision.
NanoLocalDateTime :: { date : Calendar.Date, clock : NanoClockTime }.{

	## Errors from the native Gregorian local-label parser, including invalid date
	## or clock fields, incomplete/malformed input and unsupported precision.
	TextError : [TooLarge, Incomplete, Malformed, InvalidDate(GregorianDate.Error), InvalidTime(NanoClockTime.Error)]

	## Parse an explicitly Gregorian local label: date, uppercase T, then clock.
	## The date and clock use GregorianDate.parse and NanoClockTime.parse profiles.
	## At most 64 UTF-8 bytes; omitted clock seconds become zero. No offset,
	## zone, occurrence or supplied-field resolution is inferred. This native
	## profile does not claim all ISO 8601 forms. Julian values require explicit
	## construction; their fields are never silently treated as Gregorian.
	parse_gregorian : Str -> Try(NanoLocalDateTime, TextError)
	parse_gregorian = |text| {
		fields = LocalLabel.parse(text, NanoClockTime.parse)?
		Ok(new(fields))
	}

	## Canonical Gregorian date/clock text preserves the local position. It is
	## neither a resolved timestamp nor a persistence format for every calendar.
	## Reject other calendars; callers can explicitly convert with in_calendar.
	to_gregorian_text : NanoLocalDateTime -> Try(Str, [UnsupportedCalendar(Calendar)])
	to_gregorian_text = |value| {
		day = Calendar.Date.as_gregorian(value.date)?
		Ok("${GregorianDate.to_text(day)}T${NanoClockTime.to_text(value.clock)}")
	}

	## Combine a validated calendar date and clock label without choosing an offset
	## or timezone. Resolve the result explicitly before timeline computation.
	new : { date : Calendar.Date, clock : NanoClockTime } -> NanoLocalDateTime
	new = |fields| NanoLocalDateTime.{ date: fields.date, clock: fields.clock }

	## Read the calendar date as described, retaining its calendar identity.
	date : NanoLocalDateTime -> Calendar.Date
	date = |value| value.date

	## Read the local clock label without resolving it to a timeline.
	clock : NanoLocalDateTime -> NanoClockTime
	clock = |value| value.clock

	## Describe the same civil-day and clock position in another supported calendar.
	## The clock is unchanged; an unsupported destination date returns OutOfRange.
	in_calendar : NanoLocalDateTime, Calendar -> Try(NanoLocalDateTime, [OutOfRange])
	in_calendar = |value, target| {
		converted = Calendar.Date.in_calendar(value.date, target)?
		Ok(new({ date: converted, clock: value.clock }))
	}

	## Compare local positions, not timeline occurrences or descriptions.
	compare_position : { left : NanoLocalDateTime, right : NanoLocalDateTime } -> [Before, Same, After]
	compare_position = |{ left: a, right: b }| {
		days = CivilDay.order_relative_to(Calendar.Date.to_civil_day(a.date), Calendar.Date.to_civil_day(b.date))
		match days {
			Same => a.clock.to_nanoseconds_since_midnight().order_relative_to(b.clock.to_nanoseconds_since_midnight())
			Before => Before
			After => After
		}
	}

	## Whether both labels have the same civil-day coordinate and clock position.
	## Different calendar descriptions can match; no timezone is involved.
	same_position : NanoLocalDateTime, NanoLocalDateTime -> Bool
	same_position = |a, b| compare_position({ left: a, right: b }) == Same

	## Description equality preserves the calendar as well as the clock label.
	is_eq : NanoLocalDateTime, NanoLocalDateTime -> Bool
	is_eq = |a, b| a.date == b.date and a.clock == b.clock

	## Hash description identity, including the calendar and clock, consistently
	## with is_eq. Use explicit conversion when keys should ignore calendar identity.
	to_hash : NanoLocalDateTime, Hasher -> Hasher
	to_hash = |value, hasher| value.clock.to_hash(value.date.to_hash(hasher))

	## Describe the calendar date and local clock for diagnostics, without choosing
	## a zone or resolving an occurrence.
	to_inspect : NanoLocalDateTime -> Str
	to_inspect = |value| "NanoLocalDateTime(${Str.inspect(value.date)}, ${Str.inspect(value.clock)})"

	## Decode signed nanoseconds on the nominal Gregorian civil axis starting at 1970-01-01.
	from_gregorian_local_nanoseconds : I64 -> NanoLocalDateTime
	from_gregorian_local_nanoseconds = |value| {
		remainder = value.mod_by(day_nanoseconds)
		day = value // day_nanoseconds - if (value % day_nanoseconds < 0) 1 else 0
		date_value = Calendar.Date.from_civil_day(Gregorian, CivilDay.from_day_number(day)) ?? crash "NanoLocalDateTime: I64 nanoseconds fit the Gregorian provider"
		clock_value = NanoClockTime.from_nanoseconds_since_midnight(remainder) ?? crash "NanoLocalDateTime: remainder fits a nominal day"
		new({ date: date_value, clock: clock_value })
	}

	## Encode a Gregorian civil label with checked I64 range.
	to_gregorian_local_nanoseconds : NanoLocalDateTime -> Try(I64, [UnsupportedCalendar(Calendar), OutOfRange])
	to_gregorian_local_nanoseconds = |value| {
		gregorian = value.date.as_gregorian()?
		day = gregorian.to_civil_day().to_day_number().to_i128()
		(day * day_nanoseconds.to_i128() + value.clock.to_nanoseconds_since_midnight().to_i128()).to_i64_try()
	}

	## Exactly extend a microsecond civil label.
	from_local : LocalDateTime -> NanoLocalDateTime
	from_local = |value| new({ date: value.date(), clock: NanoClockTime.from_clock(value.clock()) })

	## Reject fractional microseconds.
	to_local : NanoLocalDateTime -> Try(LocalDateTime, [Submicrosecond, OutOfRange])
	to_local = |value| value.to_local_with_rounding(RejectSubmicrosecond)

	## Round the nonnegative clock count since nominal midnight. TowardZero
	## is equivalent to Floor for civil labels, including dates before 1970.
	## Carry a rounded midnight to the next date in the retained calendar.
	to_local_with_rounding : NanoLocalDateTime, MicrosecondRounding -> Try(LocalDateTime, [Submicrosecond, OutOfRange])
	to_local_with_rounding = |value, rounding| match value.clock.to_clock_with_rounding(rounding) {
		Ok(clock_value) => Ok(LocalDateTime.new({ date: value.date, clock: clock_value }))
		Err(Submicrosecond) => Err(Submicrosecond)
		Err(OutOfRange) => {
			next = CivilDay.from_day_number(value.date.to_civil_day().to_day_number() + 1)
			tomorrow = Calendar.Date.from_civil_day(value.date.calendar(), next)?
			midnight = ClockTime.from_microseconds_since_midnight(0)?
			Ok(LocalDateTime.new({ date: tomorrow, clock: midnight }))
		}
	}

	## A negative count immediately before the epoch remains an unresolved civil label.
	expect from_gregorian_local_nanoseconds(-1).to_gregorian_text() == Ok("1969-12-31T23:59:59.999999999")

	## The complete signed I64 carrier round-trips.
	expect [I64.lowest, -1, 0, 1, I64.highest].all(|value| from_gregorian_local_nanoseconds(value).to_gregorian_local_nanoseconds() == Ok(value))

	## Civil rounding uses midnight of the retained date as its origin.
	expect {
		label = from_gregorian_local_nanoseconds(-1)
		rounded = label.to_local_with_rounding(TowardZero)?
		rounded.to_gregorian_text() == Ok("1969-12-31T23:59:59.999999")
	}

	## On a dated label, rounded midnight carries across a year boundary.
	expect {
		value = parse_gregorian("1999-12-31T23:59:59.999999999")?
		rounded = value.to_local_with_rounding(Ceiling)?
		rounded.to_gregorian_text() == Ok("2000-01-01T00:00:00")
	}

	## Dated rounding crosses a Gregorian leap-day boundary.
	expect {
		value = parse_gregorian("2000-02-28T23:59:59.999999500")?
		rounded = value.to_local_with_rounding(NearestTiesEven)?
		rounded.to_gregorian_text() == Ok("2000-02-29T00:00:00")
	}

	## A valid Gregorian label can exceed the external I64 nanosecond encoding.
	expect {
		value = parse_gregorian("2263-01-01T00:00:00")?
		value.to_gregorian_local_nanoseconds() == Err(OutOfRange)
	}

	## A midnight carry at the provider's last Gregorian date is out of range.
	expect {
		date_value = Calendar.Date.from_fields(Gregorian, { year: 2147483647, month: 12, day: 31 })?
		clock_value = NanoClockTime.parse("23:59:59.999999999")?
		new({ date: date_value, clock: clock_value }).to_local_with_rounding(Ceiling) == Err(OutOfRange)
	}

}

day_nanoseconds = 86400000000000.I64
