use jiff::{
    Timestamp,
    civil::Date,
    fmt::temporal::{DateTimeParser, DateTimePrinter},
    tz::Offset,
};
use std::{hint::black_box, time::Instant};
fn ds(d: Date) -> u64 {
    d.year() as u64 * 10000 + d.month() as u64 * 100 + d.day() as u64
}
fn parse(s: &str) -> (Timestamp, Offset) {
    let p = DateTimeParser::new();
    let pieces = p.parse_pieces(s).unwrap();
    (
        p.parse_timestamp(s).unwrap(),
        pieces.to_numeric_offset().unwrap(),
    )
}
fn text(v: &(Timestamp, Offset)) -> String {
    let mut text = String::new();
    DateTimePrinter::new()
        .precision(Some(6))
        .print_timestamp_with_offset(&v.0, v.1, &mut text)
        .unwrap();
    text
}
fn sample<T, F: Fn(&T) -> u64>(data: &[T], n: usize, w: usize, s: usize, op: F) {
    let run = || {
        let data = black_box(data);
        let n = black_box(n);
        let mut sum = 0;
        for i in 0..n {
            sum += op(&data[i % data.len()]);
        }
        black_box(sum)
    };
    for _ in 0..w {
        black_box(run());
    }
    for _ in 0..s {
        let start = Instant::now();
        let sum = run();
        let elapsed = start.elapsed().as_nanos();
        println!("{elapsed},{sum}");
    }
}
fn main() {
    let a: Vec<_> = std::env::args().collect();
    let mode = &a[1];
    let n: usize = a[2].parse().unwrap();
    let w: usize = a[3].parse().unwrap();
    let s: usize = a[4].parse().unwrap();
    assert!(n > 0 && n <= 10000000 && w <= 10 && s <= 50 && a.len() > 5);
    let texts = &a[5..];
    let values: Vec<_> = texts.iter().map(|s| parse(s)).collect();
    let dates: Vec<_> = values
        .iter()
        .map(|(t, o)| o.to_datetime(*t).date())
        .collect();
    let epoch = Date::new(1970, 1, 1).unwrap();
    if mode == "verify" {
        for (v, d) in values.iter().zip(&dates) {
            println!(
                "{}|{}|{}",
                epoch.until(*d).unwrap().get_days(),
                v.0.as_microsecond(),
                text(v)
            );
        }
        return;
    }
    match mode.as_str() {
        "date_control" => sample(&dates, n, w, s, |v| ds(*v)),
        "construct" => {
            let f: Vec<_> = dates
                .iter()
                .map(|d| (d.year(), d.month(), d.day()))
                .collect();
            sample(&f, n, w, s, |v| ds(Date::new(v.0, v.1, v.2).unwrap()))
        }
        "add_days" => sample(&dates, n, w, s, |v| {
            ds(v.checked_add(jiff::Span::new().days(17)).unwrap())
        }),
        "parse" => sample(texts, n, w, s, |v| {
            DateTimeParser::new()
                .parse_timestamp(v)
                .unwrap()
                .as_microsecond()
                .rem_euclid(1000000007) as u64
        }),
        "resolve" => sample(&values, n, w, s, |v| {
            v.0.as_microsecond().rem_euclid(1000000007) as u64
        }),
        _ => panic!("unsupported workload"),
    }
}
