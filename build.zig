const std = @import("std");
const Build = std.Build;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const test_filters = b.option([]const []const u8, "test-filter", "Filters to use for executed tests");

    const test_step = b.step("test", "Run all test steps");
    const unit_test_step = b.step("test-unit", "Run unit tests");
    test_step.dependOn(unit_test_step);

    const bincode = b.addModule("bincode", .{
        .root_source_file = b.path("src/bincode.zig"),
    });
    _ = bincode;

    const unit_test_exe = b.addTest(.{
        .root_source_file = b.path("src/bincode.zig"),
        .target = target,
        .optimize = optimize,
        .filters = test_filters orelse &.{},
    });
    const unit_test_run = b.addRunArtifact(unit_test_exe);
    unit_test_step.dependOn(&unit_test_run.step);
}
