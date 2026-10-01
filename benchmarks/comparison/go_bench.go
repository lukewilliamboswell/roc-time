package main

import (
	"fmt"
	"os"
	"strconv"
	"time"
)

const layout = "2006-01-02T15:04:05.000000-07:00"

func parse(s string) time.Time {
	v, e := time.Parse(time.RFC3339Nano, s)
	if e != nil {
		panic(e)
	}
	return v
}
func ds(v time.Time) int64 { y, m, d := v.Date(); return int64(y*10000 + int(m)*100 + d) }
func ts(s string) int64 {
	var n int64
	for i := 0; i < len(s); i++ {
		n += int64(s[i])
	}
	return n
}
func mod(n int64) int64 {
	n %= 1000000007
	if n < 0 {
		n += 1000000007
	}
	return n
}
func day(v time.Time) int64 {
	y, m, d := v.Date()
	return time.Date(y, m, d, 0, 0, 0, 0, time.UTC).Unix() / 86400
}
func main() {
	// RFC3339 may reuse Local for matching offsets. Fix it explicitly so
	// preparation and timed parsing never consult the host zone database.
	time.Local = time.UTC
	mode := os.Args[1]
	n, e := strconv.Atoi(os.Args[2])
	if e != nil {
		panic(e)
	}
	w, e := strconv.Atoi(os.Args[3])
	if e != nil {
		panic(e)
	}
	s, e := strconv.Atoi(os.Args[4])
	if e != nil {
		panic(e)
	}
	texts := os.Args[5:]
	if n < 1 || n > 10000000 || w < 0 || w > 10 || s < 0 || s > 50 || len(texts) == 0 {
		panic("bounds")
	}
	values := make([]time.Time, len(texts))
	dates := make([]time.Time, len(texts))
	type fields struct {
		y int
		m time.Month
		d int
	}
	fs := make([]fields, len(texts))
	for i, t := range texts {
		v := parse(t)
		values[i] = v
		y, m, d := v.Date()
		dates[i] = time.Date(y, m, d, 0, 0, 0, 0, time.UTC)
		fs[i] = fields{y, m, d}
	}
	if mode == "verify" {
		for _, v := range values {
			fmt.Printf("%d|%d|%s\n", day(v), v.UnixMicro(), v.Format(layout))
		}
		return
	}
	var op func(int) int64
	switch mode {
	case "date_control":
		op = func(i int) int64 { return ds(dates[i]) }
	case "date_to_day":
		op = func(i int) int64 { return day(dates[i]) + 1000000 }
	case "construct":
		op = func(i int) int64 {
			f := fs[i]
			v := time.Date(f.y, f.m, f.d, 0, 0, 0, 0, time.UTC)
			y, m, d := v.Date()
			if y != f.y || m != f.m || d != f.d {
				panic("invalid date")
			}
			return ds(v)
		}
	case "roundtrip":
		op = func(i int) int64 { return ds(time.Unix(day(dates[i])*86400, 0).UTC()) }
	case "add_days":
		op = func(i int) int64 { return ds(dates[i].AddDate(0, 0, 17)) }
	case "parse":
		op = func(i int) int64 { return mod(parse(texts[i]).UnixMicro()) }
	case "resolve":
		op = func(i int) int64 { return mod(values[i].UnixMicro()) }
	case "parse_only":
		op = func(i int) int64 {
			v := parse(texts[i])
			_, o := v.Zone()
			h, m, s := v.Clock()
			return ds(v) + int64((h*3600+m*60+s)*1000000+v.Nanosecond()/1000) + int64(o+86400)*101
		}
	case "format":
		op = func(i int) int64 { return ts(values[i].Format(layout)) }
	case "end_to_end":
		op = func(i int) int64 { return ts(parse(texts[i]).Format(layout)) }
	default:
		panic("unknown workload")
	}
	run := func() int64 {
		var sum int64
		for i := 0; i < n; i++ {
			sum += op(i % len(texts))
		}
		return sum
	}
	var observed int64
	for i := 0; i < w; i++ {
		observed = run()
	}
	for i := 0; i < s; i++ {
		start := time.Now()
		observed = run()
		elapsed := time.Since(start).Nanoseconds()
		fmt.Printf("%d,%d\n", elapsed, observed)
	}
}
