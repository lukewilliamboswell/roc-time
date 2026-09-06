const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const benchmark_allocator = b.option(bool, "benchmark-allocator", "Use libc allocation for isolated comparison benchmarks") orelse false;
    const options = b.addOptions();
    options.addOption(bool, "benchmark_allocator", benchmark_allocator);
    const host = b.addLibrary(.{
        .name = "host",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("host.zig"),
            .target = target,
            .optimize = optimize,
            .strip = false,
            .pic = true,
            .link_libc = benchmark_allocator,
        }),
    });
    host.root_module.addOptions("fixture_options", options);
    host.bundle_compiler_rt = true;
    b.installArtifact(host);
}
