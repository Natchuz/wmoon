const Self = @This();

const std = @import("std");
const util = @import("util.zig");

const Mapping = @import("Mapping.zig");
const PointerMapping = @import("PointerMapping.zig");

// TODO: use unmanaged array lists here to save memory
mappings: std.ArrayList(Mapping),
pointer_mappings: std.ArrayList(PointerMapping),

pub fn init() Self {
    return .{
        .mappings = std.ArrayList(Mapping).init(util.gpa),
        .pointer_mappings = std.ArrayList(PointerMapping).init(util.gpa),
    };
}

pub fn deinit(self: Self) void {
    for (self.mappings.items) |m| m.deinit();
    self.mappings.deinit();
    self.pointer_mappings.deinit();
}
