const DragIcon = @This();

const std = @import("std");
const wlr = @import("wlroots");
const wl = @import("wayland").server.wl;

const server = &@import("main.zig").server;
const util = @import("util.zig");

const Seat = @import("Seat.zig");
const Subsurface = @import("Subsurface.zig");

seat: *Seat,
wlr_drag_icon: *wlr.Drag.Icon,

// Always active
destroy: wl.Listener(*wlr.Drag.Icon) = wl.Listener(*wlr.Drag.Icon).init(handleDestroy),
map: wl.Listener(*wlr.Drag.Icon) = wl.Listener(*wlr.Drag.Icon).init(handleMap),
unmap: wl.Listener(*wlr.Drag.Icon) = wl.Listener(*wlr.Drag.Icon).init(handleUnmap),
new_subsurface: wl.Listener(*wlr.Subsurface) = wl.Listener(*wlr.Subsurface).init(handleNewSubsurface),

// Only active while mapped
commit: wl.Listener(*wlr.Surface) = wl.Listener(*wlr.Surface).init(handleCommit),

pub fn init(drag_icon: *DragIcon, seat: *Seat, wlr_drag_icon: *wlr.Drag.Icon) void {
    drag_icon.* = .{ .seat = seat, .wlr_drag_icon = wlr_drag_icon };

    wlr_drag_icon.events.destroy.add(&drag_icon.destroy);
    wlr_drag_icon.events.map.add(&drag_icon.map);
    wlr_drag_icon.events.unmap.add(&drag_icon.unmap);
    wlr_drag_icon.surface.events.new_subsurface.add(&drag_icon.new_subsurface);

    Subsurface.handleExisting(wlr_drag_icon.surface, .{ .drag_icon = drag_icon });
}

fn handleDestroy(listener: *wl.Listener(*wlr.Drag.Icon), wlr_drag_icon: *wlr.Drag.Icon) void {
    const drag_icon = @fieldParentPtr(DragIcon, "destroy", listener);

    const node = @fieldParentPtr(std.SinglyLinkedList(DragIcon).Node, "data", drag_icon);
    server.root.drag_icons.remove(node);

    drag_icon.destroy.link.remove();
    drag_icon.map.link.remove();
    drag_icon.unmap.link.remove();
    drag_icon.new_subsurface.link.remove();

    Subsurface.destroySubsurfaces(wlr_drag_icon.surface);

    util.gpa.destroy(node);
}

fn handleMap(listener: *wl.Listener(*wlr.Drag.Icon), wlr_drag_icon: *wlr.Drag.Icon) void {
    const drag_icon = @fieldParentPtr(DragIcon, "map", listener);

    wlr_drag_icon.surface.events.commit.add(&drag_icon.commit);
    var it = server.root.outputs.first;
    while (it) |node| : (it = node.next) node.data.damage.addWhole();
}

fn handleUnmap(listener: *wl.Listener(*wlr.Drag.Icon), wlr_drag_icon: *wlr.Drag.Icon) void {
    const drag_icon = @fieldParentPtr(DragIcon, "unmap", listener);

    drag_icon.commit.link.remove();
    var it = server.root.outputs.first;
    while (it) |node| : (it = node.next) node.data.damage.addWhole();
}
fn handleCommit(listener: *wl.Listener(*wlr.Surface), surface: *wlr.Surface) void {
    const drag_icon = @fieldParentPtr(DragIcon, "commit", listener);

    var it = server.root.outputs.first;
    while (it) |node| : (it = node.next) node.data.damage.addWhole();
}

fn handleNewSubsurface(listener: *wl.Listener(*wlr.Subsurface), wlr_subsurface: *wlr.Subsurface) void {
    const drag_icon = @fieldParentPtr(DragIcon, "new_subsurface", listener);

    Subsurface.create(wlr_subsurface, .{ .drag_icon = drag_icon });
}
