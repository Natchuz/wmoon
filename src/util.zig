const std = @import("std");
const os = std.os;

/// The global general-purpose allocator used throughout river's code
pub const gpa = std.heap.c_allocator;
