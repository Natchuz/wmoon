// This file is part of river, a dynamic tiling wayland compositor.
//
// Copyright 2020 The River Developers
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

const Self = @This();

const std = @import("std");
const wlr = @import("wlroots");
const wayland = @import("wayland");
const wl = wayland.server.wl;
const zriver = wayland.server.zriver;

const server = &@import("main.zig").server;
const util = @import("util.zig");

const Output = @import("Output.zig");
const OutputStatus = @import("OutputStatus.zig");
const Seat = @import("Seat.zig");
const SeatStatus = @import("SeatStatus.zig");
const Server = @import("Server.zig");

const log = std.log.scoped(.river_status);

global: *wl.Global,

server_destroy: wl.Listener(*wl.Server) = wl.Listener(*wl.Server).init(handleServerDestroy),

pub fn init(self: *Self) !void {
    self.* = .{
        .global = try wl.Global.create(server.wl_server, zriver.StatusManagerV1, 2, *Self, self, bind),
    };

    server.wl_server.addDestroyListener(&self.server_destroy);
}

fn handleServerDestroy(listener: *wl.Listener(*wl.Server), wl_server: *wl.Server) void {
    const self = @fieldParentPtr(Self, "server_destroy", listener);
    self.global.destroy();
}

fn bind(client: *wl.Client, self: *Self, version: u32, id: u32) callconv(.C) void {
    const status_manager = zriver.StatusManagerV1.create(client, version, id) catch {
        client.postNoMemory();
        log.crit("out of memory", .{});
        return;
    };
    status_manager.setHandler(*Self, handleRequest, null, self);
}

fn handleRequest(
    status_manager: *zriver.StatusManagerV1,
    request: zriver.StatusManagerV1.Request,
    self: *Self,
) void {
    switch (request) {
        .destroy => status_manager.destroy(),
        .get_river_output_status => |req| {
            // ignore if the output is inert
            const wlr_output = wlr.Output.fromWlOutput(req.output) orelse return;
            const output = @intToPtr(*Output, wlr_output.data);

            const node = util.gpa.create(std.SinglyLinkedList(OutputStatus).Node) catch {
                status_manager.getClient().postNoMemory();
                log.crit("out of memory", .{});
                return;
            };

            const output_status = zriver.OutputStatusV1.create(
                status_manager.getClient(),
                status_manager.getVersion(),
                req.id,
            ) catch {
                status_manager.getClient().postNoMemory();
                util.gpa.destroy(node);
                log.crit("out of memory", .{});
                return;
            };

            node.data.init(output, output_status);
            output.status_trackers.prepend(node);
        },
        .get_river_seat_status => |req| {
            // ignore if the seat is inert
            const wlr_seat = wlr.Seat.Client.fromWlSeat(req.seat) orelse return;
            const seat = @intToPtr(*Seat, wlr_seat.seat.data);

            const node = util.gpa.create(std.SinglyLinkedList(SeatStatus).Node) catch {
                status_manager.getClient().postNoMemory();
                log.crit("out of memory", .{});
                return;
            };

            const seat_status = zriver.SeatStatusV1.create(
                status_manager.getClient(),
                status_manager.getVersion(),
                req.id,
            ) catch {
                status_manager.getClient().postNoMemory();
                util.gpa.destroy(node);
                log.crit("out of memory", .{});
                return;
            };

            node.data.init(seat, seat_status);
            seat.status_trackers.prepend(node);
        },
    }
}
