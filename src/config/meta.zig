const std = @import("std");
const mem = std.mem;
const meta = std.meta;
const Type = std.builtin.Type;

const constants = @import("constants.zig");


// turn packed struct to normal struct
pub fn unpacked(comptime T: type) type {
    const info = @typeInfo(T).@"struct";
    const fields = info.fields;
    var len: usize = 0;
    var names: [fields.len][]const u8 = undefined;
    var types: [fields.len]type = undefined;
    var attrs: [fields.len]Type.StructField.Attributes = undefined;
    for (fields) |field| {
        if (field.name[0] == '_') continue;

        names[len] = field.name;
        types[len] = field.@"type";
        attrs[len] = Type.StructField.Attributes {
            .@"comptime" = field.is_comptime,
            .@"align" = field.alignment,
            .default_value_ptr = field.default_value_ptr,
        };
        len += 1;
    }

    return @Struct(
        .auto,
        null,
        names[0..len],
        types[0..len],
        attrs[0..len]
    );
}


pub fn add_default(comptime T: type, comptime object: T) type {
    switch (@typeInfo(T)) {
        .@"struct" => |info| {
            const len = info.fields.len;
            var names: [len][]const u8 = undefined;
            var types: [len]type = undefined;
            var attrs: [len]Type.StructField.Attributes = undefined;

            for (0.., info.fields) |i, field| {
                const new_T = add_default(field.type, @field(object, field.name));
                const default: new_T = switch (@typeInfo(new_T)) {
                    .@"struct" => .{},
                    .optional => |optional_info| switch (@typeInfo(optional_info.child)) {
                        .@"struct" => if (@field(object, field.name)) |_| .{} else null,
                        else => @field(object, field.name),
                    },
                    else => @field(object, field.name),
                };

                names[i] = field.name;
                types[i] = new_T;
                attrs[i] = Type.StructField.Attributes {
                    .@"comptime" = field.is_comptime,
                    .@"align" = field.alignment,
                    .default_value_ptr = @ptrCast(&default),
                };
            }

            return @Struct(info.layout, info.backing_integer, &names, &types, &attrs);
        },
        .optional => |info| return
            if (object) |obj| ?add_default(info.child, obj)
            else T,
        else => return T,
    }
}


pub fn enum_struct(comptime E: type, comptime T: type) type {
    const info = @typeInfo(E).@"enum";

    const len = info.fields.len;
    var names: [len][]const u8 = undefined;
    var types: [len]type = undefined;
    var attrs: [len]Type.StructField.Attributes = undefined;
    for (0.., info.fields) |i, field| {
        names[i] = field.name;
        types[i] = T;
        attrs[i] = Type.StructField.Attributes {
            .@"comptime" = false,
            .@"align" = @alignOf(T),
            .default_value_ptr = switch (@typeInfo(T)) {
                .optional => blk: {
                    const default_value: T = null;
                    break :blk &default_value;
                },
                else => null,
            },
        };
    }

    const S = @Struct(.auto, null, &names, &types, &attrs);

    const Getter = struct {
        pub const instance: @This() = .{};
        pub fn get(self: *const @This(), e: E) T {
            return switch (e) {
                inline else => |v| @field(
                    @as(*const S, @ptrCast(@alignCast(self))),
                    @tagName(v)
                ),
            };
        }
    };

    return @Struct(
        .auto,
        null,
        &(.{ "getter" } ++ names),
        &(.{ Getter } ++ types),
        &(.{
            Type.StructField.Attributes {
                .@"comptime" = false,
                .@"align" = @alignOf(T),
                .default_value_ptr = &Getter.instance
            }
        } ++ attrs)
    );
}


pub fn make_optional(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .optional => T,
        .@"struct" => ?make_fields_optional(T),
        else => ?T,
    };
}


pub fn make_fields_optional(comptime T: type) type {
    const info = @typeInfo(T).@"struct";

    const len = info.fields.len;
    var names: [len][]const u8 = undefined;
    var types: [len]type = undefined;
    var attrs: [len]Type.StructField.Attributes = undefined;
    for (0.., info.fields) |i, field| {
        const new_T = make_optional(field.type);
        const default_value: new_T = null;
        names[i] = field.name;
        types[i] = new_T;
        attrs[i] = Type.StructField.Attributes {
            .@"comptime" = false,
            .@"align" = @alignOf(new_T),
            .default_value_ptr = &default_value,
        };
    }

    return @Struct(.auto, null, &names, &types, &attrs);
}


pub fn field_mask(comptime T: type) type {
    const info = @typeInfo(T).@"struct";

    const len = info.fields.len;
    var names: [len][]const u8 = undefined;
    var attrs: [len]Type.StructField.Attributes = undefined;
    for (0.., info.fields) |i, field| {
        const default_value = false;
        names[i] = field.name;
        attrs[i] = Type.StructField.Attributes {
            .@"comptime" = false,
            .@"align" = @alignOf(bool),
            .default_value_ptr = &default_value,
        };
    }

    return @Struct(.auto, null, &names, &@splat(bool), &attrs);
}


pub fn override(base: anytype, new: anytype) @TypeOf(base) {
    const T = @TypeOf(base);
    var result: T = undefined;
    inline for (@typeInfo(T).@"struct".fields) |field_info| {
        const new_field = @field(new, field_info.name);
        const base_field = @field(base, field_info.name);
        @field(result, field_info.name) =
            if (new_field == null) base_field
            else switch (@typeInfo(field_info.type)) {
                .@"struct" => override(base_field, new_field.?),
                else => new_field.?,
            };
    }
    return result;
}


pub fn deep_equal(comptime T: type, a: *const T, b: *const T) bool {
    return switch (@typeInfo(T)) {
        .@"struct" => |info| blk: {
            inline for (info.fields) |field| {
                if (!deep_equal(
                    field.type,
                    @ptrCast(&@field(a, field.name)),
                    @ptrCast(&@field(b, field.name)),
                )) {
                    break :blk false;
                }
            }
            break :blk true;
        },
        .array => |info| blk: {
            if (a.len != b.len) break :blk false;

            for (a.*, b.*) |elem_a, elem_b| {
                if (!deep_equal(info.child, &elem_a, &elem_b)) {
                    break :blk false;
                }
            }

            break :blk true;
        },
        .pointer => |info| switch (info.size) {
            .slice => blk: {
                if (a.len != b.len) break :blk false;

                for (a.*, b.*) |elem_a, elem_b| {
                    if (!deep_equal(info.child, &elem_a, &elem_b)) {
                        break :blk false;
                    }
                }

                break :blk true;
            },
            else => unreachable,
        },
        .@"union" => |info| blk: {
            if (info.tag_type != null) {
                const tag_a = meta.activeTag(a.*);
                const tag_b = meta.activeTag(b.*);

                if (tag_a != tag_b) break :blk false;

                inline for (info.fields) |field| {
                    if (@field(T, field.name) == tag_a) {
                        break :blk deep_equal(
                            field.type,
                            &@field(a.*, field.name),
                            &@field(b.*, field.name),
                        );
                    }
                }
                unreachable;
            } else unreachable;
        },
        .optional => |info|
            if (a.* == null and b.* == null) true
            else if (a.* == null or b.* == null) false
            else deep_equal(info.child, &a.*.?, &b.*.?),
        .float => @abs(a.*-b.*) < 1e-9,
        .int, .bool, .@"enum" => a.* == b.*,
        .void => true,
        else => unreachable,
    };
}


pub fn zon_free(gpa: mem.Allocator, value: anytype, default: ?*const @TypeOf(value)) void {
    const Value = @TypeOf(value);
    const info = @typeInfo(Value);

    switch (info) {
        .bool, .int, .float, .@"enum" => {},
        .pointer => |pointer| {
            switch (pointer.size) {
                .one => {
                    if (default) |ptr| {
                        if (value == ptr.*) return;
                    }

                    zon_free(gpa, value.*);
                    gpa.destroy(value);
                },
                .slice => {
                    if (default) |ptr| {
                        if (value.ptr == ptr.ptr) return;
                    }

                    for (value) |item| {
                        zon_free(gpa, item, null);
                    }
                    gpa.free(value);
                },
                .many, .c => comptime unreachable,
            }
        },
        .array => for (0.., value) |i, item| {
            zon_free(
                gpa,
                item,
                if (default) |ptr| &ptr.*[i] else null
            );
        },
        .@"struct" => |@"struct"| inline for (@"struct".fields) |field| {
            zon_free(
                gpa,
                @field(value, field.name),
                if (default) |ptr|
                    @ptrCast(@alignCast(&@field(ptr.*, field.name)))
                else
                    if (field.default_value_ptr) |ptr| @ptrCast(@alignCast(ptr))
                    else null
            );
        },
        .@"union" => |@"union"| if (@"union".tag_type == null) {
            if (comptime requiresAllocator(Value)) unreachable;
        } else switch (value) {
            inline else => |_, tag| {
                zon_free(
                    gpa,
                    @field(value, @tagName(tag)),
                    if (default) |ptr| (
                        if (meta.activeTag(ptr.*) == tag)
                            &@field(ptr.*, @tagName(tag))
                        else null
                    )
                    else null
                );
            },
        },
        .optional => if (value) |some| {
            zon_free(
                gpa,
                some,
                if (default) |ptr| (
                    if (ptr.* != null) &ptr.*.?
                    else null
                )
                else null
            );
        },
        .vector => |vector| for (0..vector.len) |i|
            zon_free(
                gpa,
                value[i],
                if (default) |ptr| &ptr.*[i] else null
            ),
        .void => {},
        else => comptime unreachable,
    }
}

fn requiresAllocator(T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => true,
        .array => |array| return array.len > 0 and requiresAllocator(array.child),
        .@"struct" => |@"struct"| inline for (@"struct".fields) |field| {
            if (requiresAllocator(field.type)) {
                break true;
            }
        } else false,
        .@"union" => |@"union"| inline for (@"union".fields) |field| {
            if (requiresAllocator(field.type)) {
                break true;
            }
        } else false,
        .optional => |optional| requiresAllocator(optional.child),
        .vector => |vector| return vector.len > 0 and requiresAllocator(vector.child),
        else => false,
    };
}


const testing = std.testing;

test "deep_equal: strings and primitives" {
    const hello: []const u8 = "hello";
    const hello2: []const u8 = "hello";
    const hallo: []const u8 = "hallo";
    const shorter: []const u8 = "hell";
    try testing.expect(deep_equal([]const u8, &hello, &hello2));
    try testing.expect(!deep_equal([]const u8, &hello, &hallo));
    try testing.expect(!deep_equal([]const u8, &hello, &shorter));

    const yes = true;
    const no = false;
    try testing.expect(deep_equal(bool, &yes, &yes));
    try testing.expect(!deep_equal(bool, &yes, &no));

    const n1: u32 = 42;
    const n2: u32 = 42;
    const n3: u32 = 43;
    try testing.expect(deep_equal(u32, &n1, &n2));
    try testing.expect(!deep_equal(u32, &n1, &n3));
}

test "deep_equal: optionals" {
    const a: ?u32 = 1;
    const b: ?u32 = 1;
    const c: ?u32 = 2;
    const n1: ?u32 = null;
    const n2: ?u32 = null;
    try testing.expect(deep_equal(?u32, &a, &b));
    try testing.expect(!deep_equal(?u32, &a, &c));
    try testing.expect(deep_equal(?u32, &n1, &n2));
    try testing.expect(!deep_equal(?u32, &a, &n1));
}

test "deep_equal: tagged unions compare tag and payload" {
    const U = union(enum) { none, num: u32, text: []const u8 };
    const a: U = .{ .num = 5 };
    const b: U = .{ .num = 5 };
    const c: U = .{ .num = 6 };
    const d: U = .{ .text = "5" };
    const e: U = .none;
    const f: U = .none;
    try testing.expect(deep_equal(U, &a, &b));
    try testing.expect(!deep_equal(U, &a, &c));
    try testing.expect(!deep_equal(U, &a, &d));
    try testing.expect(deep_equal(U, &e, &f));
}

test "deep_equal: nested structs, arrays and floats" {
    const S = struct { name: []const u8, n: u8, opt: ?i32 };
    const a: S = .{ .name = "x", .n = 1, .opt = null };
    const b: S = .{ .name = "x", .n = 1, .opt = null };
    const c: S = .{ .name = "x", .n = 2, .opt = null };
    try testing.expect(deep_equal(S, &a, &b));
    try testing.expect(!deep_equal(S, &a, &c));

    const arr1 = [3]u8{ 1, 2, 3 };
    const arr2 = [3]u8{ 1, 2, 3 };
    const arr3 = [3]u8{ 1, 2, 4 };
    try testing.expect(deep_equal([3]u8, &arr1, &arr2));
    try testing.expect(!deep_equal([3]u8, &arr1, &arr3));

    const f1: f32 = 0.5;
    const f2: f32 = 0.5;
    const f3: f32 = 0.75;
    try testing.expect(deep_equal(f32, &f1, &f2));
    try testing.expect(!deep_equal(f32, &f1, &f3));
}
