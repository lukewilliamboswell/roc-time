app [main!] { pf: platform "../platform/main.roc", time: "../../package/main.roc" }
import pf.Host
import time.Persistence
import time.ResolvedBoundary
import time.ResolvedSelection
import time.PosixBoundary
import time.Coverage
import time.ZoneRules
import CivilFixture

# R07/R09/R14/R15: each offset drop adds a separate one-microsecond preimage.
# Full-I64 validity makes logical extent huge while finite table work stays small.
# Input resolution precedes measured encode/load/read scopes.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	count = U32.from_str(args.get(1) ?? "1023") ?? 1023
	boundary = (args.get(2) ?? "selection") == "boundary"
	ceiling = U64.from_str(args.get(3) ?? "2097152") ?? 2097152
	Host.assert!(count <= 1025)
	source = match CivilFixture.make(count, boundary) {
		Ok(value) => value
		Err(_) => crash "valid civil fixture"
	}
	# Retain a partially consumed cursor while resuming it. A shared buffer may
	# copy once, but must not copy its growing prefix on every visited segment.
	cursor_work = match source {
		ResolvedSelection(value) if count >= 2 and count <= 1023 => {
			cursor = match ZoneRules.selection_cursor(ResolvedSelection.rules(value), ResolvedSelection.start(value), ResolvedSelection.end(value)) {
				Ok(result) => result
				Err(_) => crash "valid cursor"
			}
			first_before = Host.allocated_bytes!({})
			first = match ZoneRules.SelectionCursor.collect(cursor, { max_segments: 2, max_members: 1024 }) {
				Ok(result) => result
				Err(_) => crash "first cursor batch"
			}
			first_after = Host.allocated_bytes!({})
			Host.assert!(first.segments == 2 and first.buffered == 2)
			retained = match first.status {
				Limited({ cursor: rest, reason: WorkLimit }) => rest
				_ => crash "bounded first batch"
			}
			resume_before = Host.allocated_bytes!({})
			resumed = match ZoneRules.SelectionCursor.collect(retained, { max_segments: 2048, max_members: 1024 }) {
				Ok(result) => result
				Err(_) => crash "resumed cursor"
			}
			resume_after = Host.allocated_bytes!({})
			Host.assert!(resumed.segments == count.to_u64() - 1)
			match resumed.status {
				Complete(coverage) => Host.assert!(coverage == ResolvedSelection.coverage(value))
				_ => Host.assert!(False)
			}
			original = match ZoneRules.SelectionCursor.collect(retained, { max_segments: 0, max_members: 1024 }) {
				Ok(result) => result
				Err(_) => crash "retained cursor"
			}
			Host.assert!(original.segments == 0 and original.buffered == 2)
			Host.assert!(
				match original.status {
					Limited({ reason: WorkLimit, .. }) => True
					_ => False
				},
			)
			Host.assert!(first_after - first_before <= ceiling and resume_after - resume_before <= ceiling and resume_after - resume_before <= 131072)
			[first_after - first_before, resume_after - resume_before]
		}
		_ => [0, 0]
	}
	before = Host.allocated_bytes!({})
	result = Persistence.new(source)
	constructed = Host.allocated_bytes!({})
	if count > 1024 or (!boundary and count >= 1024) {
		Host.assert!(result == Err(InvalidCivilSnapshot(TooLarge)) and constructed == before)
		return { bytes: "civil=rejected-before-encoding\n".to_utf8(), work: [constructed - before] }
	}
	stored = match result {
		Ok(value) => value
		Err(_) => crash "bounded civil persistence"
	}
	Host.assert!(constructed - before <= ceiling)
	text = Persistence.to_text(stored)
	encoded = Host.allocated_bytes!({})
	Host.assert!(text.count_utf8_bytes() <= 65536 and encoded - constructed <= ceiling)
	decoded = match Persistence.parse(text) {
		Ok(value) => value
		Err(_) => crash "civil replay"
	}
	loaded = Host.allocated_bytes!({})
	Host.assert!(decoded == stored and loaded - encoded <= ceiling)
	snapshot = Persistence.value(decoded)
	var $i = 0.U32
	while $i < 100000 {
		match snapshot {
			ResolvedBoundary(value) => Host.assert!(ResolvedBoundary.boundary(value) == PosixBoundary.from_microseconds(0) and ResolvedBoundary.policy(value) == First)
			ResolvedSelection(value) => Host.assert!(Coverage.member_count(ResolvedSelection.coverage(value)) == count.to_u64() + 1 and Coverage.contains(ResolvedSelection.coverage(value), PosixBoundary.from_microseconds(count.to_i64() * 1000000)) and !Coverage.contains(ResolvedSelection.coverage(value), PosixBoundary.from_microseconds(1)))
			_ => Host.assert!(False)
		}
		$i = $i + 1
	}
	queried = Host.allocated_bytes!({})
	Host.assert!(queried == loaded)
	{ bytes: "civil=restored,coverage=preserved\n".to_utf8(), work: [constructed - before, encoded - constructed, loaded - encoded, queried - loaded].concat(cursor_work) }
}
