const Self = @This();

const std = @import("std");
const mem = std.mem;
const wlr = @import("wlroots");
const wl = @import("wayland").server.wl;

const c = @import("c.zig");
const util = @import("util.zig");

const Config = @import("Config.zig");
const Control = @import("Control.zig");
const DecorationManager = @import("DecorationManager.zig");
const InputManager = @import("InputManager.zig");
const LayerSurface = @import("LayerSurface.zig");
const Output = @import("Output.zig");
const Root = @import("Root.zig");
const View = @import("View.zig");
const ViewStack = @import("view_stack.zig").ViewStack;
const XwaylandUnmanaged = @import("XwaylandUnmanaged.zig");

const log = std.log.scoped(.server);

wl_server: *wl.Server,

sigint_source: *wl.EventSource,
sigterm_source: *wl.EventSource,

backend: *wlr.Backend,
noop_backend: *wlr.Backend,

xdg_shell: *wlr.XdgShell,
new_xdg_surface: wl.Listener(*wlr.XdgSurface),

layer_shell: *wlr.LayerShellV1,
new_layer_surface: wl.Listener(*wlr.LayerSurfaceV1),

xwayland: *wlr.Xwayland,
new_xwayland_surface: wl.Listener(*wlr.XwaylandSurface),

foreign_toplevel_manager: *wlr.ForeignToplevelManagerV1,
xdg_activation: *wlr.XdgActivationV1,

decoration_manager: DecorationManager,
input_manager: InputManager,
root: Root,
config: Config,

pub fn init(self: *Self) !void {
    self.wl_server = try wl.Server.create();
    errdefer self.wl_server.destroy();

    const loop = self.wl_server.getEventLoop();
    self.sigint_source = try loop.addSignal(*wl.Server, std.os.SIGINT, terminate, self.wl_server);
    errdefer self.sigint_source.remove();
    self.sigterm_source = try loop.addSignal(*wl.Server, std.os.SIGTERM, terminate, self.wl_server);
    errdefer self.sigterm_source.remove();

    // This frees itself when the wl.Server is destroyed
    self.backend = try wlr.Backend.autocreate(self.wl_server);

    // This backend is used to create a noop output for use when no actual
    // outputs are available. This frees itself when the wl.Server is destroyed.
    self.noop_backend = try wlr.Backend.createNoop(self.wl_server);

    // This will never be null for the non-custom backends in wlroots
    const renderer = self.backend.getRenderer().?;
    try renderer.initServer(self.wl_server);

    const compositor = try wlr.Compositor.create(self.wl_server, renderer);

    // Set up xdg shell
    self.xdg_shell = try wlr.XdgShell.create(self.wl_server);
    self.new_xdg_surface.setNotify(handleNewXdgSurface);
    self.xdg_shell.events.new_surface.add(&self.new_xdg_surface);

    // Set up layer shell
    self.layer_shell = try wlr.LayerShellV1.create(self.wl_server);
    self.new_layer_surface.setNotify(handleNewLayerSurface);
    self.layer_shell.events.new_surface.add(&self.new_layer_surface);

    // Set up xwayland
    self.xwayland = try wlr.Xwayland.create(self.wl_server, compositor, false);
    self.new_xwayland_surface.setNotify(handleNewXwaylandSurface);
    self.xwayland.events.new_surface.add(&self.new_xwayland_surface);

    self.foreign_toplevel_manager = try wlr.ForeignToplevelManagerV1.create(self.wl_server);
    self.xdg_activation = try wlr.XdgActivationV1.create(self.wl_server);

    _ = try wlr.PrimarySelectionDeviceManagerV1.create(self.wl_server);

    self.config = try Config.init();
    try self.decoration_manager.init();
    try self.root.init();
    // Must be called after root is initialized
    try self.input_manager.init();

    // These all free themselves when the wl_server is destroyed
    _ = try wlr.DataDeviceManager.create(self.wl_server);
    _ = try wlr.DataControlManagerV1.create(self.wl_server);
    _ = try wlr.ExportDmabufManagerV1.create(self.wl_server);
    _ = try wlr.GammaControlManagerV1.create(self.wl_server);
    _ = try wlr.ScreencopyManagerV1.create(self.wl_server);
    _ = try wlr.Viewporter.create(self.wl_server);
}

/// Free allocated memory and clean up. Note: order is important here
pub fn deinit(self: *Self) void {
    self.sigint_source.remove();
    self.sigterm_source.remove();

    self.xwayland.destroy();

    self.wl_server.destroyClients();

    self.backend.destroy();

    self.root.deinit();
    self.input_manager.deinit();

    self.wl_server.destroy();

    self.config.deinit();
}

/// Create the socket, start the backend, and setup the environment
pub fn start(self: Self) !void {
    var buf: [11]u8 = undefined;
    const socket = try self.wl_server.addSocketAuto(&buf);
    try self.backend.start();
    // TODO: don't use libc's setenv
    if (c.setenv("WAYLAND_DISPLAY", socket, 1) < 0) return error.SetenvError;
    if (c.setenv("DISPLAY", self.xwayland.display_name, 1) < 0) return error.SetenvError;
}

/// Handle SIGINT and SIGTERM by gracefully stopping the server
fn terminate(signal: c_int, wl_server: *wl.Server) callconv(.C) c_int {
    wl_server.terminate();
    return 0;
}

fn handleNewXdgSurface(listener: *wl.Listener(*wlr.XdgSurface), xdg_surface: *wlr.XdgSurface) void {
    const self = @fieldParentPtr(Self, "new_xdg_surface", listener);

    if (xdg_surface.role == .popup) {
        log.debug("new xdg_popup", .{});
        return;
    }

    log.debug("new xdg_toplevel", .{});

    // The View will add itself to the output's view stack on map
    const output = self.input_manager.defaultSeat().focused_output;
    const node = util.gpa.create(ViewStack(View).Node) catch {
        xdg_surface.resource.postNoMemory();
        return;
    };
    node.view.init(output, getNewViewTags(output), xdg_surface);
}

/// This event is raised when the layer_shell recieves a new surface from a client.
fn handleNewLayerSurface(listener: *wl.Listener(*wlr.LayerSurfaceV1), wlr_layer_surface: *wlr.LayerSurfaceV1) void {
    const self = @fieldParentPtr(Self, "new_layer_surface", listener);

    log.debug(
        "new layer surface: namespace {s}, layer {s}, anchor {b:0>4}, size {},{}, margin {},{},{},{}, exclusive_zone {}",
        .{
            wlr_layer_surface.namespace,
            @tagName(wlr_layer_surface.client_pending.layer),
            @bitCast(u32, wlr_layer_surface.client_pending.anchor),
            wlr_layer_surface.client_pending.desired_width,
            wlr_layer_surface.client_pending.desired_height,
            wlr_layer_surface.client_pending.margin.top,
            wlr_layer_surface.client_pending.margin.right,
            wlr_layer_surface.client_pending.margin.bottom,
            wlr_layer_surface.client_pending.margin.left,
            wlr_layer_surface.client_pending.exclusive_zone,
        },
    );

    // If the new layer surface does not have an output assigned to it, use the
    // first output or close the surface if none are available.
    if (wlr_layer_surface.output == null) {
        const output = self.input_manager.defaultSeat().focused_output;
        if (output == &self.root.noop_output) {
            log.err("no output available for layer surface '{s}'", .{wlr_layer_surface.namespace});
            wlr_layer_surface.close();
            return;
        }

        log.debug("new layer surface had null output, assigning it to output '{s}'", .{
            mem.sliceTo(&output.wlr_output.name, 0),
        });
        wlr_layer_surface.output = output.wlr_output;
    }

    // The layer surface will add itself to the proper list of the output on map
    const output = @intToPtr(*Output, wlr_layer_surface.output.?.data);
    const node = util.gpa.create(std.TailQueue(LayerSurface).Node) catch {
        wlr_layer_surface.resource.postNoMemory();
        return;
    };
    node.data.init(output, wlr_layer_surface);
}

fn handleNewXwaylandSurface(listener: *wl.Listener(*wlr.XwaylandSurface), wlr_xwayland_surface: *wlr.XwaylandSurface) void {
    const self = @fieldParentPtr(Self, "new_xwayland_surface", listener);

    if (wlr_xwayland_surface.override_redirect) {
        log.debug("new unmanaged xwayland surface", .{});
        // The unmanged surface will add itself to the list of unmanaged views
        // in Root when it is mapped.
        const node = util.gpa.create(std.TailQueue(XwaylandUnmanaged).Node) catch return;
        node.data.init(wlr_xwayland_surface);
        return;
    }

    log.debug(
        "new xwayland surface: title '{s}', class '{s}'",
        .{ wlr_xwayland_surface.title, wlr_xwayland_surface.class },
    );

    // The View will add itself to the output's view stack on map
    const output = self.input_manager.defaultSeat().focused_output;
    const node = util.gpa.create(ViewStack(View).Node) catch return;
    node.view.init(output, getNewViewTags(output), wlr_xwayland_surface);
}

fn getNewViewTags(output: *Output) u32 {
    const tags = output.current.tags & output.spawn_tagmask;
    return if (tags != 0) tags else output.current.tags;
}
