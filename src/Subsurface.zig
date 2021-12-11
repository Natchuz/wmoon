const Subsurface = @This();

const std = @import("std");
const assert = std.debug.assert;
const wlr = @import("wlroots");
const wl = @import("wayland").server.wl;

const server = &@import("main.zig").server;
const util = @import("util.zig");

const DragIcon = @import("DragIcon.zig");
const LayerSurface = @import("LayerSurface.zig");
const XdgToplevel = @import("XdgToplevel.zig");

pub const Parent = union(enum) {
    xdg_toplevel: *XdgToplevel,
    layer_surface: *LayerSurface,
    drag_icon: *DragIcon,

    pub fn damageWholeOutput(parent: Parent) void {
        switch (parent) {
            .xdg_toplevel => |xdg_toplevel| xdg_toplevel.view.output.damage.addWhole(),
            .layer_surface => |layer_surface| layer_surface.output.damage.addWhole(),
            .drag_icon => |drag_icon| {
                var it = server.root.outputs.first;
                while (it) |node| : (it = node.next) node.data.damage.addWhole();
            },
        }
    }
};

/// The parent at the root of this surface tree
parent: Parent,
wlr_subsurface: *wlr.Subsurface,

// Always active
subsurface_destroy: wl.Listener(*wlr.Subsurface) = wl.Listener(*wlr.Subsurface).init(handleDestroy),
map: wl.Listener(*wlr.Subsurface) = wl.Listener(*wlr.Subsurface).init(handleMap),
unmap: wl.Listener(*wlr.Subsurface) = wl.Listener(*wlr.Subsurface).init(handleUnmap),
new_subsurface: wl.Listener(*wlr.Subsurface) = wl.Listener(*wlr.Subsurface).init(handleNewSubsurface),

// Only active while mapped
commit: wl.Listener(*wlr.Surface) = wl.Listener(*wlr.Surface).init(handleCommit),

pub fn create(wlr_subsurface: *wlr.Subsurface, parent: Parent) void {
    const subsurface = util.gpa.create(Subsurface) catch {
        std.log.crit("out of memory", .{});
        wlr_subsurface.resource.getClient().postNoMemory();
        return;
    };
    subsurface.* = .{ .wlr_subsurface = wlr_subsurface, .parent = parent };
    assert(wlr_subsurface.data == 0);
    wlr_subsurface.data = @ptrToInt(subsurface);

    wlr_subsurface.events.destroy.add(&subsurface.subsurface_destroy);
    wlr_subsurface.events.map.add(&subsurface.map);
    wlr_subsurface.events.unmap.add(&subsurface.unmap);
    wlr_subsurface.surface.events.new_subsurface.add(&subsurface.new_subsurface);

    Subsurface.handleExisting(wlr_subsurface.surface, parent);
}

/// Create Subsurface structs to track subsurfaces already present on the
/// given surface when river becomes aware of the surface as we won't
/// recieve a new_subsurface event for them.
pub fn handleExisting(surface: *wlr.Surface, parent: Parent) void {
    var below_it = surface.subsurfaces_below.iterator(.forward);
    while (below_it.next()) |s| Subsurface.create(s, parent);

    var above_it = surface.subsurfaces_above.iterator(.forward);
    while (above_it.next()) |s| Subsurface.create(s, parent);
}

/// Destroy this Subsurface and all of its children
pub fn destroy(subsurface: *Subsurface) void {
    subsurface.subsurface_destroy.link.remove();
    subsurface.map.link.remove();
    subsurface.unmap.link.remove();
    subsurface.new_subsurface.link.remove();

    if (subsurface.wlr_subsurface.mapped) subsurface.commit.link.remove();

    Subsurface.destroySubsurfaces(subsurface.wlr_subsurface.surface);

    subsurface.wlr_subsurface.data = 0;
    util.gpa.destroy(subsurface);
}

pub fn destroySubsurfaces(surface: *wlr.Surface) void {
    var below_it = surface.subsurfaces_below.iterator(.forward);
    while (below_it.next()) |wlr_subsurface| {
        if (@intToPtr(?*Subsurface, wlr_subsurface.data)) |s| s.destroy();
    }

    var above_it = surface.subsurfaces_above.iterator(.forward);
    while (above_it.next()) |wlr_subsurface| {
        if (@intToPtr(?*Subsurface, wlr_subsurface.data)) |s| s.destroy();
    }
}

fn handleDestroy(listener: *wl.Listener(*wlr.Subsurface), wlr_subsurface: *wlr.Subsurface) void {
    const subsurface = @fieldParentPtr(Subsurface, "subsurface_destroy", listener);

    subsurface.destroy();
}

fn handleMap(listener: *wl.Listener(*wlr.Subsurface), wlr_subsurface: *wlr.Subsurface) void {
    const subsurface = @fieldParentPtr(Subsurface, "map", listener);

    wlr_subsurface.surface.events.commit.add(&subsurface.commit);
    subsurface.parent.damageWholeOutput();
}

fn handleUnmap(listener: *wl.Listener(*wlr.Subsurface), wlr_subsurface: *wlr.Subsurface) void {
    const subsurface = @fieldParentPtr(Subsurface, "unmap", listener);

    subsurface.commit.link.remove();
    subsurface.parent.damageWholeOutput();
}

fn handleCommit(listener: *wl.Listener(*wlr.Surface), surface: *wlr.Surface) void {
    const subsurface = @fieldParentPtr(Subsurface, "commit", listener);

    subsurface.parent.damageWholeOutput();
}

fn handleNewSubsurface(listener: *wl.Listener(*wlr.Subsurface), new_wlr_subsurface: *wlr.Subsurface) void {
    const subsurface = @fieldParentPtr(Subsurface, "new_subsurface", listener);

    Subsurface.create(new_wlr_subsurface, subsurface.parent);
}
