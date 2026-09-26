const Self = @This();

const std = @import("std");
const mem = std.mem;
const log = std.log.scoped(.window_rule);

const mvzr = @import("mvzr");

const kwm = @import("kwm");

const Pattern = @import("pattern.zig");


pub const Dimension = struct {
    width: i32,
    height: i32,
};


title: ?Pattern = null,
app_id: ?Pattern = null,

tag: ?u32 = null,
output: ?Pattern = null,
floating: ?bool = null,
dimension: ?Dimension = null,
decoration: ?kwm.WindowDecoration = null,
is_terminal: ?bool = null,
disable_swallow: ?bool = null,
scroller_mfact: ?f32 = null,
attach_mode: ?kwm.WindowAttachMode = null,


pub fn match(self: *const Self, app_id: ?[]const u8, title: ?[]const u8) bool {
    if (self.app_id) |pattern| {
        log.debug("try match app_id: `{s}` with {*}({*}: `{s}`)", .{ app_id orelse "null", self, &pattern, pattern.str });

        if (!pattern.is_match(app_id)) return false;
    }

    if (self.title) |pattern| {
        log.debug("try match title: `{s}` with {*}({*}: `{s}`)", .{ title orelse "null", self, &pattern, pattern.str });

        if (!pattern.is_match(title)) return false;
    }

    return true;
}


const testing = std.testing;

test "window rule: requires both app_id and title to match" {
    const r: Self = .{
        .app_id = .{ .str = "firefox" },
        .title = .{ .str = "Mozilla Firefox" },
    };
    try testing.expect(r.match("firefox", "Mozilla Firefox"));
    try testing.expect(!r.match("chromium", "Mozilla Firefox"));
    try testing.expect(!r.match("firefox", "Other Title"));
}

test "window rule: absent patterns match anything" {
    const r: Self = .{};
    try testing.expect(r.match(null, null));
    try testing.expect(r.match("any.app", "any title"));
}

test "window rule: match_null matches missing field" {
    const r: Self = .{ .app_id = .{ .str = "ghost", .match_null = true } };
    try testing.expect(r.match(null, "t"));
    try testing.expect(!r.match("other", "t"));
}
