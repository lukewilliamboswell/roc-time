## Test-only observations. Calls themselves allocate no Roc memory.
## Counts start after argv construction and include output construction.
## Requested bytes count full alloc/realloc requests, not live or retained bytes.
Host := [].{
	opaque_u64! : U64 => U64

	## Monotonic nanoseconds from an unspecified epoch, for kernel timing only.
	monotonic_ns! : {} => U64

	allocation_count! : {} => U64
	allocated_bytes! : {} => U64
	deallocation_count! : {} => U64

	## Numeric marks are emitted to stderr; no formatting is done in Roc.
	mark! : U64 => {}

	## Remains active in optimized builds, where Roc expect may be removed.
	assert! : Bool => {}
}
