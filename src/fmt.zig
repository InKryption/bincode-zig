//! Procedures for encoding and decoding typed data.

pub const byte = @import("fmt/byte.zig");
pub const int = @import("fmt/int.zig");
pub const float = @import("fmt/float.zig");
pub const optional = @import("fmt/optional.zig");
pub const list = @import("fmt/list.zig");
pub const tuple = @import("fmt/tuple.zig");
pub const enumeration = @import("fmt/enumeration.zig");
pub const tag_union = @import("fmt/tag_union.zig");

pub const array_list = @import("fmt/array_list.zig");
pub const array_hash_map = @import("fmt/array_hash_map.zig");

pub fn encode(
    /// Must allow `DataFormat(@TypeOf(ctx))`.
    ctx: anytype,
    int_config: bincode.int.Config,
    /// `*const T`
    ///
    /// Pointer to the value to be encoded into the `writer` stream.
    value: anytype,
    /// `std.io.GenericWriter(...)` | `std.io.AnyWriter`
    ///
    /// The stream that the encoded data will be written to.
    writer: anytype,
) (DataFormat(@TypeOf(ctx)).EncodeError(@TypeOf(value.*)) || @TypeOf(writer).Error)!void {
    @setEvalBranchQuota(10_000); // generous baseline for minimally complex data structures
    if (@TypeOf(writer) != std.io.AnyWriter) {
        const any_writer: std.io.AnyWriter = writer.any();
        return @errorCast(encode(ctx, int_config, value, any_writer));
    }
    return dataFormat(ctx).encode(int_config, value, writer);
}

pub fn decode(
    /// Must allow `DataFormat(@TypeOf(ctx))`.
    ctx: anytype,
    int_config: bincode.int.Config,
    /// `*T`
    ///
    /// Pointer to the result location of the decoded data.
    value: anytype,
    /// `std.io.GenericReader(...)` | `std.io.AnyReader`
    ///
    /// The stream that the data will be read and decoded from.
    reader: anytype,
    allocator: std.mem.Allocator,
) (DataFormat(@TypeOf(ctx)).DecodeError(@TypeOf(value.*)) || @TypeOf(reader).Error)!void {
    @setEvalBranchQuota(10_000); // generous baseline for minimally complex data structures
    if (@TypeOf(reader) != std.io.AnyReader) {
        const any_reader: std.io.AnyReader = reader.any();
        return @errorCast(decode(ctx, int_config, value, any_reader, allocator));
    }
    return dataFormat(ctx).decode(int_config, value, reader, allocator);
}

pub fn decodeCopy(
    ctx: anytype,
    int_config: bincode.int.Config,
    /// Type of the data to decode.
    comptime T: type,
    /// `std.io.GenericReader(...)` | `std.io.AnyReader`
    ///
    /// The stream that the data will be read and decoded from.
    reader: anytype,
    allocator: std.mem.Allocator,
) (DataFormat(@TypeOf(ctx)).DecodeError(T) || @TypeOf(reader).Error)!T {
    @setEvalBranchQuota(10_000); // generous baseline for minimally complex data structures
    var value: T = undefined;
    try decode(ctx, int_config, &value, reader, allocator);
    return value;
}

pub fn freeDecoded(
    /// Must allow `DataFormat(@TypeOf(ctx))`.
    ctx: anytype,
    int_config: bincode.int.Config,
    /// `*const T`
    ///
    /// Pointer to the decoded data that must be deinitialised.
    value: anytype,
    allocator: std.mem.Allocator,
) void {
    return dataFormat(ctx).freeDecoded(int_config, value, allocator);
}

pub inline fn dataFormat(ctx: anytype) DataFormat(@TypeOf(ctx)) {
    if (@TypeOf(ctx) == DataFormat(@TypeOf(ctx))) return ctx;
    return .{ .ctx = ctx };
}
pub fn DataFormat(comptime Ctx: type) type {
    const CtxNamespace = switch (@typeInfo(Ctx)) {
        .Pointer => |pointer| pointer.child,
        else => Ctx,
    };

    if (Ctx == CtxNamespace and
        @hasDecl(Ctx, "Context") and
        @TypeOf(Ctx.Context) == type and
        DataFormat(Ctx.Context) == Ctx //
    ) return Ctx;

    return struct {
        ctx: Context,
        const Self = @This();

        pub const Context = Ctx;

        /// `CtxNamespace.EncodeError` must either be an error set,
        /// or a function that returns an error set based on `Value`.
        pub fn EncodeError(comptime Value: type) type {
            if (@sizeOf(Value) == 0) return error{};
            if (@TypeOf(CtxNamespace.EncodeError) == type) return CtxNamespace.EncodeError;
            return CtxNamespace.EncodeError(Value);
        }
        pub inline fn encode(
            cdf: Self,
            int_config: bincode.int.Config,
            /// `*const T`
            ///
            /// Pointer to the value to be encoded into the `writer` stream.
            value: anytype,
            /// `std.io.GenericWriter(...)` | `std.io.AnyWriter`
            ///
            /// The stream that the encoded data will be written to.
            writer: anytype,
        ) (EncodeError(@TypeOf(value.*)) || @TypeOf(writer).Error)!void {
            @setEvalBranchQuota(1000);
            make_const: {
                const const_value = makeConstPtr(value);
                if (@TypeOf(const_value) == @TypeOf(value)) break :make_const;
                return cdf.encode(int_config, const_value, writer);
            }

            const ptr_info = @typeInfo(@TypeOf(value)).Pointer;
            if (ptr_info.size != .One) {
                @compileError("Expected `*const T`, got " ++ @typeName(@TypeOf(value)));
            }
            if (@sizeOf(@TypeOf(value.*)) == 0) return;
            return cdf.ctx.encode(int_config, value, writer);
        }

        /// `CtxNamespace.DecodeError` must either be an error set,
        /// or a function that returns an error set based on `Value`.
        pub fn DecodeError(comptime Value: type) type {
            if (@sizeOf(Value) == 0) return error{};
            if (@TypeOf(CtxNamespace.DecodeError) == type) return CtxNamespace.DecodeError;
            return CtxNamespace.DecodeError(Value);
        }
        pub inline fn decode(
            cdf: Self,
            int_config: bincode.int.Config,
            /// `*T`
            ///
            /// Pointer to the result location of the decoded data.
            /// Callee should assume `value.* = undefined`.
            value: anytype,
            /// `std.io.GenericReader(...)` | `std.io.AnyReader`
            ///
            /// The stream that the data will be read and decoded from.
            reader: anytype,
            allocator: std.mem.Allocator,
        ) (DecodeError(@TypeOf(value.*)) || @TypeOf(reader).Error)!void {
            @setEvalBranchQuota(1000);
            const ptr_info = @typeInfo(@TypeOf(value)).Pointer;
            if (ptr_info.size != .One) {
                @compileError("Expected `*T`, got " ++ @typeName(@TypeOf(value)));
            }
            if (@sizeOf(@TypeOf(value.*)) == 0) return;
            value.* = undefined;
            return cdf.ctx.decode(int_config, value, reader, allocator);
        }

        pub inline fn freeDecoded(
            cdf: Self,
            int_config: bincode.int.Config,
            /// `*const T`
            ///
            /// Pointer to the decoded data that must be deinitialised.
            value: anytype,
            allocator: std.mem.Allocator,
        ) void {
            @setEvalBranchQuota(1000);
            make_const: {
                const const_value = makeConstPtr(value);
                if (@TypeOf(const_value) == @TypeOf(value)) break :make_const;
                return cdf.freeDecoded(int_config, const_value, allocator);
            }

            if (@sizeOf(@TypeOf(value.*)) == 0) return;
            return cdf.ctx.freeDecoded(int_config, value, allocator);
        }

        fn makeConstPtr(ptr: anytype) @Type(.{ .Pointer = blk: {
            var ptr_info = @typeInfo(@TypeOf(ptr)).Pointer;
            ptr_info.is_const = true;
            break :blk ptr_info;
        } }) {
            return ptr;
        }
    };
}

comptime {
    const A = struct {};
    assert(DataFormat(DataFormat(A)) == DataFormat(A));
}

test "encode/decode tuple of things" {
    var buffer: [4096 * 16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    const writer = fbs.writer();
    const reader = fbs.reader();

    const T = struct {
        a: i8,
        b: i32,
        c: *const [3]u8,
        d: []const u16,
        e: [2]u64,
        f: @Vector(4, u16),
        g: ?[]const u16,
        h: ?u64,
        i: [3]FooBarBaz,
        j: []const []const u8,
        k: enum(u1) { fizz, buzz },
        l: struct { f32, f64 },
        m: [2]bool,

        const FooBarBaz = union(enum) {
            foo: u32,
            bar,
            baz: [2]u8,

            const union_fmt = tag_union.format(.{
                .foo = int.format(.unrounded),
                .baz = list.format(byte.format, .encode_len_based_on_type),
            });
        };

        const tuple_fmt = tuple.format(.{
            .a = byte.format,
            .b = int.format(.unrounded),
            .c = list.format(byte.format, .encode_len_based_on_type),
            .d = list.format(int.format(.unrounded), .encode_len_based_on_type),
            .e = list.format(int.format(.unrounded), .encode_len_based_on_type),
            .f = list.format(int.format(.unrounded), .encode_len_based_on_type),
            .g = optional.format(list.format(int.format(.unrounded), .encode_len_based_on_type)),
            .h = optional.format(int.format(.unrounded)),
            .i = list.format(FooBarBaz.union_fmt, .encode_len_based_on_type),
            .j = list.format(list.format(byte.format, .encode_len_always), .encode_len_always),
            .k = enumeration.format(.tag_value),
            .l = tuple.format(.{ float.format, float.format }),
            .m = list.format(byte.format, .encode_len_based_on_type),
        });
    };

    const int_config: bincode.int.Config = .{
        .endian = .little,
        .int_encoding = .varint,
    };
    const value: T = .{
        .a = -127,
        .b = 255,
        .c = &.{ 255, 255, 255 },
        .d = &.{ 123, 456, 789, 1011 },
        .e = .{ 6, 7 },
        .f = .{ 32, 33, 34, 75 },
        .g = &.{ 1, 2, 3, 4, 5, 6 },
        .h = null,
        .i = .{
            .{ .foo = 768 },
            .bar,
            .{ .baz = "ao".* },
        },
        .j = &.{ "foo", "bar", "baz" },
        .k = .fizz,
        .l = .{ 1.234, 56.789 },
        .m = .{ false, true },
    };
    try encode(T.tuple_fmt, int_config, &value, writer);

    fbs.reset();

    const decoded = try decodeCopy(T.tuple_fmt, int_config, T, reader, std.testing.allocator);
    defer freeDecoded(T.tuple_fmt, int_config, &decoded, std.testing.allocator);

    try std.testing.expectEqualDeep(value, decoded);
}

test array_list {
    var buffer: [4096 * 16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    const writer = fbs.writer();
    const reader = fbs.reader();

    const int_config: bincode.int.Config = .{
        .endian = .little,
        .int_encoding = .varint,
    };

    const elem_format = tuple.format(.{ float.format, byte.format, list.format(byte.format, .encode_len_based_on_type) });
    var data = std.ArrayList(struct { f64, bool, []const u8 }).init(std.testing.allocator);
    defer data.deinit();

    try data.appendSlice(&.{
        .{ 0.1, true, "foo" },
        .{ 0.34441, true, "bar" },
        .{ -126634.3, false, "baz" },
        .{ -1.001, true, "fizz" },
        .{ 0, false, "buzz" },
    });

    try encode(array_list.format(elem_format), int_config, &data, writer);

    fbs.reset();

    const decoded = try decodeCopy(array_list.format(elem_format), int_config, std.ArrayList(struct { f64, bool, []const u8 }), reader, std.testing.allocator);
    defer freeDecoded(array_list.format(elem_format), int_config, &decoded, std.testing.allocator);

    try std.testing.expectEqualDeep(data.items, decoded.items);
}

test array_hash_map {
    var buffer: [4096 * 16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    const writer = fbs.writer();
    const reader = fbs.reader();

    const int_config: bincode.int.Config = .{
        .endian = .little,
        .int_encoding = .varint,
    };

    const key_fmt = list.format(byte.format, .encode_len_based_on_type);
    const val_fmt = list.format(int.format(.unrounded), .encode_len_based_on_type);
    var data = std.StringArrayHashMap([]const u32).init(std.testing.allocator);
    defer data.deinit();

    try data.put("foo", &.{ 32, 33 });
    try data.put("bar", &.{ 111111, 111112, 111113, 111114 });
    try data.put("baz", &.{ 127, 256, 8 });
    try data.put("fizz", &.{ 1234, 4321, 123, 321, 12, 21, 1 });
    try data.put("buzz", &.{});

    try encode(array_hash_map.format(key_fmt, val_fmt, .err_on_duplicate), int_config, &data, writer);

    fbs.reset();

    const decoded = try decodeCopy(array_hash_map.format(key_fmt, val_fmt, .err_on_duplicate), int_config, std.StringArrayHashMap([]const u32), reader, std.testing.allocator);
    defer freeDecoded(array_hash_map.format(key_fmt, val_fmt, .err_on_duplicate), int_config, &decoded, std.testing.allocator);

    try std.testing.expectEqualDeep(data.keys(), decoded.keys());
    try std.testing.expectEqualDeep(data.values(), decoded.values());
}

const std = @import("std");
const assert = std.debug.assert;

const builtin = @import("builtin");

const bincode = @import("bincode.zig");
