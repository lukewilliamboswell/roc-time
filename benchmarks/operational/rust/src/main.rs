use rangemap::RangeSet;
use std::{env, hint::black_box, ops::Range, time::Instant};

type Span = Range<i64>;

#[derive(Clone, Copy, Eq, PartialEq)]
enum Mode {
    Sorted,
    Unsorted,
    RejectUnsorted,
    Union,
    Intersection,
    Difference,
    Contains,
    FoldOverlap,
    MaterializeOverlap,
}

fn mode(text: &str) -> Mode {
    match text {
        "coverage-sorted" => Mode::Sorted,
        "coverage-unsorted" => Mode::Unsorted,
        "coverage-reject-unsorted" => Mode::RejectUnsorted,
        "coverage-union" => Mode::Union,
        "coverage-intersection" => Mode::Intersection,
        "coverage-difference" => Mode::Difference,
        "coverage-contains" => Mode::Contains,
        "coverage-fold-overlap" => Mode::FoldOverlap,
        "coverage-materialize-overlap" => Mode::MaterializeOverlap,
        _ => panic!("unknown workload"),
    }
}

#[inline(never)]
fn opaque(value: u64) -> u64 {
    black_box(value)
}

#[derive(PartialEq, Eq, Debug)]
enum Output {
    Coverage(RangeSet<i64>),
    Matches(Vec<Span>),
    UnsortedInput,
    Point(bool),
    Fold { count: u64, endpoints: u64 },
}

fn semantic_output(output: Output) -> Output {
    match output {
        Output::Coverage(set) => Output::Matches(set.iter().cloned().collect()),
        other => other,
    }
}

fn observe<'a>(ranges: impl Iterator<Item = &'a Span>) -> (u64, u64) {
    ranges.fold((0, 0), |(count, endpoints), range| {
        (count + 1, endpoints + (range.start + range.end) as u64)
    })
}

fn checksum(output: Output) -> u64 {
    let (count, endpoints) = match &output {
        Output::Coverage(set) => observe(set.iter()),
        Output::Matches(ranges) => observe(ranges.iter()),
        Output::UnsortedInput => return 3,
        Output::Point(value) => return 1 + u64::from(*value),
        Output::Fold { count, endpoints } => (*count, *endpoints),
    };
    1 + count + endpoints
}

fn sorted(spans: &[Span]) -> Output {
    if spans.windows(2).any(|pair| pair[0].start > pair[1].start) {
        return Output::UnsortedInput;
    }
    Output::Coverage(spans.iter().cloned().collect())
}

struct Input {
    raw: Vec<Span>,
    reversed: Vec<Span>,
    left: RangeSet<i64>,
    right: RangeSet<i64>,
    query: Span,
}

fn run(workload: Mode, input: &Input) -> Output {
    match workload {
        Mode::Sorted => sorted(&input.raw),
        Mode::Unsorted => Output::Coverage(input.reversed.iter().cloned().collect()),
        Mode::RejectUnsorted => sorted(&input.reversed),
        Mode::Union => Output::Coverage(input.left.union(&input.right).collect()),
        Mode::Intersection => Output::Coverage(input.left.intersection(&input.right).collect()),
        Mode::Difference => {
            let mut result = input.left.clone();
            for member in input.right.iter() {
                result.remove(member.clone());
            }
            Output::Coverage(result)
        }
        Mode::Contains => Output::Point(input.left.contains(&input.query.start)),
        Mode::FoldOverlap => {
            let (count, endpoints) = observe(input.left.overlapping(&input.query));
            Output::Fold { count, endpoints }
        }
        Mode::MaterializeOverlap => {
            Output::Matches(input.left.overlapping(&input.query).cloned().collect())
        }
    }
}

// Enumerate individual positions and coalesce runs. This model shares neither
// the Roc interval algorithms nor the comparator's tree searches and algebra.
fn model(
    workload: Mode,
    count: i64,
    blocks: i64,
    width: i64,
    offset: i64,
    query: &Span,
    matches: i64,
    phase: i64,
) -> Output {
    if workload == Mode::RejectUnsorted && count >= 2 {
        return Output::UnsortedInput;
    }
    if workload == Mode::Contains {
        return Output::Point(matches > 0);
    }
    let mut intervals = Vec::new();
    let mut start = None;
    for position in 16..=16 * (blocks + 1) {
        let point = position + phase;
        let lane = position % 16;
        let within = position / 16 <= blocks;
        let left = within && lane < width;
        let right = within && (offset..offset + width).contains(&lane);
        let overlap = point - lane < query.end && point - lane + width > query.start;
        let include = match workload {
            Mode::Union => left || right,
            Mode::Intersection => left && right,
            Mode::Difference => left && !right,
            Mode::FoldOverlap | Mode::MaterializeOverlap => left && overlap,
            _ => left,
        };
        match (include, start) {
            (true, None) => start = Some(point),
            (false, Some(lower)) => {
                intervals.push(lower..point);
                start = None;
            }
            _ => {}
        }
    }
    match workload {
        Mode::FoldOverlap => {
            let (count, endpoints) = observe(intervals.iter());
            Output::Fold { count, endpoints }
        }
        _ => Output::Matches(intervals),
    }
}

fn prepare(workload: Mode, shape: &str, count: i64, matches: i64, phase: i64) -> (Input, u64) {
    let dense = shape == "dense";
    let blocks = if dense { count / 2 } else { count };
    let width = if dense { 8 } else { 4 };
    let offset = if shape == "disjoint" { 8 } else { width / 2 };
    assert!(matches!(shape, "sparse" | "dense" | "disjoint"));
    assert!(matches!(count, 0 | 8 | 4096) && matches >= 0 && matches <= blocks && matches <= 64);

    let raw: Vec<_> = (0..count)
        .map(|index| {
            let start = if dense {
                16 * (index / 2) + 4 * (index % 2) + 16
            } else {
                16 * index + 16
            };
            start + phase..start + phase + 4
        })
        .collect();
    let lo = if matches == 0 {
        16 * blocks + width
    } else {
        16 * (blocks - matches + 1)
    };
    let hi = if matches == 0 {
        lo + 1
    } else {
        16 * blocks + width
    };
    let input = Input {
        reversed: raw.iter().rev().cloned().collect(),
        left: raw.iter().cloned().collect(),
        right: raw
            .iter()
            .map(|span| span.start + offset..span.end + offset)
            .collect(),
        raw,
        query: lo + phase..hi + phase,
    };
    let expected = model(
        workload,
        count,
        blocks,
        width,
        offset,
        &input.query,
        matches,
        phase,
    );
    assert_eq!(semantic_output(run(workload, &input)), expected);

    (input, checksum(expected))
}

fn main() {
    let args: Vec<_> = env::args().collect();
    let workload = mode(&args[1]);
    let count: i64 = args[3].parse().unwrap();
    let matches: i64 = args[4].parse().unwrap();
    let iterations: u64 = args[5].parse().unwrap();
    let warmups: u64 = args[6].parse().unwrap();
    let samples: u64 = args[7].parse().unwrap();
    assert!((1..=10000).contains(&iterations) && warmups <= 10 && samples <= 50);
    let (first, first_sum) = prepare(workload, &args[2], count, matches, 0);
    let (second, second_sum) = prepare(workload, &args[2], count, matches, 1);
    let fixtures = [first, second];
    let expected_sum = (iterations / 2) * (first_sum + second_sum) + iterations % 2 * first_sum;
    let batch = || {
        (0..opaque(iterations))
            .map(|index| {
                opaque(checksum(run(
                    workload,
                    &fixtures[opaque(index % 2) as usize],
                )))
            })
            .sum::<u64>()
    };
    for _ in 0..warmups {
        assert_eq!(batch(), expected_sum);
    }
    println!("{expected_sum}");
    for _ in 0..samples {
        let start = Instant::now();
        let sum = batch();
        let elapsed = start.elapsed().as_nanos();
        assert_eq!(sum, expected_sum);
        assert!(elapsed > 0);
        println!("{elapsed},{sum}");
    }
}
