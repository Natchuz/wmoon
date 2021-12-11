const Self = @This();

const build_options = @import("build_options");
const std = @import("std");
const wlr = @import("wlroots");

const log = std.log.scoped(.input_config);

const c = @import("c.zig");

const server = &@import("main.zig").server;
const util = @import("util.zig");

const InputDevice = @import("InputManager.zig").InputDevice;

// TODO - keyboards
//      - mapping to output / region
//      - calibration matrices
//      - scroll factor

pub const EventState = enum {
    enabled,
    disabled,
    @"disabled-on-external-mouse",

    pub fn apply(event_state: EventState, device: *c.libinput_device) void {
        const want = switch (event_state) {
            .enabled => c.LIBINPUT_CONFIG_SEND_EVENTS_ENABLED,
            .disabled => c.LIBINPUT_CONFIG_SEND_EVENTS_DISABLED,
            .@"disabled-on-external-mouse" => c.LIBINPUT_CONFIG_SEND_EVENTS_DISABLED_ON_EXTERNAL_MOUSE,
        };
        const current = c.libinput_device_config_send_events_get_mode(device);
        if (want != current) {
            _ = c.libinput_device_config_send_events_set_mode(device, @intCast(u32, want));
        }
    }
};

pub const AccelProfile = enum {
    none,
    flat,
    adaptive,

    pub fn apply(accel_profile: AccelProfile, device: *c.libinput_device) void {
        const want = @intToEnum(c.libinput_config_accel_profile, switch (accel_profile) {
            .none => c.LIBINPUT_CONFIG_ACCEL_PROFILE_NONE,
            .flat => c.LIBINPUT_CONFIG_ACCEL_PROFILE_FLAT,
            .adaptive => c.LIBINPUT_CONFIG_ACCEL_PROFILE_ADAPTIVE,
        });
        if (c.libinput_device_config_accel_is_available(device) == 0) return;
        const current = c.libinput_device_config_accel_get_profile(device);
        if (want != current) {
            _ = c.libinput_device_config_accel_set_profile(device, want);
        }
    }
};

pub const ClickMethod = enum {
    none,
    @"button-areas",
    clickfinger,

    pub fn apply(click_method: ClickMethod, device: *c.libinput_device) void {
        const want = @intToEnum(c.libinput_config_click_method, switch (click_method) {
            .none => c.LIBINPUT_CONFIG_CLICK_METHOD_NONE,
            .@"button-areas" => c.LIBINPUT_CONFIG_CLICK_METHOD_BUTTON_AREAS,
            .clickfinger => c.LIBINPUT_CONFIG_CLICK_METHOD_CLICKFINGER,
        });
        const supports = c.libinput_device_config_click_get_methods(device);
        if (supports & @intCast(u32, @enumToInt(want)) == 0) return;
        _ = c.libinput_device_config_click_set_method(device, want);
    }
};

pub const DragState = enum {
    disabled,
    enabled,

    pub fn apply(drag_state: DragState, device: *c.libinput_device) void {
        const want = @intToEnum(c.libinput_config_drag_state, switch (drag_state) {
            .disabled => c.LIBINPUT_CONFIG_DRAG_DISABLED,
            .enabled => c.LIBINPUT_CONFIG_DRAG_ENABLED,
        });
        if (c.libinput_device_config_tap_get_finger_count(device) <= 0) return;
        const current = c.libinput_device_config_tap_get_drag_enabled(device);
        if (want != current) {
            _ = c.libinput_device_config_tap_set_drag_enabled(device, want);
        }
    }
};

pub const DragLock = enum {
    disabled,
    enabled,

    pub fn apply(drag_lock: DragLock, device: *c.libinput_device) void {
        const want = @intToEnum(c.libinput_config_drag_lock_state, switch (drag_lock) {
            .disabled => c.LIBINPUT_CONFIG_DRAG_LOCK_DISABLED,
            .enabled => c.LIBINPUT_CONFIG_DRAG_LOCK_ENABLED,
        });
        if (c.libinput_device_config_tap_get_finger_count(device) <= 0) return;
        const current = c.libinput_device_config_tap_get_drag_lock_enabled(device);
        if (want != current) {
            _ = c.libinput_device_config_tap_set_drag_lock_enabled(device, want);
        }
    }
};

pub const DwtState = enum {
    disabled,
    enabled,

    pub fn apply(dwt_state: DwtState, device: *c.libinput_device) void {
        const want = @intToEnum(c.libinput_config_dwt_state, switch (dwt_state) {
            .disabled => c.LIBINPUT_CONFIG_DWT_DISABLED,
            .enabled => c.LIBINPUT_CONFIG_DWT_ENABLED,
        });
        if (c.libinput_device_config_dwt_is_available(device) == 0) return;
        const current = c.libinput_device_config_dwt_get_enabled(device);
        if (want != current) {
            _ = c.libinput_device_config_dwt_set_enabled(device, want);
        }
    }
};

pub const MiddleEmulation = enum {
    disabled,
    enabled,

    pub fn apply(middle_emulation: MiddleEmulation, device: *c.libinput_device) void {
        const want = @intToEnum(c.libinput_config_middle_emulation_state, switch (middle_emulation) {
            .disabled => c.LIBINPUT_CONFIG_MIDDLE_EMULATION_DISABLED,
            .enabled => c.LIBINPUT_CONFIG_MIDDLE_EMULATION_ENABLED,
        });
        if (c.libinput_device_config_middle_emulation_is_available(device) == 0) return;
        const current = c.libinput_device_config_middle_emulation_get_enabled(device);
        if (want != current) {
            _ = c.libinput_device_config_middle_emulation_set_enabled(device, want);
        }
    }
};

pub const NaturalScroll = enum {
    disabled,
    enabled,

    pub fn apply(natural_scroll: NaturalScroll, device: *c.libinput_device) void {
        const want: c_int = switch (natural_scroll) {
            .disabled => 0,
            .enabled => 1,
        };
        if (c.libinput_device_config_scroll_has_natural_scroll(device) == 0) return;
        const current = c.libinput_device_config_scroll_get_natural_scroll_enabled(device);
        if (want != current) {
            _ = c.libinput_device_config_scroll_set_natural_scroll_enabled(device, want);
        }
    }
};

pub const LeftHanded = enum {
    disabled,
    enabled,

    pub fn apply(left_handed: LeftHanded, device: *c.libinput_device) void {
        const want: c_int = switch (left_handed) {
            .disabled => 0,
            .enabled => 1,
        };
        if (c.libinput_device_config_left_handed_is_available(device) == 0) return;
        const current = c.libinput_device_config_left_handed_get(device);
        if (want != current) {
            _ = c.libinput_device_config_left_handed_set(device, want);
        }
    }
};

pub const TapState = enum {
    disabled,
    enabled,

    pub fn apply(tap_state: TapState, device: *c.libinput_device) void {
        const want = @intToEnum(c.libinput_config_tap_state, switch (tap_state) {
            .disabled => c.LIBINPUT_CONFIG_TAP_DISABLED,
            .enabled => c.LIBINPUT_CONFIG_TAP_ENABLED,
        });
        if (c.libinput_device_config_tap_get_finger_count(device) <= 0) return;
        const current = c.libinput_device_config_tap_get_enabled(device);
        if (want != current) {
            _ = c.libinput_device_config_tap_set_enabled(device, want);
        }
    }
};

pub const TapButtonMap = enum {
    @"left-middle-right",
    @"left-right-middle",

    pub fn apply(tap_button_map: TapButtonMap, device: *c.libinput_device) void {
        const want = @intToEnum(c.libinput_config_tap_button_map, switch (tap_button_map) {
            .@"left-right-middle" => c.LIBINPUT_CONFIG_TAP_MAP_LRM,
            .@"left-middle-right" => c.LIBINPUT_CONFIG_TAP_MAP_LMR,
        });
        if (c.libinput_device_config_tap_get_finger_count(device) <= 0) return;
        const current = c.libinput_device_config_tap_get_button_map(device);
        if (want != current) {
            _ = c.libinput_device_config_tap_set_button_map(device, want);
        }
    }
};

pub const PointerAccel = struct {
    value: f32,

    pub fn apply(pointer_accel: PointerAccel, device: *c.libinput_device) void {
        if (c.libinput_device_config_accel_is_available(device) == 0) return;
        if (c.libinput_device_config_accel_get_speed(device) != pointer_accel.value) {
            _ = c.libinput_device_config_accel_set_speed(device, pointer_accel.value);
        }
    }
};

pub const ScrollMethod = enum {
    none,
    @"two-finger",
    edge,
    button,

    pub fn apply(scroll_method: ScrollMethod, device: *c.libinput_device) void {
        const want = @intToEnum(c.libinput_config_scroll_method, switch (scroll_method) {
            .none => c.LIBINPUT_CONFIG_SCROLL_NO_SCROLL,
            .@"two-finger" => c.LIBINPUT_CONFIG_SCROLL_2FG,
            .edge => c.LIBINPUT_CONFIG_SCROLL_EDGE,
            .button => c.LIBINPUT_CONFIG_SCROLL_ON_BUTTON_DOWN,
        });
        const supports = c.libinput_device_config_scroll_get_methods(device);
        if (supports & @intCast(u32, @enumToInt(want)) == 0) return;
        _ = c.libinput_device_config_scroll_set_method(device, want);
    }
};

pub const ScrollButton = struct {
    button: u32,

    pub fn apply(scroll_button: ScrollButton, device: *c.libinput_device) void {
        const supports = c.libinput_device_config_scroll_get_methods(device);
        if (supports & ~@intCast(u32, c.LIBINPUT_CONFIG_SCROLL_NO_SCROLL) == 0) return;
        _ = c.libinput_device_config_scroll_set_button(device, scroll_button.button);
    }
};

identifier: []const u8,

event_state: ?EventState = null,
accel_profile: ?AccelProfile = null,
click_method: ?ClickMethod = null,
drag_state: ?DragState = null,
drag_lock: ?DragLock = null,
dwt_state: ?DwtState = null,
middle_emulation: ?MiddleEmulation = null,
natural_scroll: ?NaturalScroll = null,
left_handed: ?LeftHanded = null,
tap_state: ?TapState = null,
tap_button_map: ?TapButtonMap = null,
pointer_accel: ?PointerAccel = null,
scroll_method: ?ScrollMethod = null,
scroll_button: ?ScrollButton = null,

pub fn deinit(self: *Self) void {
    util.gpa.free(self.identifier);
}

pub fn apply(self: *Self, device: *InputDevice) void {
    const libinput_device = @ptrCast(
        *c.libinput_device,
        device.device.getLibinputDevice() orelse return,
    );
    log.debug("applying input configuration to device: {s}", .{device.identifier});
    if (self.event_state) |setting| setting.apply(libinput_device);
    if (self.accel_profile) |setting| setting.apply(libinput_device);
    if (self.click_method) |setting| setting.apply(libinput_device);
    if (self.drag_state) |setting| setting.apply(libinput_device);
    if (self.drag_lock) |setting| setting.apply(libinput_device);
    if (self.dwt_state) |setting| setting.apply(libinput_device);
    if (self.middle_emulation) |setting| setting.apply(libinput_device);
    if (self.natural_scroll) |setting| setting.apply(libinput_device);
    if (self.left_handed) |setting| setting.apply(libinput_device);
    if (self.pointer_accel) |setting| setting.apply(libinput_device);
    if (self.scroll_button) |setting| setting.apply(libinput_device);
    if (self.scroll_method) |setting| setting.apply(libinput_device);
    if (self.tap_state) |setting| setting.apply(libinput_device);
    if (self.tap_button_map) |setting| setting.apply(libinput_device);
}
