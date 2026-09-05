app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.3.0/FTcKnkDxL1ZXfKsxeLmNKZ6XKnuKDd47Gv79ThxLYSfw.tar.zst",
	time: "../../package/main.roc",
}

import fuzz.Fuzz
import ClockCase

target = Fuzz.target({ name: "clock-v1", test: ClockCase.check, show: |input| Str.inspect(input) })
