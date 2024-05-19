pub const zigzag = @import("int/zigzag.zig");
pub const varint = @import("int/varint.zig");

comptime {
    _ = zigzag;
    _ = varint;
}

pub const Encoding = enum {
    varint,
    fixint,
};

pub const Config = struct {
    endian: std.builtin.Endian,
    int_encoding: Encoding,
};

pub const Type = enum {
    //! This does not include `u8`/`i8`, because byte-sized integers
    //! should always be encoded directly as bytes, irrespective of
    //! the encoding of integers.

    u16,
    i16,

    u32,
    i32,

    u64,
    i64,

    u128,
    i128,

    usize,
    isize,

    pub fn fromTypeRounded(comptime T: type) ?Type {
        if (fromType(T)) |int_type| return int_type;
        const info = @typeInfo(T).Int;
        const Rounded = std.meta.Int(info.signedness, std.math.ceilPowerOfTwo(u16, info.bits) catch return null);
        return fromType(Rounded);
    }

    pub fn fromType(comptime T: type) ?Type {
        return switch (T) {
            ToType(.u16) => .u16,
            ToType(.i16) => .i16,

            ToType(.u32) => .u32,
            ToType(.i32) => .i32,

            ToType(.u64) => .u64,
            ToType(.i64) => .i64,

            ToType(.u128) => .u128,
            ToType(.i128) => .i128,

            ToType(.usize) => .usize,
            ToType(.isize) => .isize,

            else => null,
        };
    }

    pub fn ToType(comptime int_type: Type) type {
        return switch (int_type) {
            .u16 => u16,
            .i16 => i16,

            .u32 => u32,
            .i32 => i32,

            .u64 => u64,
            .i64 => i64,

            .u128 => u128,
            .i128 => i128,

            .usize => usize,
            .isize => isize,
        };
    }

    pub fn EncodedType(comptime int_type: Type) type {
        return switch (int_type) {
            .usize => u64,
            .isize => i64,
            else => |tag| tag.ToType(),
        };
    }
};

pub fn writeInt(
    writer: anytype,
    config: Config,
    comptime int_type: Type,
    value: int_type.ToType(),
) @TypeOf(writer).Error!void {
    if (@TypeOf(writer) != std.io.AnyWriter) {
        const any_writer: std.io.AnyWriter = writer.any();
        return @errorCast(writeInt(any_writer, config, int_type, value));
    }

    const T = int_type.EncodedType();
    const int: T = value;
    const info = @typeInfo(T).Int;

    switch (config.int_encoding) {
        .varint => {
            var buffer: [varint.ValueLayout.max.encodedLength()]u8 = undefined;

            const unsigned = switch (info.signedness) {
                .signed => zigzag.toUnsigned(T, int),
                .unsigned => int,
            };
            const layout = varint.encodeBuffer(@TypeOf(unsigned), unsigned, buffer[0..], config.endian);
            try writer.writeAll(buffer[0..layout.encodedLength()]);
        },
        .fixint => {
            const Unsigned = std.meta.Int(.unsigned, @bitSizeOf(T));
            try writer.writeInt(Unsigned, @bitCast(int), config.endian);
        },
    }
}

pub const ReadIntError = error{
    /// The flag byte held an invalid value.
    InvalidFlagByte,
    /// The result overflowed, meaning the type being deserialized into
    /// doesn't match the type that the source was serialized from.
    TypeMismatch,
    /// Encountered EOF before acquiring all the bytes.
    PrematureEof,
};
pub inline fn readInt(
    reader: anytype,
    config: Config,
    comptime int_type: Type,
) (@TypeOf(reader).Error || ReadIntError)!int_type.ToType() {
    if (@TypeOf(reader) != std.io.AnyReader) {
        const any_writer: std.io.AnyReader = reader.any();
        return @errorCast(readInt(any_writer, config, int_type));
    }

    const T = int_type.EncodedType();
    const info = @typeInfo(T).Int;
    switch (config.int_encoding) {
        .varint => {
            const flag_byte = try reader.readByte();
            const layout = varint.ValueLayout.fromFlagByte(flag_byte) orelse return ReadIntError.InvalidFlagByte;
            const Unsigned = std.meta.Int(.unsigned, info.bits);
            const unsigned: Unsigned = dec: {
                var buffer: [varint.ValueLayout.max.encodedLength()]u8 = undefined;
                const encoded = buffer[0..try reader.readAll(buffer[0 .. layout.encodedLength() - 1])];
                if (encoded.len != layout.encodedLength() - 1) {
                    return ReadIntError.PrematureEof;
                }
                const decoded = varint.decodeBuffer(flag_byte, encoded, config.endian);
                break :dec std.math.cast(Unsigned, decoded) orelse {
                    return ReadIntError.TypeMismatch;
                };
            };
            return switch (info.signedness) {
                .signed => zigzag.fromUnsigned(T, unsigned),
                .unsigned => unsigned,
            };
        },
        .fixint => {
            const Rounded = std.meta.Int(info.signedness, std.math.ceilPowerOfTwoAssert(u16, info.bits));
            const Unsigned = std.meta.Int(.unsigned, @bitSizeOf(Rounded));
            const unsigned: Unsigned = blk: {
                var buffer: [@sizeOf(T)]u8 = undefined;
                const bytes_read = try reader.readAll(&buffer);
                if (bytes_read != buffer.len) return ReadIntError.PrematureEof;
                assert(bytes_read == buffer.len);
                var unsigned: Unsigned = @bitCast(buffer);
                const native_endian = comptime builtin.cpu.arch.endian();
                if (config.endian != native_endian) {
                    unsigned = @byteSwap(unsigned);
                }
                break :blk unsigned;
            };
            const rounded: Rounded = @bitCast(unsigned);
            return std.math.cast(T, rounded) orelse return ReadIntError.TypeMismatch;
        },
    }
}

fn testWriteReadInt(config: Config, values: anytype) !void {
    const fbs_buffer = try std.testing.allocator.alloc(u8, varint.ValueLayout.max.encodedLength() * values.len);
    defer std.testing.allocator.free(fbs_buffer);

    var fbs = std.io.fixedBufferStream(fbs_buffer);

    const writer = fbs.writer();
    const reader = fbs.reader();

    switch (@typeInfo(@TypeOf(values))) {
        .Pointer, .Array, .Vector => //
        for (values) |value| try writeInt(writer, config, Type.fromTypeRounded(@TypeOf(value)).?, value),
        .Struct => inline //
        for (values) |value| try writeInt(writer, config, Type.fromTypeRounded(@TypeOf(value)).?, value),

        else => @compileError("Unsupported list type: " ++ @typeName(@TypeOf(values))),
    }

    fbs.reset();

    switch (@typeInfo(@TypeOf(values))) {
        .Pointer, .Array, .Vector => //
        for (values) |value| try std.testing.expectEqual(value, try readInt(reader, config, Type.fromTypeRounded(@TypeOf(value)).?)),
        .Struct => inline //
        for (values) |value| try std.testing.expectEqual(value, try readInt(reader, config, Type.fromTypeRounded(@TypeOf(value)).?)),

        else => @compileError("Unsupported list type: " ++ @typeName(@TypeOf(values))),
    }
}

test "writeInt & readInt" {
    for ([_]Config{
        .{ .int_encoding = .varint, .endian = .little },
        .{ .int_encoding = .fixint, .endian = .little },
        .{ .int_encoding = .varint, .endian = .big },
        .{ .int_encoding = .fixint, .endian = .big },
    }) |config| {
        try testWriteReadInt(config, .{
            @as(u9, 223),
            @as(u16, 10000),
            @as(i64, -1),
            @as(i32, 0xAbAbAb),
            @as(usize, 5325325),
        });
        try testWriteReadInt(config, [_]i32{
            128, -77777, 170, -1234567, 0xf00, 0xba7, 0xba2,
        });
    }
}

const std = @import("std");
const assert = std.debug.assert;

const builtin = @import("builtin");
