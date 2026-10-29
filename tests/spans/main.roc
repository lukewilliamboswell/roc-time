app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.5.0/9WT86CuwM7ZJBSs8iTd1jLyrUFTTiGp5hcJE63TwswGE.tar.zst",
	time: "../../package/main.roc",
}

import fuzz.Fuzz
import SpanCase

# Generated inputs exercise the invariant; these named cases pin its boundaries.
target = Fuzz.target({
	name: "spans-v1",
	examples: [
		Fuzz.example({
			name: "relation-after",
			revision: "1",
			make: || SpanCase.{
				a: 0,
				b: 3,
				c: -2,
				d: -1,
			},
		}),
		Fuzz.example({
			name: "relation-before",
			revision: "1",
			make: || SpanCase.{
				a: 0,
				b: 3,
				c: 4,
				d: 5,
			},
		}),
		Fuzz.example({
			name: "relation-contains",
			revision: "1",
			make: || SpanCase.{
				a: 0,
				b: 3,
				c: 1,
				d: 2,
			},
		}),
		Fuzz.example({
			name: "relation-during",
			revision: "1",
			make: || SpanCase.{
				a: 0,
				b: 3,
				c: -1,
				d: 4,
			},
		}),
		Fuzz.example({
			name: "relation-equal",
			revision: "1",
			make: || SpanCase.{
				a: 0,
				b: 3,
				c: 0,
				d: 3,
			},
		}),
		Fuzz.example({
			name: "relation-finished_by",
			revision: "1",
			make: || SpanCase.{
				a: 0,
				b: 3,
				c: 1,
				d: 3,
			},
		}),
		Fuzz.example({
			name: "relation-finishes",
			revision: "1",
			make: || SpanCase.{
				a: 0,
				b: 3,
				c: -1,
				d: 3,
			},
		}),
		Fuzz.example({
			name: "relation-meets",
			revision: "1",
			make: || SpanCase.{
				a: 0,
				b: 3,
				c: 3,
				d: 4,
			},
		}),
		Fuzz.example({
			name: "relation-met_by",
			revision: "1",
			make: || SpanCase.{
				a: 0,
				b: 3,
				c: -1,
				d: 0,
			},
		}),
		Fuzz.example({
			name: "relation-overlapped_by",
			revision: "1",
			make: || SpanCase.{
				a: 0,
				b: 3,
				c: -1,
				d: 2,
			},
		}),
		Fuzz.example({
			name: "relation-overlaps",
			revision: "1",
			make: || SpanCase.{
				a: 0,
				b: 3,
				c: 2,
				d: 4,
			},
		}),
		Fuzz.example({
			name: "relation-started_by",
			revision: "1",
			make: || SpanCase.{
				a: 0,
				b: 3,
				c: 0,
				d: 2,
			},
		}),
		Fuzz.example({
			name: "relation-starts",
			revision: "1",
			make: || SpanCase.{
				a: 0,
				b: 3,
				c: 0,
				d: 4,
			},
		}),
		Fuzz.example({
			name: "signed-limits",
			revision: "1",
			make: || SpanCase.{
				a: I64.lowest,
				b: I64.highest,
				c: -1,
				d: 1,
			},
		}),
		Fuzz.example({
			name: "malformed-bounds",
			revision: "1",
			make: || SpanCase.{
				a: 1,
				b: 0,
				c: 0,
				d: 0,
			},
		}),
	],
	test: SpanCase.check,
	show: Str.inspect,
})
