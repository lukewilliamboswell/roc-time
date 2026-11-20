import time.Calendar
import time.ClockTime
import time.FixedOffset
import time.LocalDateTime
import time.PosixBoundary
import time.ZoneRules
import zones.Database

## Independent CPython zoneinfo expectations from the IANA 2026e wheel pinned
## by tzdb/package/manifest.json. Resolve by trying both fold positions and
## accepting only values that project to the original local label.
ZoneWorkload := [].{
	Mode : [Load, RejectSchema, Lookup, Offset, Resolve]
	Output : [Count(U64), Seconds(I32), Resolution(ZoneRules.Resolution), OutsideValidity, UnsupportedSchema]

	prepare = |name, scenario, mode| {
		data = Database.get(name) ?? crash "named profile"
		rules = ZoneRules.from_database(data) ?? crash "pinned zone record"
		{ month, day, hour, minute, instant, offset, expected_points } = case_for(name, scenario)
		date = Calendar.Date.from_fields(Gregorian, { year: if (scenario == "outside") 1798 else 2024, month, day }) ?? crash "zone fixture date"
		clock = ClockTime.from_fields({ hour, minute, second: 0, microsecond: 0 }) ?? crash "zone fixture clock"
		local = LocalDateTime.new({ date, clock })
		point = PosixBoundary.from_microseconds(instant)
		expected : Output
		expected = match mode {
			Load | Lookup => Count(if (name == "America/New_York") 560 else 439)
			RejectSchema => UnsupportedSchema
			Offset if scenario == "outside" => OutsideValidity
			Offset => Seconds(offset)
			Resolve if scenario == "outside" => OutsideValidity
			Resolve => Resolution(
				match expected_points.map(PosixBoundary.from_microseconds) {
					[] => Gap
					[only] => Unique(only)
					points => Fold(points)
				},
			)
		}
		{ data, rules, local, point, name, expected }
	}

	run : Mode, { data : Database.Record, rules : ZoneRules, local : LocalDateTime, point : PosixBoundary, name : Str, expected : Output } -> Output
	run = |mode, fixture| match mode {
		Lookup => {
			data = Database.get(fixture.name) ?? crash "named profile"
			Count(data.transitions.len())
		}
		Load | RejectSchema => {
			input = if (mode == RejectSchema) { ..fixture.data, schema: 0 } else fixture.data
			match ZoneRules.from_database(input) {
				Ok(loaded) => Count(ZoneRules.definition(loaded).transitions.len())
				Err(UnsupportedSchema(0)) => UnsupportedSchema
				Err(_) => crash "unexpected provider admission error"
			}
		}
		Offset => match ZoneRules.offset_at(fixture.rules, fixture.point) {
			Ok(offset) => Seconds(FixedOffset.to_seconds(offset))
			Err(OutsideValidity) => OutsideValidity
		}
		Resolve => match ZoneRules.resolve(fixture.rules, fixture.local) {
			Ok(resolution) => Resolution(resolution)
			Err(OutsideValidity) => OutsideValidity
			Err(OutOfRange) => crash "fixture local coordinate"
		}
	}

	checksum : Output -> U64
	checksum = |output| match output {
		Count(count) => count + 1
		Seconds(seconds) => (seconds.to_i64() + 86400).to_u64_wrap()
		UnsupportedSchema => 2
		OutsideValidity => 3
		Resolution(Gap) => 5
		Resolution(Unique(point)) => 7 + observe(point)
		Resolution(Fold(points)) => points.fold(11, |sum, point| sum + observe(point))
	}
}

case_for = |name, scenario| match (name, scenario) {
	("America/New_York", "ordinary") => { month: 1.U8, day: 15.U8, hour: 12.U8, minute: 0.U8, instant: 1705338000000000.I64, offset: -18000.I32, expected_points: [1705338000000000.I64] }
	("America/New_York", "gap") => { month: 3, day: 10, hour: 2, minute: 30, instant: 1710055800000000, offset: -14400, expected_points: [] }
	("America/New_York", "gap-start") => { month: 3, day: 10, hour: 2, minute: 0, instant: 1710053999999999, offset: -18000, expected_points: [] }
	("America/New_York", "gap-end") => { month: 3, day: 10, hour: 3, minute: 0, instant: 1710054000000000, offset: -14400, expected_points: [1710054000000000] }
	("America/New_York", "fold") => { month: 11, day: 3, hour: 1, minute: 30, instant: 1730611800000000, offset: -14400, expected_points: [1730611800000000, 1730615400000000] }
	("America/New_York", "fold-start") => { month: 11, day: 3, hour: 1, minute: 0, instant: 1730610000000000, offset: -14400, expected_points: [1730610000000000, 1730613600000000] }
	("America/New_York", "fold-end") => { month: 11, day: 3, hour: 2, minute: 0, instant: 1730617200000000, offset: -18000, expected_points: [1730617200000000] }
	("Australia/Lord_Howe", "ordinary") => { month: 1, day: 15, hour: 12, minute: 0, instant: 1705280400000000, offset: 39600, expected_points: [1705280400000000] }
	("Australia/Lord_Howe", "gap") => { month: 10, day: 6, hour: 2, minute: 15, instant: 1728143100000000, offset: 39600, expected_points: [] }
	("Australia/Lord_Howe", "gap-start") => { month: 10, day: 6, hour: 2, minute: 0, instant: 1728142199999999, offset: 37800, expected_points: [] }
	("Australia/Lord_Howe", "gap-end") => { month: 10, day: 6, hour: 2, minute: 30, instant: 1728142200000000, offset: 39600, expected_points: [1728142200000000] }
	("Australia/Lord_Howe", "fold") => { month: 4, day: 7, hour: 1, minute: 45, instant: 1712414700000000, offset: 39600, expected_points: [1712414700000000, 1712416500000000] }
	("Australia/Lord_Howe", "fold-start") => { month: 4, day: 7, hour: 1, minute: 30, instant: 1712413800000000, offset: 39600, expected_points: [1712413800000000, 1712415600000000] }
	("Australia/Lord_Howe", "fold-end") => { month: 4, day: 7, hour: 2, minute: 0, instant: 1712417400000000, offset: 37800, expected_points: [1712417400000000] }
	(_, "outside") => { month: 1, day: 8, hour: 12, minute: 0, instant: I64.lowest, offset: 0, expected_points: [] }
	_ => crash "unknown zone workload case"
}

observe = |point| I64.mod_by(PosixBoundary.to_microseconds(point), 1000000007).to_u64_wrap()
