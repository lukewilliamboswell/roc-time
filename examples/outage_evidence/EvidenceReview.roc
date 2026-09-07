import time.RfcDateTime
import time.PosixSpan
import time.IntervalEvidence

## Keep report correlation while reviewing uncertain outage membership.
EvidenceReview :: [].{
	compare = |reports, notes, probes| {
		var $spans = []
		for report in reports {
			$spans = $spans.append(PosixSpan.new(boundary(report.start)?, boundary(report.end)?)?)
		}
		paired = IntervalEvidence.paired($spans)?
		var $starts = []
		var $ends = []
		for text in notes.starts {
			$starts = $starts.append(boundary(text)?)
		}
		for text in notes.ends {
			$ends = $ends.append(boundary(text)?)
		}
		independent = IntervalEvidence.independent({ starts: $starts, ends: $ends })?
		var $results = []
		for probe in probes {
			point = boundary(probe.time)?
			$results = $results.append({ label: probe.label, paired: report_truth(IntervalEvidence.contains(paired, point)), independent: report_truth(IntervalEvidence.contains(independent, point)) })
		}
		Ok($results)
	}
}

boundary = |text| {
	timestamp = match RfcDateTime.parse(text) {
		Ok(value) => value
		Err(error) => return Err(Timestamp(error))
	}
	RfcDateTime.utc_boundary(timestamp)
}

report_truth = |truth| match truth {
	Definite => "definite"
	Possible => "possible"
	Impossible => "impossible"
}
