import time.Persistence
import time.Ixdtf
import time.OffsetTimestamp
import time.PosixBoundary
import time.FixedOffset
import time.ZoneRules

## Archive an imported recording's interpretation for reproducible review.
## These deliberately synthetic tables share labels but differ in actual rules.
## Their provenance labels identify this example's fixtures, not real zone data.
SnapshotArchive :: [].{
	restore = |inputs| {
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
		stored = (match Persistence.new(IxdtfSnapshot(original)) {
			Ok(result) => Ok(result)
			Err(error) => Err(Archive(error))
		})?
		serialized = Persistence.to_text(stored)
		# An application's storage layer can keep this text. Decode restores the
		# original rules directly; the current table is not an input to parsing.
		restored = match Persistence.value((match Persistence.parse(serialized) {
			Ok(result) => Ok(result)
			Err(error) => Err(Restore(error))
		})?) {
			IxdtfSnapshot(snapshot) => snapshot
			_ => return Err(UnexpectedStoredKind)
		}
		reinterpreted = (match Ixdtf.Snapshot.reresolve(restored, Some(updated_rules)) {
			Ok(result) => Ok(result)
			Err(error) => Err(Reinterpretation(error))
		})?
		presentation = match Ixdtf.Snapshot.presentation(restored) {
			Ok(_) => "Gregorian presentation is available"
			Err(UnsupportedCalendar(calendar)) => "Preferred calendar ${calendar} is retained; presentation is unsupported"
		}
		saved_description = describe(original)?
		restored_description = describe(restored)?
		updated_description = describe(reinterpreted)?
		Ok(
			Str.join_with(
				[
					"Recording interpretation archive",
					"Rule labels reused: ${ZoneRules.name(original_rules)} / ${ZoneRules.version(original_rules)}",
					"Saved: ${saved_description}",
					"Restored: ${restored_description}",
					"Explicit re-resolution: ${updated_description}",
					presentation,
				],
				"\n",
			),
		)
	}
}

whole_second = |text| {
	point = OffsetTimestamp.boundary((match OffsetTimestamp.parse(text) {
		Ok(result) => Ok(result)
		Err(error) => Err(FixtureTimestamp(error))
	})?)?
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
