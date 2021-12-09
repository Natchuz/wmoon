const build_options = @import("build_options");
const std = @import("std");
const fs = std.fs;
const io = std.io;
const os = std.os;
const wlr = @import("wlroots");
const clap = @import("clap");

const c = @import("c.zig");
const util = @import("util.zig");

const Server = @import("Server.zig");

/// Message that will be displayed for help.
const usage: []const u8 =
    \\usage: wmoon [options]
    \\
    \\  -h, --help               Print this help message and exit.
    \\      --version            Print the version number and exit.
    \\  -l, -log-level <level>   Set the log level to error, warning, info, or debug.
    \\
    \\
;

/// Flags for clap, arguments parser.
const params = comptime [_]clap.Param(void){
    .{
        .names = .{ .short = 'h', .long = "help" },
    },
    .{
        .names = .{ .long = "version" },
    },
    .{
        .names = .{ .short = 'l', .long = "log-level" },
        .takes_value = .one,
    },
};

/// Global singleton to Server.
/// TODO: remove.
pub var server: Server = undefined;

pub fn main() anyerror!void {

    // Let's parse our flags.
    // Setup optional Diagnostic for error reporting.
    var diag = clap.Diagnostic{};
    var args = clap.parse(void, &params, .{ .diagnostic = &diag }) catch |err| {
        // Report useful error and exit.
        diag.report(io.getStdErr().writer(), err) catch {};
        os.exit(1);
    };
    defer args.deinit();

    // Print help if requested.
    if (args.flag("--help")) {
        try io.getStdOut().writeAll(usage);
        os.exit(0);
    }

    // Print version if requested.
    if (args.flag("--version")) {
        try io.getStdOut().writeAll(build_options.version ++ "\n");
        os.exit(0);
    }

    // Set the log level.
    if (args.option("--log-level")) |level_str| {

        // Let's convert string to enum literal.
        const level = std.meta.stringToEnum(LogLevel, std.mem.span(level_str)) orelse {

            // Bail if user specified invalid level.
            std.log.err("Invalid log level '{s}'. Use error, warning, info or debug", .{level_str});
            try io.getStdErr().writeAll(usage);
            os.exit(1);
        };

        runtime_log_level = switch (level) {
            .@"error" => .err,
            .warning => .warn,
            .info => .info,
            .debug => .debug,
        };
    }

    // Log handler for wlroots requres some special treatment,
    // use this function to set it.
    river_init_wlroots_log(switch (runtime_log_level) {
        .debug => .debug,
        .notice, .info => .info,
        .warn, .err, .crit, .alert, .emerg => .err,
    });

    // Initialize and boostrap server.
    std.log.info("Initializing server", .{});
    try server.init();
    defer server.deinit();
    try server.start();

    // Run wayland loop, blocking the execution of a program.
    std.log.info("Running server", .{});
    server.wl_server.run();
    std.log.info("Shutting down", .{});
}

fn defaultInitPath() !?[:0]const u8 {
    const path = blk: {
        if (os.getenv("XDG_CONFIG_HOME")) |xdg_config_home| {
            break :blk try fs.path.joinZ(util.gpa, &[_][]const u8{ xdg_config_home, "river/init" });
        } else if (os.getenv("HOME")) |home| {
            break :blk try fs.path.joinZ(util.gpa, &[_][]const u8{ home, ".config/river/init" });
        } else {
            return null;
        }
    };

    os.accessZ(path, os.X_OK) catch |err| {
        std.log.err("failed to run init executable {s}: {s}", .{ path, @errorName(err) });
        util.gpa.free(path);
        return null;
    };

    return path;
}

/// Tell std.log to leave all log level filtering to us.
pub const log_level: std.log.Level = .debug;

/// Set the default log level based on the build mode.
var runtime_log_level: std.log.Level = switch (std.builtin.mode) {
    .Debug => .debug,
    .ReleaseSafe, .ReleaseFast, .ReleaseSmall => .info,
};

/// River only exposes these 4 log levels to the user for simplicity
const LogLevel = enum {
    @"error",
    warning,
    info,
    debug,
};

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    if (@enumToInt(message_level) > @enumToInt(runtime_log_level)) return;

    const river_level: LogLevel = switch (message_level) {
        .emerg, .alert, .crit, .err => .@"error",
        .warn => .warning,
        .notice, .info => .info,
        .debug => .debug,
    };
    const scope_prefix = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";

    const stderr = std.io.getStdErr().writer();
    stderr.print(@tagName(river_level) ++ scope_prefix ++ format ++ "\n", args) catch {};
}

/// See wlroots_log_wrapper.c
extern fn river_init_wlroots_log(importance: wlr.log.Importance) void;
export fn river_wlroots_log_callback(importance: wlr.log.Importance, ptr: [*:0]const u8, len: usize) void {
    switch (importance) {
        .err => log(.err, .wlroots, "{s}", .{ptr[0..len]}),
        .info => log(.info, .wlroots, "{s}", .{ptr[0..len]}),
        .debug => log(.debug, .wlroots, "{s}", .{ptr[0..len]}),
        .silent, .last => unreachable,
    }
}
