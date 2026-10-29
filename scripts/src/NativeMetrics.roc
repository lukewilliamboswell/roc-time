## Strict observation protocol for native fixture output. Every stderr line
## must be a trace or the final metrics record; diagnostic junk is an error.
NativeMetrics := [].{
	Trace : { mark : U64, allocations : U64 }
	Metrics : { allocations : U64, requested_bytes : U64, deallocations : U64, work : List(U64), traces : List(Trace) }
	parse : Str -> Try(Metrics, [MalformedMetrics])
	parse = |stderr| {
		if !stderr.ends_with("\n") {
			return Err(MalformedMetrics)
		}
		lines = stderr.drop_suffix("\n").split_on("\n")
		last = lines.last().map_err(|_| MalformedMetrics)?
		fields = last.split_on(" ")
		(allocations, requested_bytes, deallocations, raw_work) = match fields {
			["ROC_METRICS", "protocol=1", a, r, d, w] if w.starts_with("work=") => (number(a, "allocations=")?, number(r, "requested_bytes=")?, number(d, "deallocations=")?, w.drop_prefix("work="))
			_ => return Err(MalformedMetrics)
		}
		work = if (raw_work.is_empty()) [] else raw_work.split_on(",").map_try(|text| number(text, ""))?
		traces = lines.drop_last(1).map_try(
			|line| match line.split_on(" ") {
				["ROC_TRACE", "protocol=1", mark, count] => Ok({ mark: number(mark, "mark=")?, allocations: number(count, "allocations=")? })
				_ => Err(MalformedMetrics)
			},
		)?
		Ok({ allocations, requested_bytes, deallocations, work, traces })
	}
}

number = |text, prefix| {
	digits = text.drop_prefix(prefix)
	if !text.starts_with(prefix) or digits.is_empty() or !digits.to_utf8().all(|b| b >= '0' and b <= '9') {
		return Err(MalformedMetrics)
	}
	U64.from_str(digits).map_err(|_| MalformedMetrics)
}
expect NativeMetrics.parse("ROC_TRACE protocol=1 mark=1 allocations=2\nROC_METRICS protocol=1 allocations=3 requested_bytes=4 deallocations=5 work=6,7\n") == Ok({ allocations: 3, requested_bytes: 4, deallocations: 5, work: [6, 7], traces: [{ mark: 1, allocations: 2 }] })
expect NativeMetrics.parse("ROC_METRICS protocol=1 allocations=3 requested_bytes=4 deallocations=5 work=\n").map_ok(|metrics| metrics.work) == Ok([])
expect NativeMetrics.parse("junk\nROC_METRICS protocol=1 allocations=3 requested_bytes=4 deallocations=5 work=6\n") == Err(MalformedMetrics)
expect NativeMetrics.parse("ROC_METRICS protocol=1 allocations=3 requested_bytes=4 deallocations=5 work=6,\n") == Err(MalformedMetrics)
expect NativeMetrics.parse("ROC_METRICS protocol=1 allocations=-1 requested_bytes=4 deallocations=5 work=6\n") == Err(MalformedMetrics)
