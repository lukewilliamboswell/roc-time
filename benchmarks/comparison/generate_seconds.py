"""Print the whole-second comparison corpus; never refresh expectations on replay.

Uses Python datetime, independent of Roc/Rust/Go/Tempo. See README for the
upstream benchmark cases and deliberate removal of Go's nanosecond fraction.
"""
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
from benchmark_chrono import oracle

source = Path(__file__).resolve().parents[1] / 'chrono/corpus.jsonl'
texts = [json.loads(line)['text'] for line in source.read_text().splitlines()]
texts = [text[:19] + text[26:] for text in texts]
texts += ['2014-01-09T21:48:00-05:30', '2020-08-22T11:27:43-02:00']
for text in texts:
    print(json.dumps(oracle(text), sort_keys=True))
