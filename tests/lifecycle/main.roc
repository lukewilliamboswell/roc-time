app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.3.0/FTcKnkDxL1ZXfKsxeLmNKZ6XKnuKDd47Gv79ThxLYSfw.tar.zst",
}

import fuzz.Fuzz
import LifecycleCheck

target = Fuzz.target_with({ name: "lifecycle-intentional-failure-v1", generator: Fuzz.raw_bytes, test: LifecycleCheck.check, show: |bytes| Str.inspect(bytes) })
