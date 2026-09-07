app [main!] { pf: platform "../platform/main.roc", time: "../../package/main.roc" }
import pf.Host
import time.Persistence
import time.Ixdtf
import time.PosixBoundary
import SnapshotFixture

# R09/R14/R15: complete runtime rule tables, including microsecond transitions
# across full-I64 validity. Work depends on table/text size, not logical extent.
# Construction, serialization, load validation and stored reads have separate
# requested-byte counters. Source input construction is outside these scopes.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	count = U32.from_str(args.get(1) ?? "1024") ?? 1024
	metadata = U64.from_str(args.get(2) ?? "16") ?? 16
	ceiling = U64.from_str(args.get(3) ?? "8388608") ?? 8388608
	Host.assert!(count <= 16384 and metadata > 0 and metadata <= 4097)
	snapshot = match SnapshotFixture.make(count, metadata) {
		Ok(v) => v
		Err(_) => crash "valid runtime snapshot fixture"
	}
	before = Host.allocated_bytes!({})
	saved_result = Persistence.new(IxdtfSnapshot(snapshot))
	constructed = Host.allocated_bytes!({})
	if count > 1024 or metadata > 4096 {
		Host.assert!(saved_result == Err(InvalidSnapshot(TooLarge)) and constructed == before)
		return { bytes: "rejected-before-encoding\n".to_utf8(), work: [constructed - before] }
	}
	saved = match saved_result {
		Ok(v) => v
		Err(_) => crash "supported snapshot persistence fixture"
	}
	Host.assert!(constructed - before <= ceiling)
	text = Persistence.to_text(saved)
	encoded = Host.allocated_bytes!({})
	Host.assert!(text.count_utf8_bytes() <= 65536 and encoded - constructed <= ceiling)
	restored = match Persistence.parse(text) {
		Ok(v) => v
		Err(_) => crash "snapshot replay fixture"
	}
	decoded = Host.allocated_bytes!({})
	Host.assert!(decoded - encoded <= ceiling and restored == saved)
	value = match Persistence.value(restored) {
		IxdtfSnapshot(v) => v
		_ => crash "snapshot kind"
	}
	var $i = 0.U32
	while $i < 100000 {
		Host.assert!(Ixdtf.Snapshot.boundary(value) == PosixBoundary.from_microseconds(0) and Ixdtf.Snapshot.presentation(value) == Err(UnsupportedCalendar("hebrew")))
		$i = $i + 1
	}
	queried = Host.allocated_bytes!({})
	Host.assert!(queried == decoded)
	{ bytes: "snapshot=restored,reads=stored\n".to_utf8(), work: [constructed - before, encoded - constructed, decoded - encoded, queried - decoded] }
}
