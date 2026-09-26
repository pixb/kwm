const Self = @This();

const std = @import("std");
const mem = std.mem;
const log = std.log.scoped(.pattern);

const mvzr = @import("mvzr");

str: []const u8,
regex: bool = false,
match_null: bool = false,

pub fn is_match(self: *const Self, haystack: ?[]const u8) bool {
    if (haystack == null) {
        log.debug("<{*}> matched null", .{ self });
        return self.match_null;
    }

    const matched = blk: {
        if (self.regex) {
            const pattern = mvzr.compile(self.str) orelse return false;
            break :blk pattern.isMatch(haystack.?);
        } else {
            break :blk mem.eql(u8, self.str, haystack.?);
        }
    };

    if (matched) {
        log.debug("<{*}> matched `{s}`", .{ self, haystack.? });
    }

    return matched;
}


const testing = std.testing;

test "pattern: literal match" {
    const p: Self = .{ .str = "firefox" };
    try testing.expect(p.is_match("firefox"));
    try testing.expect(!p.is_match("Firefox"));
    try testing.expect(!p.is_match("firefox-esr"));
    try testing.expect(!p.is_match(""));
    try testing.expect(!p.is_match(null));
}

test "pattern: literal does not interpret regex metacharacters" {
    const p: Self = .{ .str = "fire.*" };
    try testing.expect(p.is_match("fire.*"));
    try testing.expect(!p.is_match("firefox"));
}

test "pattern: regex match" {
    const p: Self = .{ .str = "fire.*", .regex = true };
    try testing.expect(p.is_match("firefox"));
    try testing.expect(p.is_match("firestorm"));
    try testing.expect(!p.is_match("chrome"));
}

test "pattern: match_null controls null haystack" {
    const with_null: Self = .{ .str = "x", .match_null = true };
    const without: Self = .{ .str = "x" };
    try testing.expect(with_null.is_match(null));
    try testing.expect(!without.is_match(null));
}
