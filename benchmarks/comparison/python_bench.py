"""CPython datetime and ciso8601 adapters; integer-only timestamp observation."""
import datetime as dt
import sys
import time

library, mode, n, warmups, samples, *texts = sys.argv[1:]
n, warmups, samples = map(int, (n, warmups, samples))
assert 1 <= n <= 10_000_000 and 0 <= warmups <= 10 and 0 <= samples <= 50 and texts
parse = dt.datetime.fromisoformat
if library == 'ciso8601':
    import ciso8601
    parse = ciso8601.parse_datetime
values = [parse(s) for s in texts]
epoch = dt.datetime(1970, 1, 1, tzinfo=dt.timezone.utc)

def micros(v):
    delta = v - epoch
    return (delta.days * 86400 + delta.seconds) * 1000000 + delta.microseconds

def date_sum(v):
    return v.year * 10000 + v.month * 100 + v.day

def canonical(v):
    return v.isoformat(timespec='microseconds')

if mode == 'verify':
    for v in values:
        print(f'{v.date().toordinal() - 719163}|{micros(v)}|{canonical(v)}')
    sys.exit()

def parsed_fields(s):
    v = parse(s)
    off = v.utcoffset()
    seconds = off.days * 86400 + off.seconds
    return date_sum(v) + ((v.hour * 60 + v.minute) * 60 + v.second) * 1000000 + v.microsecond + (seconds + 86400) * 101

day_step = dt.timedelta(days=17)
operations = {
    'date_control': ([v.date() for v in values], date_sum),
    'date_to_day': ([v.date() for v in values], lambda v: v.toordinal() - 719163 + 1000000),
    'construct': ([(v.year, v.month, v.day) for v in values], lambda v: date_sum(dt.date(*v))),
    'roundtrip': ([v.date() for v in values], lambda v: date_sum(dt.date.fromordinal(v.toordinal()))),
    'add_days': ([v.date() for v in values], lambda v: date_sum(v + day_step)),
    'parse_only': (texts, parsed_fields),
    'parse': (texts, lambda v: micros(parse(v)) % 1000000007),
    'resolve': (values, lambda v: micros(v) % 1000000007),
    'format': (values, lambda v: sum(canonical(v).encode('ascii'))),
    'end_to_end': (texts, lambda v: sum(canonical(parse(v)).encode('ascii'))),
}
data, operation = operations[mode]
size = len(data)
def run():
    checksum = 0
    for i in range(n):
        checksum += operation(data[i % size])
    return checksum
for _ in range(warmups):
    run()
for _ in range(samples):
    start = time.perf_counter_ns()
    checksum = run()
    elapsed = time.perf_counter_ns() - start
    print(f'{elapsed},{checksum}')
