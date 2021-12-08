const std = @import("std");
const assert = std.debug.assert;
const fs = std.fs;
const mem = std.mem;
const zbs = std.build;

const ScanProtocolsStep = @import("deps/zig-wayland/build.zig").ScanProtocolsStep;

/// While a wmoon release is in development, this string should contain the version in development
/// with the "-dev" suffix.
/// When a release is tagged, the "-dev" suffix should be removed for the commit that gets tagged.
/// Directly after the tagged commit, the version should be bumped and the "-dev" suffix added.
const version = "0.0.1-dev";

pub fn build(b: *zbs.Builder) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const xwayland = b.option(
        bool,
        "xwayland",
        "Set to false to disable xwayland support",
    ) orelse true;

    // Obtain full version name
    const full_version = blk: {
        if (mem.endsWith(u8, version, "-dev")) {
            var ret: u8 = undefined;
            const git_dir = try fs.path.join(b.allocator, &[_][]const u8{ b.build_root, ".git" });
            const git_commit_hash = b.execAllowFail(
                &[_][]const u8{ "git", "--git-dir", git_dir, "--work-tree", b.build_root, "rev-parse", "--short", "HEAD" },
                &ret,
                .Inherit,
            ) catch break :blk version;
            break :blk try std.fmt.allocPrintZ(b.allocator, "{s}-{s}", .{
                version,
                mem.trim(u8, git_commit_hash, &std.ascii.spaces),
            });
        } else {
            break :blk version;
        }
    };

    // Create scanner to generate code files based on Wayland protocols
    const scanner = ScanProtocolsStep.create(b);
    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.addSystemProtocol("unstable/pointer-gestures/pointer-gestures-unstable-v1.xml");
    scanner.addSystemProtocol("unstable/xdg-output/xdg-output-unstable-v1.xml");
    scanner.addSystemProtocol("unstable/pointer-constraints/pointer-constraints-unstable-v1.xml");
    scanner.addProtocolPath("protocol/river-status-unstable-v1.xml");
    scanner.addProtocolPath("protocol/river-layout-v3.xml");
    scanner.addProtocolPath("protocol/wlr-layer-shell-unstable-v1.xml");
    scanner.addProtocolPath("protocol/wlr-output-power-management-unstable-v1.xml");

    // Main executable build
    const wmoon_build = b.addExecutable("wmoon", "src/main.zig");
    wmoon_build.setTarget(target);
    wmoon_build.setBuildMode(mode);
    wmoon_build.addBuildOption(bool, "xwayland", xwayland);
    wmoon_build.addBuildOption([:0]const u8, "version", full_version);
    addServerDeps(wmoon_build, scanner);
    wmoon_build.install();

    // Run main executable
    const wmoon_run = wmoon_build.run();
    wmoon_run.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        wmoon_run.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&wmoon_run.step);

    // Test step
    const wmoon_test = b.addTest("src/test_main.zig");
    wmoon_test.setTarget(target);
    wmoon_test.setBuildMode(mode);
    wmoon_test.addBuildOption(bool, "xwayland", xwayland);
    addServerDeps(wmoon_test, scanner);
    const test_step = b.step("test", "Run the tests");
    test_step.dependOn(&wmoon_test.step);
}

fn addServerDeps(exe: *zbs.LibExeObjStep, scanner: *ScanProtocolsStep) void {
    const wayland = scanner.getPkg();
    const xkbcommon = zbs.Pkg{ .name = "xkbcommon", .path = "deps/zig-xkbcommon/src/xkbcommon.zig" };
    const pixman = zbs.Pkg{ .name = "pixman", .path = "deps/zig-pixman/pixman.zig" };
    const wlroots = zbs.Pkg{
        .name = "wlroots",
        .path = "deps/zig-wlroots/src/wlroots.zig",
        .dependencies = &[_]zbs.Pkg{ wayland, xkbcommon, pixman },
    };

    exe.step.dependOn(&scanner.step);

    exe.linkLibC();
    exe.linkSystemLibrary("libevdev");
    exe.linkSystemLibrary("libinput");

    exe.addPackage(wayland);
    exe.linkSystemLibrary("wayland-server");

    exe.addPackage(xkbcommon);
    exe.linkSystemLibrary("xkbcommon");

    exe.addPackage(pixman);
    exe.linkSystemLibrary("pixman-1");

    exe.addPackage(wlroots);
    exe.linkSystemLibrary("wlroots");

    exe.addPackagePath("flags", "flags.zig");
    exe.addCSourceFile("src/wlroots_log_wrapper.c", &[_][]const u8{ "-std=c99", "-O2" });

    // TODO: remove when zig issue #131 is implemented
    scanner.addCSource(exe);
}
