import time.ZoneRules
import time.PosixBoundary
import time.PosixSpan
import time.FixedOffset
import time.Ixdtf

SnapshotFixture := [].{
	make = |count, metadata_bytes| {
		var transitions = []
		var i = 1.U32
		while i <= count {
			transitions = transitions.append({ at: PosixBoundary.from_microseconds(i.to_i64()), offset: FixedOffset.from_seconds(0) })
			i = i + 1
		}
		validity = PosixSpan.new(PosixBoundary.from_microseconds(I64.lowest), PosixBoundary.from_microseconds(I64.highest))?
		rules = ZoneRules.new_bounded("Synthetic/Archive", "v".repeat(metadata_bytes), validity, FixedOffset.from_seconds(0), transitions, { minimum: 0, maximum: 0 })?
		declaration : Ixdtf
		declaration = "1970-01-01T00:00:00Z[Synthetic/Archive][u-ca=hebrew]"
		match Ixdtf.resolve(declaration, Some(rules)) {
			Ok(value) => Ok(value)
			Err(error) => Err(Resolve(error))
		}
	}
}
