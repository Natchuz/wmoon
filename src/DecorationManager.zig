const Self = @This();

const std = @import("std");
const wlr = @import("wlroots");
const wl = @import("wayland").server.wl;

const server = &@import("main.zig").server;
const util = @import("util.zig");

const Decoration = @import("Decoration.zig");
const Server = @import("Server.zig");

/// List of all Decoration objects. This will clean itself up on exit through
/// the wlr.XdgToplevelDecorationV1.events.destroy event.
decorations: std.TailQueue(Decoration) = .{},

xdg_decoration_manager: *wlr.XdgDecorationManagerV1,

new_toplevel_decoration: wl.Listener(*wlr.XdgToplevelDecorationV1) =
    wl.Listener(*wlr.XdgToplevelDecorationV1).init(handleNewToplevelDecoration),

pub fn init(self: *Self) !void {
    self.* = .{
        .xdg_decoration_manager = try wlr.XdgDecorationManagerV1.create(server.wl_server),
    };

    self.xdg_decoration_manager.events.new_toplevel_decoration.add(&self.new_toplevel_decoration);
}

fn handleNewToplevelDecoration(
    listener: *wl.Listener(*wlr.XdgToplevelDecorationV1),
    xdg_toplevel_decoration: *wlr.XdgToplevelDecorationV1,
) void {
    const self = @fieldParentPtr(Self, "new_toplevel_decoration", listener);
    const decoration_node = util.gpa.create(std.TailQueue(Decoration).Node) catch {
        xdg_toplevel_decoration.resource.postNoMemory();
        return;
    };
    decoration_node.data.init(xdg_toplevel_decoration);
    self.decorations.append(decoration_node);
}
