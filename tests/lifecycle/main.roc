app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.7.0/HBigHQhVZWEF2EkLxpYK35u8P6UNsAmPYxpNFTxXK1Br.tar.zst",
}

import fuzz.Fuzz

import LifecycleCheck

target = Fuzz.target_with({ examples: [], name: "lifecycle-intentional-failure-v1", generator: Fuzz.raw_bytes, test: LifecycleCheck.check, show: |bytes| Str.inspect(bytes) })
