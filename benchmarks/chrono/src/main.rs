use chrono::{DateTime, Datelike, Days, FixedOffset, NaiveDate, SecondsFormat};
use std::{hint::black_box, time::Instant};
struct Input {
    text: String,
    timestamp: DateTime<FixedOffset>,
    date: NaiveDate,
    fields: (i32, u32, u32),
}
fn date_sum(d: NaiveDate) -> u64 {
    (d.year() as u64) * 10000 + u64::from(d.month()) * 100 + u64::from(d.day())
}
fn text_sum(s: &str) -> u64 {
    s.bytes().map(u64::from).sum()
}
fn run<T, F: Fn(&T) -> u64>(data: &[T], iterations: usize, operation: &F) -> u64 {
    let data = black_box(data);
    let iterations = black_box(iterations);
    let mut sum = 0;
    for i in 0..iterations {
        sum += operation(&data[i % data.len()]);
    }
    black_box(sum)
}
fn sample<T, F: Fn(&T) -> u64>(
    data: &[T],
    iterations: usize,
    warmups: usize,
    samples: usize,
    operation: F,
) {
    for _ in 0..warmups {
        black_box(run(data, iterations, &operation));
    }
    for _ in 0..samples {
        let start = Instant::now();
        let checksum = run(data, iterations, &operation);
        let nanos = start.elapsed().as_nanos();
        println!("{nanos},{checksum}");
    }
}
fn main() {
    let args: Vec<String> = std::env::args().collect();
    let mode = &args[1];
    let iterations: usize = args[2].parse().unwrap();
    let warmups: usize = args[3].parse().unwrap();
    let samples: usize = args[4].parse().unwrap();
    assert!((1..=10_000_000).contains(&iterations) && samples <= 50 && warmups <= 10);
    let data: Vec<Input> = args[5..]
        .iter()
        .map(|text| {
            let timestamp = DateTime::parse_from_rfc3339(text).unwrap();
            let date = timestamp.date_naive();
            Input {
                text: text.clone(),
                timestamp,
                date,
                fields: (date.year(), date.month(), date.day()),
            }
        })
        .collect();
    assert!(!data.is_empty());
    if mode == "verify" {
        for v in &data {
            println!(
                "{}|{}|{}",
                v.date.num_days_from_ce() - 719163,
                v.timestamp.timestamp_micros(),
                v.timestamp.to_rfc3339_opts(SecondsFormat::Micros, false)
            );
        }
        return;
    }
    // Prepare narrow input arrays outside all samples. Date kernels never load
    // an unrelated String or timestamp from the original verification records.
    let dates: Vec<_> = data.iter().map(|v| v.date).collect();
    let fields: Vec<_> = data.iter().map(|v| v.fields).collect();
    let texts: Vec<_> = data.iter().map(|v| v.text.clone()).collect();
    let timestamps: Vec<_> = data.iter().map(|v| v.timestamp).collect();
    // Dispatch outside timestamps; generic sample/run specialize each closure.
    match mode.as_str() {
        "date_control" => sample(&dates, iterations, warmups, samples, |v| date_sum(*v)),
        "date_to_day" => sample(&dates, iterations, warmups, samples, |v| {
            (i64::from(v.num_days_from_ce()) - 719163 + 1000000) as u64
        }),
        "construct" => sample(&fields, iterations, warmups, samples, |v| {
            date_sum(NaiveDate::from_ymd_opt(v.0, v.1, v.2).unwrap())
        }),
        "roundtrip" => sample(&dates, iterations, warmups, samples, |v| {
            date_sum(NaiveDate::from_num_days_from_ce_opt(v.num_days_from_ce()).unwrap())
        }),
        "add_days" => sample(&dates, iterations, warmups, samples, |v| {
            date_sum(v.checked_add_days(Days::new(17)).unwrap())
        }),
        "parse" => sample(&texts, iterations, warmups, samples, |v| {
            DateTime::parse_from_rfc3339(v)
                .unwrap()
                .timestamp_micros()
                .rem_euclid(1_000_000_007) as u64
        }),
        "resolve" => sample(&timestamps, iterations, warmups, samples, |v| {
            v.timestamp_micros().rem_euclid(1_000_000_007) as u64
        }),
        "format" => sample(&timestamps, iterations, warmups, samples, |v| {
            text_sum(&v.to_rfc3339_opts(SecondsFormat::Micros, false))
        }),
        "end_to_end" => sample(&texts, iterations, warmups, samples, |v| {
            text_sum(
                &DateTime::parse_from_rfc3339(v)
                    .unwrap()
                    .to_rfc3339_opts(SecondsFormat::Micros, false),
            )
        }),
        _ => panic!("unknown workload"),
    }
}
