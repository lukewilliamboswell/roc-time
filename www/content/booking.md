# Find free booking windows

Use this workflow when an application receives timestamped bookings and needs the remaining available time. Inputs must identify their offset; a local clock label alone cannot identify a booking on a timeline.

## The pipeline

1. Parse opening and booking intervals with `ExactInterval`.
2. Obtain checked half-open spans from those values.
3. Build `Coverage` from the occupied spans.
4. Subtract occupied coverage within the opening span.
5. Format the resulting endpoints as canonical timestamps for your caller.

Read and run the [booking exchange application using released packages](https://github.com/lukewilliamboswell/roc-time/tree/main/examples/booking_exchange). The input/output root is `main.roc`; `BookingExchange.roc` contains the pure pipeline.

```sh
roc examples/booking_exchange/main.roc
```

Use the compiler and dependencies from the [getting-started guide](getting-started.html).

## Keep the gaps

An opening from 09:00 to 17:00 with a booking from 10:00 to 12:00 has two free spans. A single start/end pair cannot represent that result without accidentally including the booking.

`Coverage` normalizes overlapping and touching spans. That is useful for availability, but it deliberately loses individual booking identity. Keep your events separately when you need to answer “whose booking is this?”

## Know what can fail

An interval must have ordered, nonempty endpoints. Invalid timestamp spelling, an unsupported precision or a reversed interval returns a structured error. The package does not quietly swap endpoints or invent a timezone.

The supported timestamp profile uses microsecond precision. Finer input is rejected rather than truncated. Arithmetic near the signed coordinate limits is checked too.

## Store standard values

Use the format's checked parser and serializer for values you store. The [catalogue storage application](https://github.com/lukewilliamboswell/roc-time/tree/main/examples/catalogue_storage) stores EDTF date descriptions and RFC 3339 timestamps in application-owned fields, then parses them again. No library-specific archive wrapper is needed.

For availability, keep each separate span and serialize its endpoints. Your application owns the collection schema; standard timestamp strings alone do not define a standardized coverage document. Debug inspection is not a storage format.

For expiry checks, the [clock deadline application in the repository](https://github.com/lukewilliamboswell/roc-time/tree/main/examples/clock_deadline) declares its package and compiler in its header. Its platform root reads the clock, while a pure module compares the supplied reading with an expiry. The saved status describes its recorded check time, not the time the JSON is loaded.

## API reference

`ExactInterval` · `OffsetTimestamp` · `Coverage`
