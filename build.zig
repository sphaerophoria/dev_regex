const std = @import("std");

fn buildKernelObject(b: *std.Build, opt: std.builtin.OptimizeMode) !void {
    var driver_query = try std.Build.parseTargetQuery(.{
        .arch_os_abi = "x86_64-freestanding-gnu",
    });
    const kernel_step = b.step("driver", "");

    // mlugg's suggestion. Apparently the linux kernel doesn't preserve sse/avx
    // registers across interrupts, so we try to disable anything that might
    // accidentally let them get used
    driver_query.cpu_features_sub = std.Target.x86.featureSet(&.{ .avx, .mmx, .sse2, .sse, .x87 });
    const driver_target = b.resolveTargetQuery(driver_query);

    const obj = b.addObject(.{
        .name = "dev_regex_impl",
        .root_source_file = b.path("src/dev_regex_interface.zig"),
        .target = driver_target,
        .optimize = opt,
        // Kernel modules don't have stable addresses at link time
        .pic = true,
    });
    obj.root_module.code_model = .kernel;
    // Kernel disables this, we should too
    obj.root_module.red_zone = false;
    // __zig_probe_stack requires compiler rt, compiler rt needs other stuff we disable
    obj.root_module.stack_check = false;

    const install = b.addInstallArtifact(obj, .{ .dest_dir = .{ .override = .bin } });

    b.getInstallStep().dependOn(&install.step);
    kernel_step.dependOn(&install.step);
}

fn buildTestApp(b: *std.Build, opt: std.builtin.OptimizeMode) !void {
    const query = try std.Build.parseTargetQuery(.{
        .arch_os_abi = "x86_64-linux-musl",
    });
    const target = b.resolveTargetQuery(query);
    const test_app = b.addExecutable(.{
        .name = "test_app",
        .target = target,
        .optimize = opt,
    });
    test_app.addCSourceFile(.{
        .file = b.path("src/test_app.c"),
    });
    test_app.addIncludePath(b.path("include"));
    test_app.linkage = .static;
    test_app.linkLibC();


    b.installArtifact(test_app);
}

pub fn buildTests(b: *std.Build, target: std.Build.ResolvedTarget) !void {
    const tests = b.step("test", "");
    const t = b.addTest(.{
        .root_source_file = b.path("src/regex.zig"),
        .target = target,
    });
    const run_tests = b.addRunArtifact(t);
    tests.dependOn(&run_tests.step);
}

pub fn build(b: *std.Build) !void {
    const opt = b.standardOptimizeOption(.{});
    const host_target = b.standardTargetOptions(.{});

    try buildKernelObject(b, opt);
    try buildTestApp(b, opt);
    try buildTests(b, host_target);
}
