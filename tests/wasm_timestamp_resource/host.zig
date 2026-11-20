extern fn roc_main(input: u64) callconv(.c) i64;

var allocations: u32 = 0;

export fn probe(input: u64) i64 {
    return roc_main(input);
}

export fn allocation_attempts() u32 {
    return allocations;
}

export fn roc_alloc(_: usize, _: usize) callconv(.c) *anyopaque {
    allocations += 1;
    @trap();
}

export fn roc_realloc(_: *anyopaque, _: usize, _: usize) callconv(.c) *anyopaque {
    allocations += 1;
    @trap();
}

export fn roc_dealloc(_: *anyopaque, _: usize) callconv(.c) void {
    @trap();
}

export fn roc_crashed(_: [*]const u8, _: usize) callconv(.c) void {
    @trap();
}

export fn roc_dbg(_: [*]const u8, _: usize) callconv(.c) void {
    @trap();
}

export fn roc_expect_failed(_: [*]const u8, _: usize) callconv(.c) void {
    @trap();
}

export fn fixture_identity(input: u64) callconv(.c) u64 {
    return input;
}
