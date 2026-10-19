import zones.Database
import time.ZoneRules
import time.PosixBoundary
import time.FixedOffset
import time.LocalDateTime
import time.OffsetTimestamp
import time.PosixDelta

ProviderCase :: [].{
	verify = |unknown| {
		alias = Database.get("Australia/Victoria")?
		if alias.requested_name != "Australia/Victoria" or alias.canonical_name != "Australia/Melbourne" {
			return Err(WrongAlias)
		}
		# Empty, prefix, suffix, case and non-ASCII misses exercise name ordering.
		for missing in [unknown, "", "A", "Zulu-extra", "Etc/UT", "Etc/UTCx", "australia/melbourne", "é"] {
			match Database.get(missing) {
				Err(UnknownZone(name)) => {
					if name != missing {
						return Err(WrongUnknownName)
					}
				}
				_ => return Err(MissingUnknownZoneError)
			}
		}
		rules = ZoneRules.from_database(alias)?
		for outside in [
			PosixBoundary.from_microseconds(alias.start_second * 1000000 - 1),
			PosixBoundary.from_microseconds(alias.end_second * 1000000),
		] {
			match ZoneRules.offset_at(rules, outside) {
				Err(OutsideValidity) => {}
				_ => return Err(MissingHorizonError)
			}
		}
		# 2050-01-01 is beyond Melbourne's final explicit TZif transition.
		future = PosixBoundary.from_microseconds(2524608000000000)
		offset = ZoneRules.offset_at(rules, future)?
		if FixedOffset.to_seconds(offset) != 39600 {
			return Err(WrongFutureOffset)
		}
		changed_rules()?
		Ok({})
	}

	parse_local = |text| match LocalDateTime.parse_gregorian(text) {
		Ok(value) => Ok(value)
		Err(error) => Err(FixtureLocal(error))
	}

	parse_boundary = |text| match OffsetTimestamp.parse(text) {
		Ok(value) => OffsetTimestamp.boundary(value)
		Err(error) => Err(FixtureTimestamp(error))
	}

	# Expected values are transcribed from pinned IANA source rules, not this pack.
	# See README.md for derivations, release review, and the oracle's limits.
	changed_rules = || {
		for fixture in [
			{ zone: "America/Winnipeg", at: "2026-03-08T08:00:00Z", before: -21600, after: -18000 },
			{ zone: "Canada/Central", at: "2026-11-01T07:00:00Z", before: -18000, after: -18000 },
			{ zone: "America/Winnipeg", at: "2050-01-01T00:00:00Z", before: -18000, after: -18000 },
			{ zone: "America/Edmonton", at: "2026-11-01T08:00:00Z", before: -21600, after: -21600 },
			{ zone: "America/Inuvik", at: "2026-11-01T08:00:00Z", before: -21600, after: -21600 },
			{ zone: "America/Vancouver", at: "2026-11-01T09:00:00Z", before: -25200, after: -25200 },
			{ zone: "Africa/Casablanca", at: "2026-09-20T01:00:00Z", before: 3600, after: 0 },
			{ zone: "Africa/El_Aaiun", at: "2026-09-20T01:00:00Z", before: 3600, after: 0 },
			{ zone: "Europe/Chisinau", at: "2022-03-27T01:00:00Z", before: 7200, after: 10800 },
			{ zone: "Europe/Chisinau", at: "2022-10-30T01:00:00Z", before: 10800, after: 7200 },
			{ zone: "America/Tijuana", at: "1953-04-26T09:00:00Z", before: -28800, after: -25200 },
			{ zone: "America/Bogota", at: "1992-05-02T05:00:00Z", before: -18000, after: -14400 },
			{ zone: "Asia/Tehran", at: "1979-05-25T20:30:00Z", before: 12600, after: 16200 },
			{ zone: "Europe/Dublin", at: "1925-09-20T02:00:00Z", before: 3600, after: 0 },
			{ zone: "CST6CDT", at: "1900-01-01T00:00:00Z", before: -21600, after: -21600 },
			{ zone: "EST5EDT", at: "1900-01-01T00:00:00Z", before: -18000, after: -18000 },
			{ zone: "MST7MDT", at: "1900-01-01T00:00:00Z", before: -25200, after: -25200 },
			{ zone: "PST8PDT", at: "1900-01-01T00:00:00Z", before: -28800, after: -28800 },
			{ zone: "EST5EDT", at: "1960-07-01T00:00:00Z", before: -18000, after: -18000 },
			{ zone: "Asia/Tbilisi", at: "1997-03-29T19:00:00Z", before: 18000, after: 18000 },
		] {
			data = Database.get(fixture.zone)?
			if !fixture.zone.contains("/") and data.canonical_name != fixture.zone {
				return Err(WrongPosixIdentity(fixture.zone))
			}
			rules = ZoneRules.from_database(data)?
			stamp = match OffsetTimestamp.parse(fixture.at) {
				Ok(value) => value
				Err(error) => return Err(FixtureTimestamp(error))
			}
			at = OffsetTimestamp.boundary(stamp)?
			prior = PosixBoundary.shift(at, PosixDelta.from_microseconds(-1))?
			before = FixedOffset.to_seconds(ZoneRules.offset_at(rules, prior)?)
			after = FixedOffset.to_seconds(ZoneRules.offset_at(rules, at)?)
			if before != fixture.before or after != fixture.after {
				return Err(ChangedRuleOffset(fixture.zone, fixture.at, before, after))
			}
		}
		for name in ["America/Winnipeg", "Canada/Central"] {
			data = Database.get(name)?
			if data.canonical_name != "America/Winnipeg" or data.source_version != "2026e" {
				return Err(WrongWinnipegIdentity)
			}
			rules = ZoneRules.from_database(data)?
			local = parse_local("2026-11-02T09:00")?
			actual = ZoneRules.resolve_occurrence(rules, local, RequireUnique)?
			expected = parse_boundary("2026-11-02T14:00:00Z")?
			if actual != expected {
				return Err(WrongWinnipegAppointment)
			}
		}
		Ok({})
	}
}
