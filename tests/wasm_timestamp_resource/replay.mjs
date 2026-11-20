import {readFileSync} from "node:fs";
const bytes = readFileSync(process.argv[2]);
const module = new WebAssembly.Module(bytes);
const instance = new WebAssembly.Instance(module);
const {probe, allocation_attempts: allocationAttempts} = instance.exports;
for (const [input, expected] of [1123456n, -1000000n, -1n].entries()) {
    const value = probe(BigInt(input));
    if (value !== expected || allocationAttempts() !== 0) {
        throw new Error(`fixture ${input}: got ${value}, expected ${expected}; allocation requests ${allocationAttempts()}`);
    }
}
let trapped = false;
try {
    probe(3n);
} catch (error) {
    if (!(error instanceof WebAssembly.RuntimeError)) throw error;
    trapped = true;
}
if (!trapped || allocationAttempts() !== 1) throw new Error("allocation control must trap on its first request");
console.log("PASS wasm32 timestamp parsing: three exact coordinates, zero allocations, failing control");
