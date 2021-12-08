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

const View = @import("View.zig");

pub const AttachMode = enum {
    top,
    bottom,
};

/// A specialized doubly-linked stack that allows for filtered iteration
/// over the nodes. T must be View or *View.
pub fn ViewStack(comptime T: type) type {
    if (!(T == View or T == *View)) {
        @compileError("ViewStack: T must be View or *View");
    }
    return struct {
        const Self = @This();

        pub const Node = struct {
            /// Previous/next nodes in the stack
            prev: ?*Node,
            next: ?*Node,

            /// The view stored in this node
            view: T,
        };

        /// Top/bottom nodes in the stack
        first: ?*Node = null,
        last: ?*Node = null,

        /// Add a node to the top of the stack.
        pub fn push(self: *Self, new_node: *Node) void {
            // Set the prev/next pointers of the new node
            new_node.prev = null;
            new_node.next = self.first;

            if (self.first) |first| {
                // If the list is not empty, set the prev pointer of the current
                // first node to the new node.
                first.prev = new_node;
            } else {
                // If the list is empty set the last pointer to the new node.
                self.last = new_node;
            }

            // Set the first pointer to the new node
            self.first = new_node;
        }

        /// Add a node to the bottom of the stack.
        pub fn append(self: *Self, new_node: *Node) void {
            // Set the prev/next pointers of the new node
            new_node.prev = self.last;
            new_node.next = null;

            if (self.last) |last| {
                // If the list is not empty, set the next pointer of the current
                // first node to the new node.
                last.next = new_node;
            } else {
                // If the list is empty set the first pointer to the new node.
                self.first = new_node;
            }

            // Set the last pointer to the new node
            self.last = new_node;
        }

        /// Attach a node into the viewstack based on the attach mode
        pub fn attach(self: *Self, new_node: *Node, mode: AttachMode) void {
            switch (mode) {
                .top => self.push(new_node),
                .bottom => self.append(new_node),
            }
        }

        /// Remove a node from the view stack. This removes it from the stack of
        /// all views as well as the stack of visible ones.
        pub fn remove(self: *Self, target_node: *Node) void {
            // Set the previous node/list head to the next pointer
            if (target_node.prev) |prev_node| {
                prev_node.next = target_node.next;
            } else {
                self.first = target_node.next;
            }

            // Set the next node/list tail to the previous pointer
            if (target_node.next) |next_node| {
                next_node.prev = target_node.prev;
            } else {
                self.last = target_node.prev;
            }
        }

        /// Swap the nodes a and b.
        /// pointers to Node.T will point to the same data as before
        pub fn swap(self: *Self, a: *Node, b: *Node) void {
            // Set self.first and self.last
            const first = self.first;
            const last = self.last;
            if (a == first) {
                self.first = b;
            } else if (a == last) {
                self.last = b;
            }

            if (b == first) {
                self.first = a;
            } else if (b == last) {
                self.last = a;
            }

            // This is so complicated to make sure everything works when a and b are neighbors
            const a_next = if (b.next == a) b else b.next;
            const a_prev = if (b.prev == a) b else b.prev;
            const b_next = if (a.next == b) a else a.next;
            const b_prev = if (a.prev == b) a else a.prev;

            a.next = a_next;
            a.prev = a_prev;
            b.next = b_next;
            b.prev = b_prev;

            // Update all neighbors
            if (a.next) |next| {
                next.prev = a;
            }
            if (a.prev) |prev| {
                prev.next = a;
            }
            if (b.next) |next| {
                next.prev = b;
            }
            if (b.prev) |prev| {
                prev.next = b;
            }
        }

        const Direction = enum {
            forward,
            reverse,
        };

        fn Iter(comptime Context: type) type {
            return struct {
                it: ?*Node,
                dir: Direction,
                context: Context,
                filter: fn (*View, Context) bool,

                /// Returns the next node in iteration order which passes the
                /// filter, or null if done.
                pub fn next(self: *@This()) ?*View {
                    return while (self.it) |node| : (self.it = if (self.dir == .forward) node.next else node.prev) {
                        const view = if (T == View) &node.view else node.view;
                        if (self.filter(view, self.context)) {
                            self.it = if (self.dir == .forward) node.next else node.prev;
                            break view;
                        }
                    } else null;
                }
            };
        }

        /// Return a filtered iterator over the stack given a start node,
        /// iteration direction, and filter function. Views for which the
        /// filter function returns false will be skipped.
        pub fn iter(
            start: ?*Node,
            dir: Direction,
            context: anytype,
            filter: fn (*View, @TypeOf(context)) bool,
        ) Iter(@TypeOf(context)) {
            return .{ .it = start, .dir = dir, .context = context, .filter = filter };
        }
    };
}

test "push/remove (*View)" {
    const testing = @import("std").testing;

    const allocator = testing.allocator;

    var views = ViewStack(*View){};

    const one = try allocator.create(ViewStack(*View).Node);
    defer allocator.destroy(one);
    const two = try allocator.create(ViewStack(*View).Node);
    defer allocator.destroy(two);
    const three = try allocator.create(ViewStack(*View).Node);
    defer allocator.destroy(three);
    const four = try allocator.create(ViewStack(*View).Node);
    defer allocator.destroy(four);
    const five = try allocator.create(ViewStack(*View).Node);
    defer allocator.destroy(five);

    views.push(three); // {3}
    views.push(one); // {1, 3}
    views.push(four); // {4, 1, 3}
    views.push(five); // {5, 4, 1, 3}
    views.push(two); // {2, 5, 4, 1, 3}

    // Simple insertion
    {
        var it = views.first;
        try testing.expect(it == two);
        it = it.?.next;
        try testing.expect(it == five);
        it = it.?.next;
        try testing.expect(it == four);
        it = it.?.next;
        try testing.expect(it == one);
        it = it.?.next;
        try testing.expect(it == three);
        it = it.?.next;

        try testing.expect(it == null);

        try testing.expect(views.first == two);
        try testing.expect(views.last == three);
    }

    // Removal of first
    views.remove(two);
    {
        var it = views.first;
        try testing.expect(it == five);
        it = it.?.next;
        try testing.expect(it == four);
        it = it.?.next;
        try testing.expect(it == one);
        it = it.?.next;
        try testing.expect(it == three);
        it = it.?.next;

        try testing.expect(it == null);

        try testing.expect(views.first == five);
        try testing.expect(views.last == three);
    }

    // Removal of last
    views.remove(three);
    {
        var it = views.first;
        try testing.expect(it == five);
        it = it.?.next;
        try testing.expect(it == four);
        it = it.?.next;
        try testing.expect(it == one);
        it = it.?.next;

        try testing.expect(it == null);

        try testing.expect(views.first == five);
        try testing.expect(views.last == one);
    }

    // Remove from middle
    views.remove(four);
    {
        var it = views.first;
        try testing.expect(it == five);
        it = it.?.next;
        try testing.expect(it == one);
        it = it.?.next;

        try testing.expect(it == null);

        try testing.expect(views.first == five);
        try testing.expect(views.last == one);
    }

    // Reinsertion
    views.push(two);
    views.push(three);
    views.push(four);
    {
        var it = views.first;
        try testing.expect(it == four);
        it = it.?.next;
        try testing.expect(it == three);
        it = it.?.next;
        try testing.expect(it == two);
        it = it.?.next;
        try testing.expect(it == five);
        it = it.?.next;
        try testing.expect(it == one);
        it = it.?.next;

        try testing.expect(it == null);

        try testing.expect(views.first == four);
        try testing.expect(views.last == one);
    }

    // Clear
    views.remove(four);
    views.remove(two);
    views.remove(three);
    views.remove(one);
    views.remove(five);

    try testing.expect(views.first == null);
    try testing.expect(views.last == null);
}

test "iteration (View)" {
    const std = @import("std");
    const testing = std.testing;

    const allocator = testing.allocator;

    const filters = struct {
        fn all(view: *View, context: void) bool {
            return true;
        }

        fn none(view: *View, context: void) bool {
            return false;
        }

        fn current(view: *View, filter_tags: u32) bool {
            return view.current.tags & filter_tags != 0;
        }
    };

    var views = ViewStack(View){};

    const one_a_pb = try allocator.create(ViewStack(View).Node);
    defer allocator.destroy(one_a_pb);
    one_a_pb.view.current.tags = 1 << 0;
    one_a_pb.view.pending.tags = 1 << 1;

    const two_a = try allocator.create(ViewStack(View).Node);
    defer allocator.destroy(two_a);
    two_a.view.current.tags = 1 << 0;
    two_a.view.pending.tags = 1 << 0;

    const three_b_pa = try allocator.create(ViewStack(View).Node);
    defer allocator.destroy(three_b_pa);
    three_b_pa.view.current.tags = 1 << 1;
    three_b_pa.view.pending.tags = 1 << 0;

    const four_b = try allocator.create(ViewStack(View).Node);
    defer allocator.destroy(four_b);
    four_b.view.current.tags = 1 << 1;
    four_b.view.pending.tags = 1 << 1;

    const five_b = try allocator.create(ViewStack(View).Node);
    defer allocator.destroy(five_b);
    five_b.view.current.tags = 1 << 1;
    five_b.view.pending.tags = 1 << 1;

    views.push(three_b_pa); // {3}
    views.push(one_a_pb); // {1, 3}
    views.push(four_b); // {4, 1, 3}
    views.push(five_b); // {5, 4, 1, 3}
    views.push(two_a); // {2, 5, 4, 1, 3}

    // Iteration over all views
    {
        var it = ViewStack(View).iter(views.first, .forward, {}, filters.all);
        try testing.expect(it.next() == &two_a.view);
        try testing.expect(it.next() == &five_b.view);
        try testing.expect(it.next() == &four_b.view);
        try testing.expect(it.next() == &one_a_pb.view);
        try testing.expect(it.next() == &three_b_pa.view);
        try testing.expect(it.next() == null);
    }

    // Iteration over no views
    {
        var it = ViewStack(View).iter(views.first, .forward, {}, filters.none);
        try testing.expect(it.next() == null);
    }

    // Iteration over 'a' tags
    {
        var it = ViewStack(View).iter(views.first, .forward, @as(u32, 1 << 0), filters.current);
        try testing.expect(it.next() == &two_a.view);
        try testing.expect(it.next() == &one_a_pb.view);
        try testing.expect(it.next() == null);
    }

    // Iteration over 'b' tags
    {
        var it = ViewStack(View).iter(views.first, .forward, @as(u32, 1 << 1), filters.current);
        try testing.expect(it.next() == &five_b.view);
        try testing.expect(it.next() == &four_b.view);
        try testing.expect(it.next() == &three_b_pa.view);
        try testing.expect(it.next() == null);
    }

    // Reverse iteration over all views
    {
        var it = ViewStack(View).iter(views.last, .reverse, {}, filters.all);
        try testing.expect(it.next() == &three_b_pa.view);
        try testing.expect(it.next() == &one_a_pb.view);
        try testing.expect(it.next() == &four_b.view);
        try testing.expect(it.next() == &five_b.view);
        try testing.expect(it.next() == &two_a.view);
        try testing.expect(it.next() == null);
    }

    // Reverse iteration over no views
    {
        var it = ViewStack(View).iter(views.last, .reverse, {}, filters.none);
        try testing.expect(it.next() == null);
    }

    // Reverse iteration over 'a' tags
    {
        var it = ViewStack(View).iter(views.last, .reverse, @as(u32, 1 << 0), filters.current);
        try testing.expect(it.next() == &one_a_pb.view);
        try testing.expect(it.next() == &two_a.view);
        try testing.expect(it.next() == null);
    }

    // Reverse iteration over 'b' tags
    {
        var it = ViewStack(View).iter(views.last, .reverse, @as(u32, 1 << 1), filters.current);
        try testing.expect(it.next() == &three_b_pa.view);
        try testing.expect(it.next() == &four_b.view);
        try testing.expect(it.next() == &five_b.view);
        try testing.expect(it.next() == null);
    }

    // Swap, then iterate
    {
        var view_a = views.first orelse unreachable;
        var view_b = view_a.next orelse unreachable;
        ViewStack(View).swap(&views, view_a, view_b); // {2, 5, 4, 1, 3} -> {5, 2, 4, 1, 3}

        view_a = views.last orelse unreachable;
        view_b = view_a.prev orelse unreachable;
        ViewStack(View).swap(&views, view_a, view_b); // {5, 2, 4, 1, 3} -> {5, 2, 4, 3, 1}

        view_a = views.last orelse unreachable;
        view_b = views.first orelse unreachable;
        ViewStack(View).swap(&views, view_a, view_b); // {5, 2, 4, 3, 1} -> {1, 2, 4, 3, 5}

        view_a = views.first orelse unreachable;
        view_b = views.last orelse unreachable;
        ViewStack(View).swap(&views, view_a, view_b); // {1, 2, 4, 3, 5} -> {5, 2, 4, 3, 1}

        view_a = views.first orelse unreachable;
        view_a = view_a.next orelse unreachable;
        view_b = view_a.next orelse unreachable;
        view_b = view_b.next orelse unreachable;
        ViewStack(View).swap(&views, view_a, view_b); // {5, 2, 4, 3, 1} -> {5, 3, 4, 2, 1}

        var it = ViewStack(View).iter(views.first, .forward, {}, filters.all);
        try testing.expect(it.next() == &five_b.view);
        try testing.expect(it.next() == &three_b_pa.view);
        try testing.expect(it.next() == &four_b.view);
        try testing.expect(it.next() == &two_a.view);
        try testing.expect(it.next() == &one_a_pb.view);
        try testing.expect(it.next() == null);

        it = ViewStack(View).iter(views.last, .reverse, {}, filters.all);
        try testing.expect(it.next() == &one_a_pb.view);
        try testing.expect(it.next() == &two_a.view);
        try testing.expect(it.next() == &four_b.view);
        try testing.expect(it.next() == &three_b_pa.view);
        try testing.expect(it.next() == &five_b.view);
        try testing.expect(it.next() == null);
    }
}
