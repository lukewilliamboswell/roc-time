app [main!] { pf: platform "./platform/main.roc", time: "../../package/main.roc" }
import time.OffsetTimestamp
import time.PosixBoundary

main! = |input| {
	source = match input {
		0 => "1970-01-01t05:30:01.123456+05:30"
		1 => "1969-12-31T23:59:59-00:00"
		2 => "1969-12-31T23:59:59.999999+00:00"
		_ => {
			bytes = input.to_str().to_utf8()
			return (bytes.get(0) ?? 0).to_i64()
		}
	}
	timestamp = OffsetTimestamp.parse(source) ?? crash "valid fixture"
	boundary = OffsetTimestamp.boundary(timestamp) ?? crash "boundary fixture"
	PosixBoundary.to_microseconds(boundary)
}
