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
fn run(data: &[Input], mode: &str, iterations: usize) -> u64 {
    let data = black_box(data);
    let iterations = black_box(iterations);
    let mut sum = 0;
    for i in 0..iterations {
        let v = &data[i % data.len()];
        sum += match mode {
            "construct" => {
                date_sum(NaiveDate::from_ymd_opt(v.fields.0, v.fields.1, v.fields.2).unwrap())
            }
            "roundtrip" => {
                date_sum(NaiveDate::from_num_days_from_ce_opt(v.date.num_days_from_ce()).unwrap())
            }
            "add_days" => date_sum(v.date.checked_add_days(Days::new(17)).unwrap()),
            "parse" => DateTime::parse_from_rfc3339(&v.text)
                .unwrap()
                .timestamp_micros()
                .rem_euclid(1_000_000_007) as u64,
            "format" => text_sum(&v.timestamp.to_rfc3339_opts(SecondsFormat::Micros, false)),
            "end_to_end" => text_sum(
                &DateTime::parse_from_rfc3339(&v.text)
                    .unwrap()
                    .to_rfc3339_opts(SecondsFormat::Micros, false),
            ),
            _ => panic!("unknown workload"),
        };
    }
    black_box(sum)
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
    for _ in 0..warmups {
        black_box(run(&data, mode, iterations));
    }
    for _ in 0..samples {
        let start = Instant::now();
        let checksum = run(&data, mode, iterations);
        let nanos = start.elapsed().as_nanos();
        println!("{nanos},{checksum}");
    }
}
