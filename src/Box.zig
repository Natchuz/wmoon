const Self = @This();

const wlr = @import("wlroots");

x: i32,
y: i32,
width: u32,
height: u32,

pub fn fromWlrBox(wlr_box: wlr.Box) Self {
    return Self{
        .x = @intCast(i32, wlr_box.x),
        .y = @intCast(i32, wlr_box.y),
        .width = @intCast(u32, wlr_box.width),
        .height = @intCast(u32, wlr_box.height),
    };
}

pub fn toWlrBox(self: Self) wlr.Box {
    return wlr.Box{
        .x = @intCast(c_int, self.x),
        .y = @intCast(c_int, self.y),
        .width = @intCast(c_int, self.width),
        .height = @intCast(c_int, self.height),
    };
}
