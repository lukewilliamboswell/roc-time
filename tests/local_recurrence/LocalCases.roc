import time.ICalPeriod
import time.ICalTimedRule
import time.ICalDateTime
import time.TimedSchedule
import time.TimedOccurrence
import time.TimedRecurrence
import time.PosixBoundary
import time.PosixSpan
import time.PosixDelta
import time.LocalDateTime
import time.ClockTime
import time.FixedOffset
import time.ZoneRules

# R07/R09/R11/R12: finite integer-minute reference model. The synthetic
# transition occurs at 02:00Z on 1970-01-01. Enumeration and interpretation
# below do not call the package candidate or classification engines.
LocalCases := [].{
	Input : { shift : I64, position : I64, termination : U8, exclusion : U8 }
	Observation : { minute : I64, boundary : I64, end : I64, ending : U8, adjusted : Bool, end_adjusted : Bool }

	verify_all = |_| {
		var $count = 0.U64
		for shift in [-60.I64, -30, 30, 60] {
			for position in [-1.I64, 0, 1] {
				for termination in [0.U8, 1, 2] {
					for exclusion in [0.U8, 1, 2] {
						input = { shift, position, termination, exclusion }
						check(input)
						$count = $count + 1
					}
				}
			}
		}
		Ok($count)
	}

	# Reviewable transport emitted by either the independent model generator
	# or the actual native fixture. Actual execution never reads expectations.
	snapshot = |independent| {
		var $lines = []
		for shift in [-60.I64, -30, 30, 60] {
			for position in [-1.I64, 0, 1] {
				for termination in [0.U8, 1, 2] {
					for exclusion in [0.U8, 1, 2] {
						input = { shift, position, termination, exclusion }
						rows = if independent {
							model(input)
						} else {
							observe(input, 0, 1)
						}
						encoded = rows.map(
							|row| "${row.minute.to_str()}:${row.boundary.to_str()}:${row.end.to_str()}:${row.ending.to_str()}:${
								if row.adjusted {
									"1"
								} else {
									"0"
								}
							}:${
								if row.end_adjusted {
									"1"
								} else {
									"0"
								}
							}",
						)
						$lines = $lines.append("${shift.to_str()}/${position.to_str()}/${termination.to_str()}/${exclusion.to_str()}\t${Str.join_with(encoded, ",")}")
					}
				}
			}
		}
		"${Str.join_with($lines, "\n")}\n"
	}

	check = |input| {
		expected = model(input)
		actual = observe(input, 0, 1)
		if validate(expected, actual) != Ok({}) {
			crash "Local schedule differs: ${Str.inspect(input)} expected ${Str.inspect(expected)} actual ${Str.inspect(actual)}"
		}
		# An overlapping later query must restrict the original series, not
		# restart COUNT or reassign identities. Preserve same source minute IDs.
		if validate(expected.keep_if(|row| row.minute >= 180), observe(input, 180, 17)) != Ok({}) {
			crash "Later local window restarted recurrence"
		}
		# Larger work chunks must agree with one-step resumptions.
		if validate(expected, observe(input, 0, 17)) != Ok({}) {
			crash "Local recurrence resumption changed output"
		}
		{}
	}
}

# Independent source-label minute table. No date arithmetic is under test here.
text : I64 -> Str
text = |minute| match minute {
	0 => "19700101T000000"
	90 => "19700101T013000"
	150 => "19700101T023000"
	180 => "19700101T030000"
	210 => "19700101T033000"
	270 => "19700101T043000"
	330 => "19700101T053000"
	1530 => "19700102T013000"
	1590 => "19700102T023000"
	1650 => "19700102T033000"
	1710 => "19700102T043000"
	2880 => "19700103T000000"
	_ => crash "source table outside model"
}

label = |minute| ICalDateTime.local_label(ICalDateTime.parse(text(minute)) ?? crash "source fixture")

# Invert each segment directly and choose the first matching boundary for a
# fold. If no segment matches, RFC's pre-gap offset retains the source label.
resolve : I64, I64 -> { boundary : I64, adjusted : Bool }
resolve = |minute, shift| {
	before = minute < 120
	after_boundary = minute - shift
	after = after_boundary >= 120
	if before {
		{ boundary: minute, adjusted: Bool.False }
	}
	else if after {
		{ boundary: after_boundary, adjusted: Bool.False }
	}
	else {
		{ boundary: minute, adjusted: Bool.True }
	}
}

model = |input| {
	per_day = if input.position == -1 {
		[270.I64]
	} else if input.position == 1 {
		[90.I64]
	} else {
		[90.I64, 150, 210, 270]
	}
	var $sources = []
	var $count = 0.U64
	for day in [0.I64, 1440] {
		for minute in per_day.map(|n| n + day) {
			selected = resolve(minute, input.shift)
			include = if input.termination == 0 {
				$count < 3
			} else if input.termination == 1 {
				minute <= 1650
			} else {
				selected.boundary <= 1650
			}
			if include {
				$sources = $sources.append(minute)
			}
			$count = $count + 1
		}
	}
	# RDATE and PERIOD add sources after RRULE termination. Source exclusion
	# removes one label; UTC exclusion removes every colliding selected start.
	var $output = []
	for minute in $sources.concat([90, 210, 330]).sort_with(
		|a, b| if a < b {
			Before
		} else if a > b {
			After
		} else {
			Same
		},
	) {
		selected = resolve(minute, input.shift)
		excluded = (input.exclusion == 1 and minute == 150) or (input.exclusion == 2 and selected.boundary == 150)
		if !excluded and !$output.any(|row| row.minute == minute) {
			# PERIOD 03:30/05:30 retains AtLocal intent; 05:30/PT2H retains
			# coordinate-duration intent, distinct from the default PT1H.
			ending = if minute == 90 {
				3.U8
			} else if minute == 210 {
				1.U8
			} else if minute == 330 {
				2.U8
			} else {
				0.U8
			}
			end = if minute == 90 {
				resolve(150, input.shift).boundary
			} else if minute == 210 {
				resolve(330, input.shift).boundary
			} else {
				selected.boundary + if minute == 330 {
					120
				} else {
					60
				}
			}
			$output = $output.append({ minute, boundary: selected.boundary, end, ending, adjusted: selected.adjusted, end_adjusted: minute == 90 and resolve(150, input.shift).adjusted })
		}
	}
	$output
}

observe = |input, start_minute, steps| {
	anchor = if input.position == -1 {
		270.I64
	} else {
		90.I64
	}
	ending = if input.termination == 0 {
		"COUNT=3"
	} else if input.termination == 1 {
		"UNTIL=19700102T033000Z"
	} else {
		"UNTIL=19700102T033000Z"
	}
	# Local UNTIL is exercised through native definition editing below because
	# the zoned RFC profile correctly requires UTC UNTIL.
	positions = if input.position == 0 {
		""
	} else {
		";BYSETPOS=${input.position.to_str()}"
	}
	exclusions = if input.exclusion == 1 {
		["19700101T023000"]
	} else if input.exclusion == 2 {
		["19700101T023000Z"]
	} else {
		[]
	}
	parsed = ICalTimedRule.parse({ start: text(anchor), rule: "FREQ=DAILY;BYHOUR=1,2,3,4;BYMINUTE=30;${ending}${positions}", mode: Zoned, duration: "PT1H", inclusions: ["19700101T033000"], exclusions, periods: ["19700101T013000/19700101T023000", "19700101T033000/19700101T053000", "19700101T053000/PT2H"] }) ?? crash "local input rejected"
	definition = ICalTimedRule.definition(parsed)
	rule_definition = TimedRecurrence.definition(definition.rule)
	rule = if input.termination == 1 {
		TimedRecurrence.from_definition({ ..rule_definition, termination: Until(label(1650)) }) ?? crash "local until rule"
	} else {
		definition.rule
	}
	# A local UNTIL is native-only under a zoned context; construct the PERIOD
	# schedule directly, avoiding a deliberately incompatible export/import.
	rules = fixture_rules(input.shift)
	var $cursor = if input.termination == 1 {
		ICalPeriod.schedule("local-corpus", rule, { start: label(start_minute), end: label(2880) }, definition.duration, definition.periods, Local(rules)) ?? crash "native local schedule"
	} else {
		ICalTimedRule.schedule("local-corpus", parsed, { start: label(start_minute), end: label(2880) }, Local(rules)) ?? crash "local schedule"
	}
	# Every zero budget must produce explicit incompleteness and preserve a
	# continuation, then successful calls resume that exact state.
	for work in [
		{ max_steps: 0.U64, max_buffered: 8.U64, max_zone_segments: 8.U64, max_zone_candidates: 2.U64 },
		{ max_steps: 17, max_buffered: 0, max_zone_segments: 8, max_zone_candidates: 2 },
		{ max_steps: 17, max_buffered: 8, max_zone_segments: 0, max_zone_candidates: 2 },
		{ max_steps: 17, max_buffered: 8, max_zone_segments: 8, max_zone_candidates: 0 },
	] {
		paused = TimedSchedule.collect($cursor, { work, max_occurrences: 1 }) ?? crash "zero budget failed"
		match paused.status {
			Complete => crash "zero budget falsely complete"
			Limited(progress) => {
				$cursor = progress.cursor
			}
		}
		if !paused.occurrences.is_empty() {
			crash "zero budget emitted output"
		}
	}
	output_pause = TimedSchedule.collect($cursor, { work: { max_steps: 17, max_buffered: 8, max_zone_segments: 17, max_zone_candidates: 2 }, max_occurrences: 0 }) ?? crash "output pause failed"
	match output_pause.status {
		Limited(progress) => {
			$cursor = progress.cursor
		}
		Complete => crash "zero output budget falsely complete"
	}
	if !output_pause.occurrences.is_empty() {
		crash "zero output budget emitted output"
	}
	var $output = []
	var $calls = 0.U64
	while $calls < 2000 {
		batch = TimedSchedule.collect($cursor, { work: { max_steps: steps, max_buffered: 8, max_zone_segments: steps, max_zone_candidates: 2 }, max_occurrences: 1 }) ?? crash "composed schedule failed"
		if batch.steps > steps or batch.zone_segments > steps or batch.occurrences.len() > 1 {
			crash "composed schedule exceeded budget"
		}
		for occurrence in batch.occurrences {
			source = TimedRecurrence.Occurrence.source(TimedOccurrence.start(occurrence))
			id = TimedOccurrence.id(occurrence)
			if id.series != "local-corpus" or id.source != source {
				crash "source identity changed"
			}
			minute = PosixBoundary.to_microseconds(FixedOffset.resolve(FixedOffset.from_seconds(0), source) ?? crash "source coordinate") // 60000000
			span = TimedOccurrence.span(occurrence)
			if I64.rem_by(PosixBoundary.to_microseconds(PosixSpan.start(span)), 60000000) != 0 or I64.rem_by(PosixBoundary.to_microseconds(PosixSpan.end(span)), 60000000) != 0 {
				crash "local fixture boundary lost minute precision"
			}
			ending_kind = match TimedOccurrence.ending(occurrence) {
				AtLocal(spec) => {
					if spec.source != label(
						if minute == 90 {
							150
						} else {
							330
						},
					) or spec.occurrence != First or spec.gap != UseOffsetBeforeGap {
						crash "lost explicit ending label"
					}
					if minute == 90 {
						3.U8
					} else {
						1.U8
					}
				}
				After(Coordinate(delta)) => {
					if PosixDelta.to_microseconds(delta) == 7200000000 {
						2.U8
					} else {
						0.U8
					}
				}
				_ => crash "lost coordinate ending intent"
			}
			adjusted = match TimedRecurrence.Occurrence.adjustment(TimedOccurrence.start(occurrence)) {
				Exact => Bool.False
				BeforeGap(_) => Bool.True
			}
			end_adjusted = match TimedOccurrence.calendar_anchor(occurrence) {
				None => Bool.False
				Some(value) => match value.choice.adjustment {
					Exact => Bool.False
					BeforeGap(_) => Bool.True
				}
			}
			$output = $output.append({ minute, boundary: PosixBoundary.to_microseconds(PosixSpan.start(span)) // 60000000, end: PosixBoundary.to_microseconds(PosixSpan.end(span)) // 60000000, ending: ending_kind, adjusted, end_adjusted })
		}
		match batch.status {
			Complete => return $output
			Limited(progress) => {
				$cursor = progress.cursor
			}
		}
		$calls = $calls + 1
	}
	crash "local schedule failed to terminate"
}

fixture_rules = |shift| {
	validity = PosixSpan.new(PosixBoundary.from_microseconds(-86400000000), PosixBoundary.from_microseconds(345600000000)) ?? crash "validity"
	ZoneRules.new_bounded(
		"Synthetic/Composed",
		"integer-minute-v1",
		validity,
		FixedOffset.from_seconds(0),
		[{ at: PosixBoundary.from_microseconds(7200000000), offset: FixedOffset.from_seconds(shift.to_i32_wrap() * 60) }],
		{
			minimum: if shift < 0 {
				shift.to_i32_wrap() * 60
			} else {
				0
			},
			maximum: if shift > 0 {
				shift.to_i32_wrap() * 60
			} else {
				0
			},
		},
	) ?? crash "rules"
}

validate = |expected, actual| if expected == actual {
	Ok({})
} else {
	Err(OracleMismatch)
}
