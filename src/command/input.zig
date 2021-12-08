// This file is part of river, a dynamic tiling wayland compositor.
//
// Copyright 2021 The River Developers
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");
const mem = std.mem;

const server = &@import("../main.zig").server;
const util = @import("../util.zig");
const c = @import("../c.zig");

const Error = @import("../command.zig").Error;
const Seat = @import("../Seat.zig");
const InputConfig = @import("../InputConfig.zig");
const InputManager = @import("../InputManager.zig");

pub fn listInputs(
    allocator: *mem.Allocator,
    seat: *Seat,
    args: []const [:0]const u8,
    out: *?[]const u8,
) Error!void {
    var input_list = std.ArrayList(u8).init(allocator);
    const writer = input_list.writer();
    var prev = false;

    var it = server.input_manager.input_devices.first;
    while (it) |node| : (it = node.next) {
        const configured = for (server.input_manager.input_configs.items) |*input_config| {
            if (mem.eql(u8, input_config.identifier, mem.sliceTo(node.data.identifier, 0))) {
                break true;
            }
        } else false;

        if (prev) try input_list.appendSlice("\n");
        prev = true;

        try writer.print("{s}\n\ttype: {s}\n\tconfigured: {s}\n", .{
            node.data.identifier,
            @tagName(node.data.device.type),
            configured,
        });
    }

    out.* = input_list.toOwnedSlice();
}

pub fn listInputConfigs(
    allocator: *mem.Allocator,
    seat: *Seat,
    args: []const [:0]const u8,
    out: *?[]const u8,
) Error!void {
    var input_list = std.ArrayList(u8).init(allocator);
    const writer = input_list.writer();

    for (server.input_manager.input_configs.items) |*input_config, i| {
        if (i > 0) try input_list.appendSlice("\n");

        try writer.print("{s}\n", .{input_config.identifier});

        if (input_config.event_state) |event_state| {
            try writer.print("\tevents: {s}\n", .{@tagName(event_state)});
        }
        if (input_config.accel_profile) |accel_profile| {
            try writer.print("\taccel-profile: {s}\n", .{@tagName(accel_profile)});
        }
        if (input_config.click_method) |click_method| {
            try writer.print("\tclick-method: {s}\n", .{@tagName(click_method)});
        }
        if (input_config.drag_state) |drag_state| {
            try writer.print("\tdrag: {s}\n", .{@tagName(drag_state)});
        }
        if (input_config.drag_lock) |drag_lock| {
            try writer.print("\tdrag-lock: {s}\n", .{@tagName(drag_lock)});
        }
        if (input_config.dwt_state) |dwt_state| {
            try writer.print("\tdisable-while-typing: {s}\n", .{@tagName(dwt_state)});
        }
        if (input_config.middle_emulation) |middle_emulation| {
            try writer.print("\tmiddle-emulation: {s}\n", .{@tagName(middle_emulation)});
        }
        if (input_config.natural_scroll) |natural_scroll| {
            try writer.print("\tnatual-scroll: {s}\n", .{@tagName(natural_scroll)});
        }
        if (input_config.left_handed) |left_handed| {
            try writer.print("\tleft-handed: {s}\n", .{@tagName(left_handed)});
        }
        if (input_config.tap_state) |tap_state| {
            try writer.print("\ttap: {s}\n", .{@tagName(tap_state)});
        }
        if (input_config.tap_button_map) |tap_button_map| {
            try writer.print("\ttap-button-map: {s}\n", .{@tagName(tap_button_map)});
        }
        if (input_config.pointer_accel) |pointer_accel| {
            try writer.print("\tpointer-accel: {d}\n", .{pointer_accel.value});
        }
        if (input_config.scroll_method) |scroll_method| {
            try writer.print("\tscroll-method: {s}\n", .{scroll_method});
        }
        if (input_config.scroll_button) |scroll_button| {
            try writer.print("\tscroll-button: {s}\n", .{
                mem.sliceTo(c.libevdev_event_code_get_name(c.EV_KEY, scroll_button.button), 0),
            });
        }
    }

    out.* = input_list.toOwnedSlice();
}

pub fn input(
    allocator: *mem.Allocator,
    seat: *Seat,
    args: []const [:0]const u8,
    out: *?[]const u8,
) Error!void {
    if (args.len < 4) return Error.NotEnoughArguments;
    if (args.len > 4) return Error.TooManyArguments;

    // Try to find an existing InputConfig with matching identifier, or create
    // a new one if none was found.
    var new = false;
    const input_config = for (server.input_manager.input_configs.items) |*input_config| {
        if (mem.eql(u8, input_config.identifier, args[1])) break input_config;
    } else blk: {
        // Use util.gpa instead of allocator to assure the identifier is
        // allocated by the same allocator as the ArrayList.
        try server.input_manager.input_configs.ensureUnusedCapacity(1);
        server.input_manager.input_configs.appendAssumeCapacity(.{
            .identifier = try util.gpa.dupe(u8, args[1]),
        });
        new = true;
        break :blk &server.input_manager.input_configs.items[server.input_manager.input_configs.items.len - 1];
    };
    errdefer {
        if (new) {
            var cfg = server.input_manager.input_configs.pop();
            cfg.deinit();
        }
    }

    if (mem.eql(u8, "events", args[2])) {
        input_config.event_state = std.meta.stringToEnum(InputConfig.EventState, args[3]) orelse
            return Error.UnknownOption;
    } else if (mem.eql(u8, "accel-profile", args[2])) {
        input_config.accel_profile = std.meta.stringToEnum(InputConfig.AccelProfile, args[3]) orelse
            return Error.UnknownOption;
    } else if (mem.eql(u8, "click-method", args[2])) {
        input_config.click_method = std.meta.stringToEnum(InputConfig.ClickMethod, args[3]) orelse
            return Error.UnknownOption;
    } else if (mem.eql(u8, "drag", args[2])) {
        input_config.drag_state = std.meta.stringToEnum(InputConfig.DragState, args[3]) orelse
            return Error.UnknownOption;
    } else if (mem.eql(u8, "drag-lock", args[2])) {
        input_config.drag_lock = std.meta.stringToEnum(InputConfig.DragLock, args[3]) orelse
            return Error.UnknownOption;
    } else if (mem.eql(u8, "disable-while-typing", args[2])) {
        input_config.dwt_state = std.meta.stringToEnum(InputConfig.DwtState, args[3]) orelse
            return Error.UnknownOption;
    } else if (mem.eql(u8, "middle-emulation", args[2])) {
        input_config.middle_emulation = std.meta.stringToEnum(InputConfig.MiddleEmulation, args[3]) orelse
            return Error.UnknownOption;
    } else if (mem.eql(u8, "natural-scroll", args[2])) {
        input_config.natural_scroll = std.meta.stringToEnum(InputConfig.NaturalScroll, args[3]) orelse
            return Error.UnknownOption;
    } else if (mem.eql(u8, "left-handed", args[2])) {
        input_config.left_handed = std.meta.stringToEnum(InputConfig.LeftHanded, args[3]) orelse
            return Error.UnknownOption;
    } else if (mem.eql(u8, "tap", args[2])) {
        input_config.tap_state = std.meta.stringToEnum(InputConfig.TapState, args[3]) orelse
            return Error.UnknownOption;
    } else if (mem.eql(u8, "tap-button-map", args[2])) {
        input_config.tap_button_map = std.meta.stringToEnum(InputConfig.TapButtonMap, args[3]) orelse
            return Error.UnknownOption;
    } else if (mem.eql(u8, "pointer-accel", args[2])) {
        input_config.pointer_accel = InputConfig.PointerAccel{
            .value = std.math.clamp(
                try std.fmt.parseFloat(f32, args[3]),
                @as(f32, -1.0),
                @as(f32, 1.0),
            ),
        };
    } else if (mem.eql(u8, "scroll-method", args[2])) {
        input_config.scroll_method = std.meta.stringToEnum(InputConfig.ScrollMethod, args[3]) orelse
            return Error.UnknownOption;
    } else if (mem.eql(u8, "scroll-button", args[2])) {
        const ret = c.libevdev_event_code_from_name(c.EV_KEY, args[3]);
        if (ret < 1) return Error.InvalidButton;
        input_config.scroll_button = InputConfig.ScrollButton{ .button = @intCast(u32, ret) };
    } else {
        return Error.UnknownCommand;
    }

    // Update matching existing input devices.
    var it = server.input_manager.input_devices.first;
    while (it) |device_node| : (it = device_node.next) {
        if (mem.eql(u8, device_node.data.identifier, args[1])) {
            input_config.apply(&device_node.data);
            // We don't break here because it is common to have multiple input
            // devices with the same identifier.
        }
    }
}
