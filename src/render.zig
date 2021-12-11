const std = @import("std");
const mem = std.mem;
const os = std.os;
const wlr = @import("wlroots");
const wl = @import("wayland").server.wl;
const pixman = @import("pixman");

const server = &@import("main.zig").server;
const util = @import("util.zig");

const Box = @import("Box.zig");
const LayerSurface = @import("LayerSurface.zig");
const Output = @import("Output.zig");
const Server = @import("Server.zig");
const View = @import("View.zig");
const ViewStack = @import("view_stack.zig").ViewStack;

const log = std.log.scoped(.render);

const SurfaceRenderData = struct {
    output: *const Output,

    /// In output layout coordinates relative to the output
    output_x: i32,
    output_y: i32,

    when: *os.timespec,
};

/// The rendering order in this function must be kept in sync with Cursor.surfaceAt()
pub fn renderOutput(output: *Output) void {
    const renderer = output.wlr_output.backend.getRenderer().?;

    var now: os.timespec = undefined;
    os.clock_gettime(os.CLOCK_MONOTONIC, &now) catch @panic("CLOCK_MONOTONIC not supported");

    var needs_frame: bool = undefined;
    var damage_region: pixman.Region32 = undefined;
    damage_region.init();
    defer damage_region.deinit();
    output.damage.attachRender(&needs_frame, &damage_region) catch {
        log.err("failed to attach renderer", .{});
        return;
    };

    if (!needs_frame) {
        output.wlr_output.rollback();
        return;
    }

    renderer.begin(@intCast(u32, output.wlr_output.width), @intCast(u32, output.wlr_output.height));

    // Find the first visible fullscreen view in the stack if there is one
    var it = ViewStack(View).iter(output.views.first, .forward, output.current.tags, renderFilter);
    const fullscreen_view = while (it.next()) |view| {
        if (view.current.fullscreen) break view;
    } else null;

    // If we have a fullscreen view to render, render it.
    if (fullscreen_view) |view| {
        // Always clear with solid black for fullscreen
        renderer.clear(&[_]f32{ 0, 0, 0, 1 });
        renderView(output, view, &now);
        renderXwaylandUnmanaged(output, &now);
    } else {
        // No fullscreen view, so render normal layers/views
        renderer.clear(&server.config.background_color);

        renderLayer(output, output.getLayer(.background).*, &now, .toplevels);
        renderLayer(output, output.getLayer(.bottom).*, &now, .toplevels);

        // The first view in the list is "on top" so always iterate in reverse.

        // non-focused, non-floating views
        it = ViewStack(View).iter(output.views.last, .reverse, output.current.tags, renderFilter);
        while (it.next()) |view| {
            if (view.current.focus != 0 or view.current.float) continue;
            if (view.draw_borders) renderBorders(output, view, &now);
            renderView(output, view, &now);
        }

        // focused, non-floating views
        it = ViewStack(View).iter(output.views.last, .reverse, output.current.tags, renderFilter);
        while (it.next()) |view| {
            if (view.current.focus == 0 or view.current.float) continue;
            if (view.draw_borders) renderBorders(output, view, &now);
            renderView(output, view, &now);
        }

        // non-focused, floating views
        it = ViewStack(View).iter(output.views.last, .reverse, output.current.tags, renderFilter);
        while (it.next()) |view| {
            if (view.current.focus != 0 or !view.current.float) continue;
            if (view.draw_borders) renderBorders(output, view, &now);
            renderView(output, view, &now);
        }

        // focused, floating views
        it = ViewStack(View).iter(output.views.last, .reverse, output.current.tags, renderFilter);
        while (it.next()) |view| {
            if (view.current.focus == 0 or !view.current.float) continue;
            if (view.draw_borders) renderBorders(output, view, &now);
            renderView(output, view, &now);
        }

        renderXwaylandUnmanaged(output, &now);

        renderLayer(output, output.getLayer(.top).*, &now, .toplevels);

        renderLayer(output, output.getLayer(.background).*, &now, .popups);
        renderLayer(output, output.getLayer(.bottom).*, &now, .popups);
        renderLayer(output, output.getLayer(.top).*, &now, .popups);
    }

    // The overlay layer is rendered in both fullscreen and normal cases
    renderLayer(output, output.getLayer(.overlay).*, &now, .toplevels);
    renderLayer(output, output.getLayer(.overlay).*, &now, .popups);

    renderDragIcons(output, &now);

    // Hardware cursors are rendered by the GPU on a separate plane, and can be
    // moved around without re-rendering what's beneath them - which is more
    // efficient. However, not all hardware supports hardware cursors. For this
    // reason, wlroots provides a software fallback, which we ask it to render
    // here. wlr_cursor handles configuring hardware vs software cursors for you,
    // and this function is a no-op when hardware cursors are in use.
    output.wlr_output.renderSoftwareCursors(null);

    // Conclude rendering and swap the buffers, showing the final frame
    // on-screen.
    renderer.end();

    // TODO: handle failure
    output.wlr_output.commit() catch
        log.err("output commit failed for {s}", .{mem.sliceTo(&output.wlr_output.name, 0)});
}

fn renderFilter(view: *View, filter_tags: u32) bool {
    // This check prevents a race condition when a frame is requested
    // between mapping of a view and the first configure being handled.
    if (view.current.box.width == 0 or view.current.box.height == 0)
        return false;
    return view.current.tags & filter_tags != 0;
}

/// Render all surfaces on the passed layer
fn renderLayer(
    output: *const Output,
    layer: std.TailQueue(LayerSurface),
    now: *os.timespec,
    role: enum { toplevels, popups },
) void {
    var it = layer.first;
    while (it) |node| : (it = node.next) {
        const layer_surface = &node.data;
        var rdata = SurfaceRenderData{
            .output = output,
            .output_x = layer_surface.box.x,
            .output_y = layer_surface.box.y,
            .when = now,
        };
        switch (role) {
            .toplevels => layer_surface.wlr_layer_surface.surface.forEachSurface(
                *SurfaceRenderData,
                renderSurfaceIterator,
                &rdata,
            ),
            .popups => layer_surface.wlr_layer_surface.forEachPopupSurface(
                *SurfaceRenderData,
                renderSurfaceIterator,
                &rdata,
            ),
        }
    }
}

/// Render all surfaces in the view's surface tree, including subsurfaces and popups
fn renderView(output: *const Output, view: *View, now: *os.timespec) void {
    // If we have saved buffers, we are in the middle of a transaction
    // and need to render those buffers until the transaction is complete.
    if (view.saved_buffers.items.len != 0) {
        for (view.saved_buffers.items) |saved_buffer| {
            const texture = saved_buffer.client_buffer.texture orelse continue;
            renderTexture(
                output,
                texture,
                .{
                    .x = saved_buffer.surface_box.x + view.current.box.x - view.saved_surface_box.x,
                    .y = saved_buffer.surface_box.y + view.current.box.y - view.saved_surface_box.y,
                    .width = @intCast(c_int, saved_buffer.surface_box.width),
                    .height = @intCast(c_int, saved_buffer.surface_box.height),
                },
                &saved_buffer.source_box,
                saved_buffer.transform,
            );
        }
    } else {
        // Since there are no stashed buffers, we are not in the middle of
        // a transaction and may simply render the most recent buffers provided
        // by the client.
        var rdata = SurfaceRenderData{
            .output = output,
            .output_x = view.current.box.x - view.surface_box.x,
            .output_y = view.current.box.y - view.surface_box.y,
            .when = now,
        };
        view.forEachSurface(*SurfaceRenderData, renderSurfaceIterator, &rdata);
    }
}

fn renderDragIcons(output: *const Output, now: *os.timespec) void {
    const output_box = server.root.output_layout.getBox(output.wlr_output).?;

    var it = server.root.drag_icons.first;
    while (it) |node| : (it = node.next) {
        const drag_icon = &node.data;

        var rdata = SurfaceRenderData{
            .output = output,
            .output_x = @floatToInt(i32, drag_icon.seat.cursor.wlr_cursor.x) +
                drag_icon.wlr_drag_icon.surface.sx - output_box.x,
            .output_y = @floatToInt(i32, drag_icon.seat.cursor.wlr_cursor.y) +
                drag_icon.wlr_drag_icon.surface.sy - output_box.y,
            .when = now,
        };
        drag_icon.wlr_drag_icon.surface.forEachSurface(*SurfaceRenderData, renderSurfaceIterator, &rdata);
    }
}

/// Render all xwayland unmanaged windows that appear on the output
fn renderXwaylandUnmanaged(output: *const Output, now: *os.timespec) void {
    const output_box = server.root.output_layout.getBox(output.wlr_output).?;

    var it = server.root.xwayland_unmanaged_views.last;
    while (it) |node| : (it = node.prev) {
        const xwayland_surface = node.data.xwayland_surface;

        var rdata = SurfaceRenderData{
            .output = output,
            .output_x = xwayland_surface.x - output_box.x,
            .output_y = xwayland_surface.y - output_box.y,
            .when = now,
        };
        xwayland_surface.surface.?.forEachSurface(*SurfaceRenderData, renderSurfaceIterator, &rdata);
    }
}

/// This function is passed to wlroots to render each surface during iteration
fn renderSurfaceIterator(
    surface: *wlr.Surface,
    surface_x: c_int,
    surface_y: c_int,
    rdata: *SurfaceRenderData,
) callconv(.C) void {
    const texture = surface.getTexture() orelse return;

    var source_box: wlr.FBox = undefined;
    surface.getBufferSourceBox(&source_box);

    renderTexture(
        rdata.output,
        texture,
        .{
            .x = rdata.output_x + surface_x,
            .y = rdata.output_y + surface_y,
            .width = surface.current.width,
            .height = surface.current.height,
        },
        &source_box,
        surface.current.transform,
    );

    surface.sendFrameDone(rdata.when);
}

/// Render the given texture at the given box, taking the scale and transform
/// of the output into account.
fn renderTexture(
    output: *const Output,
    texture: *wlr.Texture,
    dest_box: wlr.Box,
    source_box: *const wlr.FBox,
    transform: wl.Output.Transform,
) void {
    var box = dest_box;

    // Scale the box to the output's current scaling factor
    scaleBox(&box, output.wlr_output.scale);

    // wlr_matrix_project_box is a helper which takes a box with a desired
    // x, y coordinates, width and height, and an output geometry, then
    // prepares an orthographic projection and multiplies the necessary
    // transforms to produce a model-view-projection matrix.
    var matrix: [9]f32 = undefined;
    const inverted = wlr.Output.transformInvert(transform);
    wlr.matrix.projectBox(&matrix, &box, inverted, 0.0, &output.wlr_output.transform_matrix);

    // This takes our matrix, the texture, and an alpha, and performs the actual
    // rendering on the GPU.
    const renderer = output.wlr_output.backend.getRenderer().?;
    renderer.renderSubtextureWithMatrix(texture, source_box, &matrix, 1.0) catch return;
}

fn renderBorders(output: *const Output, view: *View, now: *os.timespec) void {
    const config = &server.config;
    const color = blk: {
        if (view.current.urgent) break :blk &config.border_color_urgent;
        if (view.current.focus != 0) break :blk &config.border_color_focused;
        break :blk &config.border_color_unfocused;
    };
    const border_width = config.border_width;
    const actual_box = if (view.saved_buffers.items.len != 0) view.saved_surface_box else view.surface_box;

    var border: Box = undefined;

    // left and right, covering the corners as well
    border.y = view.current.box.y - @intCast(i32, border_width);
    border.width = border_width;
    border.height = actual_box.height + border_width * 2;

    // left
    border.x = view.current.box.x - @intCast(i32, border_width);
    renderRect(output, border, color);

    // right
    border.x = view.current.box.x + @intCast(i32, actual_box.width);
    renderRect(output, border, color);

    // top and bottom
    border.x = view.current.box.x;
    border.width = actual_box.width;
    border.height = border_width;

    // top
    border.y = view.current.box.y - @intCast(i32, border_width);
    renderRect(output, border, color);

    // bottom border
    border.y = view.current.box.y + @intCast(i32, actual_box.height);
    renderRect(output, border, color);
}

fn renderRect(output: *const Output, box: Box, color: *const [4]f32) void {
    var wlr_box = box.toWlrBox();
    scaleBox(&wlr_box, output.wlr_output.scale);
    output.wlr_output.backend.getRenderer().?.renderRect(
        &wlr_box,
        color,
        &output.wlr_output.transform_matrix,
    );
}

/// Scale a wlr_box, taking the possibility of fractional scaling into account.
fn scaleBox(box: *wlr.Box, scale: f64) void {
    box.x = @floatToInt(c_int, @round(@intToFloat(f64, box.x) * scale));
    box.y = @floatToInt(c_int, @round(@intToFloat(f64, box.y) * scale));
    box.width = scaleLength(box.width, box.x, scale);
    box.height = scaleLength(box.height, box.x, scale);
}

/// Scales a width/height.
///
/// This might seem overly complex, but it needs to work for fractional scaling.
fn scaleLength(length: c_int, offset: c_int, scale: f64) c_int {
    return @floatToInt(c_int, @round(@intToFloat(f64, offset + length) * scale) -
        @round(@intToFloat(f64, offset) * scale));
}
