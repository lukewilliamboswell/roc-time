import FixedOffset
import PosixBoundary
import ZoneRules

ZoneDatabaseTests :: [].{
	expect {
		rules = ZoneRules.from_database(fixture({}))?
		ZoneRules.name(rules) == "Synthetic/Canonical" and
			ZoneRules.version(rules) == "source-v1" and
				ZoneRules.offset_at(rules, PosixBoundary.from_microseconds(-1)) == Ok(FixedOffset.from_seconds(0)) and
					ZoneRules.offset_at(rules, PosixBoundary.from_microseconds(0)) == Ok(FixedOffset.from_seconds(1800)) and
						ZoneRules.provenance(rules) == DatabaseSource({ requested_name: "Synthetic/Alias", canonical_name: "Synthetic/Canonical", source_digest: "fixture-content-v1", profile: "synthetic-bounded" })
	}

	expect {
		good = fixture({})
		status({ ..good, schema: 2 }) == Err(UnsupportedSchema(2)) and
			status({ ..good, axis: "tai-seconds" }) == Err(UnsupportedAxis("tai-seconds")) and
				status({ ..good, future_handling: "last-offset-forever" }) == Err(UnsupportedFutureHandling("last-offset-forever")) and
					status({ ..good, source_digest: "" }) == Err(MissingProvenance) and
						status({ ..good, end_second: I64.highest }) == Err(OutOfRange) and
							status({ ..good, start_second: 10, end_second: -10 }) == Err(ReversedBounds) and
								status({ ..good, minimum_offset: 1 }) == Err(OffsetOutsideBounds) and
									status({ ..good, transitions: [{ second: 10, offset: 0 }] }) == Err(TransitionOutsideValidity)
	}
}

fixture : {} -> ZoneRules.Database
fixture = |_| {
	schema: 1,
	axis: "posix-seconds-1970",
	requested_name: "Synthetic/Alias",
	canonical_name: "Synthetic/Canonical",
	source_version: "source-v1",
	source_digest: "fixture-content-v1",
	profile: "synthetic-bounded",
	future_handling: "expanded-through-validity",
	start_second: -10,
	end_second: 10,
	initial_offset: 0,
	minimum_offset: 0,
	maximum_offset: 1800,
	transitions: [{ second: 0, offset: 1800 }],
}

status = |data| match ZoneRules.from_database(data) {
	Ok(_) => Ok({})
	Err(error) => Err(error)
}
