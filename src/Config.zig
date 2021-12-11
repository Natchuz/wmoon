const Self = @This();

const std = @import("std");

const util = @import("util.zig");

const Server = @import("Server.zig");
const Mode = @import("Mode.zig");
const AttachMode = @import("view_stack.zig").AttachMode;
const View = @import("View.zig");

pub const FocusFollowsCursorMode = enum {
    disabled,
    /// Only change focus on entering a surface
    normal,
};

pub const WarpCursorMode = enum {
    disabled,
    @"on-output-change",
};

/// Color of background in RGBA (alpha should only affect nested sessions)
background_color: [4]f32 = [_]f32{ 0.0, 0.16862745, 0.21176471, 1.0 }, // Solarized base03

/// Width of borders in pixels
border_width: u32 = 2,

/// Color of border of focused window in RGBA
border_color_focused: [4]f32 = [_]f32{ 0.57647059, 0.63137255, 0.63137255, 1.0 }, // Solarized base1

/// Color of border of unfocused window in RGBA
border_color_unfocused: [4]f32 = [_]f32{ 0.34509804, 0.43137255, 0.45882353, 1.0 }, // Solarized base01

/// Color of border of urgent window in RGBA
border_color_urgent: [4]f32 = [_]f32{ 0.86274510, 0.19607843, 0.18431373, 1.0 }, // Solarized red

/// Map of keymap mode name to mode id
mode_to_id: std.StringHashMap(usize),

/// All user-defined keymap modes, indexed by mode id
modes: std.ArrayList(Mode),

/// Sets of app_ids and titles which will be started floating
float_filter_app_ids: std.StringHashMapUnmanaged(void) = .{},
float_filter_titles: std.StringHashMapUnmanaged(void) = .{},

/// Sets of app_ids and titles which are allowed to use client side decorations
csd_filter_app_ids: std.StringHashMapUnmanaged(void) = .{},
csd_filter_titles: std.StringHashMapUnmanaged(void) = .{},

/// The selected focus_follows_cursor mode
focus_follows_cursor: FocusFollowsCursorMode = .disabled,

/// If true, the cursor warps to the center of the focused output
warp_cursor: WarpCursorMode = .disabled,

/// The default layout namespace for outputs which have never had a per-output
/// value set. Call Output.handleLayoutNamespaceChange() on setting this if
/// Output.layout_namespace is null.
default_layout_namespace: []const u8 = &[0]u8{},

/// Determines where new views will be attached to the view stack.
attach_mode: AttachMode = .top,

/// Keyboard repeat rate in characters per second
repeat_rate: u31 = 25,

/// Keyboard repeat delay in milliseconds
repeat_delay: u31 = 600,

pub fn init() !Self {
    var self = Self{
        .mode_to_id = std.StringHashMap(usize).init(util.gpa),
        .modes = std.ArrayList(Mode).init(util.gpa),
    };
    errdefer self.deinit();

    // Start with two empty modes, "normal" and "locked"
    try self.modes.ensureCapacity(2);
    {
        // Normal mode, id 0
        const owned_slice = try std.mem.dupe(util.gpa, u8, "normal");
        try self.mode_to_id.putNoClobber(owned_slice, 0);
        self.modes.appendAssumeCapacity(Mode.init());
    }
    {
        // Locked mode, id 1
        const owned_slice = try std.mem.dupe(util.gpa, u8, "locked");
        try self.mode_to_id.putNoClobber(owned_slice, 1);
        self.modes.appendAssumeCapacity(Mode.init());
    }

    return self;
}

pub fn deinit(self: *Self) void {
    {
        var it = self.mode_to_id.keyIterator();
        while (it.next()) |key| util.gpa.free(key.*);
        self.mode_to_id.deinit();
    }

    for (self.modes.items) |mode| mode.deinit();
    self.modes.deinit();

    {
        var it = self.float_filter_app_ids.keyIterator();
        while (it.next()) |key| util.gpa.free(key.*);
        self.float_filter_app_ids.deinit(util.gpa);
    }

    {
        var it = self.float_filter_titles.keyIterator();
        while (it.next()) |key| util.gpa.free(key.*);
        self.float_filter_titles.deinit(util.gpa);
    }

    {
        var it = self.csd_filter_app_ids.keyIterator();
        while (it.next()) |key| util.gpa.free(key.*);
        self.csd_filter_app_ids.deinit(util.gpa);
    }

    {
        var it = self.csd_filter_titles.keyIterator();
        while (it.next()) |key| util.gpa.free(key.*);
        self.csd_filter_titles.deinit(util.gpa);
    }

    util.gpa.free(self.default_layout_namespace);
}

pub fn shouldFloat(self: Self, view: *View) bool {
    if (view.getAppId()) |app_id| {
        if (self.float_filter_app_ids.contains(std.mem.span(app_id))) {
            return true;
        }
    }

    if (view.getTitle()) |title| {
        if (self.float_filter_titles.contains(std.mem.span(title))) {
            return true;
        }
    }

    return false;
}

pub fn csdAllowed(self: Self, view: *View) bool {
    if (view.getAppId()) |app_id| {
        if (self.csd_filter_app_ids.contains(std.mem.span(app_id))) {
            return true;
        }
    }

    if (view.getTitle()) |title| {
        if (self.csd_filter_titles.contains(std.mem.span(title))) {
            return true;
        }
    }

    return false;
}
