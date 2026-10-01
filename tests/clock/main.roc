app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.2/9weENCAXVZV14WFpwHqP3rpn46EDJWQQknSLpa1Hg5nL.tar.zst",
	time: "../../package/main.roc",
}

import fuzz.Fuzz
import ClockCase

target = Fuzz.target({ name: "clock-v1", test: ClockCase.check, show: |input| Str.inspect(input) })
