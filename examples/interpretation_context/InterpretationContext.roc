import time.Ixdtf
import time.OffsetTimestamp
import time.PosixBoundary
import time.FixedOffset
import time.ZoneRules

## Compare an imported recording under two explicit interpretation contexts.
## These deliberately synthetic tables share labels but differ in actual rules.
## Their provenance labels identify this example's fixtures, not real zone data.
InterpretationContext :: [].{
	review = |inputs| {
		source = (match Ixdtf.parse(inputs.source) {
			Ok(result) => Ok(result)
			Err(error) => Err(Source(error))
		})?
		first_second = whole_second(inputs.valid_from)?
		last_second = whole_second(inputs.valid_until)?
		original_rules = fixture(first_second, last_second, 3600, "synthetic-original")?
		updated_rules = fixture(first_second, last_second, 7200, "synthetic-updated")?
		original = (match Ixdtf.resolve(source, Some(original_rules)) {
			Ok(result) => Ok(result)
			Err(error) => Err(Resolution(error))
		})?
		# The in-memory snapshot retains its immutable context. The standard
		# declaration alone would require explicit rules again after loading.
		retained = original
		reinterpreted = (match Ixdtf.Snapshot.reresolve(retained, Some(updated_rules)) {
			Ok(result) => Ok(result)
			Err(error) => Err(Reinterpretation(error))
		})?
		presentation = match Ixdtf.Snapshot.presentation(retained) {
			Ok(_) => "Gregorian presentation is available"
			Err(UnsupportedCalendar(calendar)) => "Preferred calendar ${calendar} is retained; presentation is unsupported"
		}
		original_description = describe(original)?
		retained_description = describe(retained)?
		updated_description = describe(reinterpreted)?
		Ok(
			Str.join_with(
				[
					"Recording interpretation contexts",
					"Rule labels reused: ${ZoneRules.name(original_rules)} / ${ZoneRules.version(original_rules)}",
					"Original: ${original_description}",
					"Retained snapshot: ${retained_description}",
					"Explicit re-resolution: ${updated_description}",
					presentation,
				],
				"\n",
			),
		)
	}
}

whole_second = |text| {
	point = OffsetTimestamp.boundary(
		(match OffsetTimestamp.parse(text) {
			Ok(result) => Ok(result)
			Err(error) => Err(FixtureTimestamp(error))
		})?,
	)?
	micros = PosixBoundary.to_microseconds(point)
	if I64.rem_by(micros, 1000000) != 0 {
		return Err(FractionalFixtureBound)
	}
	Ok(I64.div_trunc_by(micros, 1000000))
}

fixture = |start_second, end_second, offset, digest| ZoneRules.from_database({
	schema: 1,
	axis: "posix-seconds-1970",
	requested_name: "Synthetic/ArchiveAlias",
	canonical_name: "Synthetic/Archive",
	source_version: "example-v1",
	source_digest: digest,
	profile: "synthetic-example-only",
	future_handling: "expanded-through-validity",
	start_second,
	end_second,
	initial_offset: offset,
	minimum_offset: 0,
	maximum_offset: 7200,
	transitions: [],
})

describe = |snapshot| {
	rules = match Ixdtf.Snapshot.context(snapshot) {
		Some(value) => value
		None => return Err(MissingStoredRules)
	}
	digest = match ZoneRules.provenance(rules) {
		DatabaseSource(data) => data.source_digest
		Supplied => "supplied rules"
	}
	Ok("offset ${FixedOffset.to_seconds(Ixdtf.Snapshot.offset(snapshot)).to_str()} seconds; provenance ${digest}")
}
