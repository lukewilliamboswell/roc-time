//! Test fixture host. Counters cover Roc allocator calls after argv construction.
//! Requested bytes are cumulative traffic, not live bytes or retained memory.
const std = @import("std");
const builtin = @import("builtin");
const abi = @import("roc_platform_abi.zig");

pub const std_options: std.Options = .{
    .allow_stack_tracing = false,
};

const HostEnv = struct {
    gpa: std.heap.DebugAllocator(.{}),
    roc_env: abi.RocEnv,
};

const ScenarioResult = extern struct {
    bytes: abi.RocListWith(u8, false),
    work: abi.RocListWith(u64, false),
};

extern fn roc_main(args: abi.RocList(abi.RocStr)) callconv(.c) ScenarioResult;

var roc_host: ?*abi.RocHost = null;
var allocation_events: u64 = 0;
var requested_bytes: u64 = 0;
var deallocation_events: u64 = 0;
var failed_expectations: bool = false;

comptime {
    if (!builtin.is_test) {
        @export(&allocationCount, .{ .name = "fixture_allocation_count" });
        @export(&allocatedBytes, .{ .name = "fixture_allocated_bytes" });
        @export(&deallocationCount, .{ .name = "fixture_deallocation_count" });
        @export(&assertion, .{ .name = "fixture_assert" });
        @export(&mark, .{ .name = "fixture_mark" });
        @export(&main, .{ .name = "main" });
        @export(&hostAlloc, .{ .name = "roc_alloc", .visibility = .hidden });
        @export(&hostDealloc, .{ .name = "roc_dealloc", .visibility = .hidden });
        @export(&hostRealloc, .{ .name = "roc_realloc", .visibility = .hidden });
        @export(&hostDbg, .{ .name = "roc_dbg", .visibility = .hidden });
        @export(&hostExpectFailed, .{ .name = "roc_expect_failed", .visibility = .hidden });
        @export(&hostCrashed, .{ .name = "roc_crashed", .visibility = .hidden });
    }
}

fn main(argc: c_int, argv: [*][*:0]u8) callconv(.c) c_int {
    return platformMain(@intCast(argc), argv);
}

fn hostAlloc(length: usize, alignment: usize) callconv(.c) ?*anyopaque {
    allocation_events += 1;
    requested_bytes += length;
    return abi.DefaultAllocators.rocAlloc(roc_host.?, length, alignment);
}

fn hostDealloc(ptr: *anyopaque, alignment: usize) callconv(.c) void {
    deallocation_events += 1;
    abi.DefaultAllocators.rocDealloc(roc_host.?, ptr, alignment);
}

fn hostRealloc(ptr: *anyopaque, new_length: usize, alignment: usize) callconv(.c) ?*anyopaque {
    allocation_events += 1;
    requested_bytes += new_length;
    return abi.DefaultAllocators.rocRealloc(roc_host.?, ptr, new_length, alignment);
}

fn hostDbg(bytes: [*]const u8, len: usize) callconv(.c) void {
    abi.DefaultHandlers.rocDbg(roc_host.?, bytes, len);
}

fn hostExpectFailed(bytes: [*]const u8, len: usize) callconv(.c) void {
    failed_expectations = true;
    abi.DefaultHandlers.rocExpectFailed(roc_host.?, bytes, len);
}

fn hostCrashed(bytes: [*]const u8, len: usize) callconv(.c) void {
    abi.DefaultHandlers.rocCrashed(roc_host.?, bytes, len);
}

fn platformMain(argc: usize, argv: [*][*:0]u8) c_int {
    const io = std.Io.Threaded.global_single_threaded.io();
    var host_env = HostEnv{
        .gpa = std.heap.DebugAllocator(.{}){},
        .roc_env = undefined,
    };
    host_env.roc_env = .{
        .allocator = host_env.gpa.allocator(),
        .roc_io = abi.RocIo.default(),
    };

    var host = abi.makeRocHost(&host_env.roc_env);
    roc_host = &host;

    const args = buildStrArgsList(argc, argv, &host);
    allocation_events = 0;
    requested_bytes = 0;
    deallocation_events = 0;

    var result = roc_main(args);
    std.Io.File.stdout().writeStreamingAll(io, result.bytes.items()) catch return 1;
    reportMetrics(io, result.work.items()) catch return 1;
    result.bytes.decref(&host);
    result.work.decref(&host);

    if (host_env.gpa.deinit() == .leak) {
        std.Io.File.stderr().writeStreamingAll(io, "ROC_HOST_LEAK\n") catch {};
        return 1;
    }

    return if (failed_expectations) 1 else 0;
}

fn reportMetrics(io: std.Io, work: []const u64) !void {
    const stderr = std.Io.File.stderr();
    var buffer: [64]u8 = undefined;
    const allocations = try std.fmt.bufPrint(&buffer, "{d}", .{allocation_events});
    try stderr.writeStreamingAll(io, "ROC_METRICS protocol=1 allocations=");
    try stderr.writeStreamingAll(io, allocations);
    const traffic = try std.fmt.bufPrint(&buffer, " requested_bytes={d}", .{requested_bytes});
    try stderr.writeStreamingAll(io, traffic);
    const frees = try std.fmt.bufPrint(&buffer, " deallocations={d}", .{deallocation_events});
    try stderr.writeStreamingAll(io, frees);
    try stderr.writeStreamingAll(io, " work=");
    for (work, 0..) |value, index| {
        if (index != 0) try stderr.writeStreamingAll(io, ",");
        const formatted = try std.fmt.bufPrint(&buffer, "{d}", .{value});
        try stderr.writeStreamingAll(io, formatted);
    }
    try stderr.writeStreamingAll(io, "\n");
}

fn buildStrArgsList(
    argc: usize,
    argv: [*][*:0]u8,
    host: *abi.RocHost,
) abi.RocList(abi.RocStr) {
    if (argc == 0) return abi.RocList(abi.RocStr).empty();

    const args = abi.RocList(abi.RocStr).allocate(argc, host);
    const values = args.elements_ptr.?;
    for (0..argc) |index| {
        const value = argv[index];
        const length = std.mem.len(value);
        values[index] = abi.RocStr.fromSlice(value[0..length], host);
    }
    return args;
}

fn allocationCount() callconv(.c) u64 {
    return allocation_events;
}
fn allocatedBytes() callconv(.c) u64 {
    return requested_bytes;
}
fn deallocationCount() callconv(.c) u64 {
    return deallocation_events;
}
// Exported symbol is also a convenient debugger/profiler breakpoint. Marker
// emission uses a stack buffer and does not call the Roc allocator.
fn mark(id: u64) callconv(.c) void {
    var buffer: [160]u8 = undefined;
    const line = std.fmt.bufPrint(&buffer, "ROC_TRACE protocol=1 mark={d} allocations={d}\n", .{ id, allocation_events }) catch unreachable;
    std.Io.File.stderr().writeStreamingAll(std.Io.Threaded.global_single_threaded.io(), line) catch std.process.exit(1);
}

fn assertion(passed: bool) callconv(.c) void {
    if (!passed) {
        failed_expectations = true;
        std.Io.File.stderr().writeStreamingAll(std.Io.Threaded.global_single_threaded.io(), "ROC_ASSERT_FAILED\n") catch std.process.exit(1);
    }
}
