const wlr = @import("wlroots");

pub const Action = enum {
    move,
    resize,
};

event_code: u32,
modifiers: wlr.Keyboard.ModifierMask,
action: Action,
