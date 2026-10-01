app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.2/9weENCAXVZV14WFpwHqP3rpn46EDJWQQknSLpa1Hg5nL.tar.zst",
}

import fuzz.Fuzz
import LifecycleCheck

target = Fuzz.target_with({ name: "lifecycle-intentional-failure-v1", generator: Fuzz.raw_bytes, test: LifecycleCheck.check, show: |bytes| Str.inspect(bytes) })
