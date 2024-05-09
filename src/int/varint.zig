//! Utilities for handling integers while using VarintEncoding.

pub const ValueLayout = enum {
    u8,
    u16,
    u32,
    u64,
    u128,

    pub const max: ValueLayout = .u128;

    pub fn encodedTypeBits(layout: ValueLayout) u16 {
        return switch (layout) {
            .u8 => 8,
            .u16 => 16,
            .u32 => 32,
            .u64 => 64,
            .u128 => 128,
        };
    }
    pub fn EncodedType(comptime layout: ValueLayout) type {
        return std.meta.Int(.unsigned, layout.encodedTypeBits());
    }

    pub const EncodedLength = std.math.IntFittingRange(1, 1 + @sizeOf(u128));
    /// Length of the encoded value, including the flag byte.
    pub fn encodedLength(layout: ValueLayout) EncodedLength {
        return @as(EncodedLength, 1) + switch (layout) {
            .u8 => @as(EncodedLength, 0),
            .u16 => @sizeOf(u16),
            .u32 => @sizeOf(u32),
            .u64 => @sizeOf(u64),
            .u128 => @sizeOf(u128),
        };
    }

    pub fn flagByte(layout: ValueLayout) ?u8 {
        return switch (layout) {
            .u8 => null,
            .u16 => 251,
            .u32 => 252,
            .u64 => 253,
            .u128 => 254,
        };
    }

    /// Returns null when `flag_byte == 255`.
    pub fn fromFlagByte(flag_byte: u8) ?ValueLayout {
        return switch (flag_byte) {
            0...251 - 1 => .u8,
            flagByte(.u16).? => .u16,
            flagByte(.u32).? => .u32,
            flagByte(.u64).? => .u64,
            flagByte(.u128).? => .u128,
            255 => null,
        };
    }

    pub fn fromValue(comptime T: type, value: T) ValueLayout {
        validateIntType(T);

        if (value < 251) return .u8;
        if (value < 1 << 16) return .u16;
        if (value < 1 << 32) return .u32;
        if (value < 1 << 64) return .u64;
        if (value < 1 << 128) return .u128;
        comptime unreachable;
    }
};

fn validateIntType(comptime T: type) void {
    comptime if (@typeInfo(T) != .Int or @typeInfo(T).Int.signedness != .unsigned) @compileError(
        "Expected an unsigned integer, got " ++ @typeName(T) ++ "",
    );
    comptime if (@bitSizeOf(T) > ValueLayout.max.encodedTypeBits()) @compileError(
        "Bit size type of " ++ @typeName(T) ++ " not suppported",
    );
}

/// Assumes that `buffer.len >= ValueLayout.fromValue(T, value).encodedLength()`
/// Writes to `bytes[0..ValueLayout.fromValue(T, value).encodedLength()]`.
pub fn encodeBuffer(
    comptime T: type,
    value: T,
    buffer: []u8,
    endian: std.builtin.Endian,
) ValueLayout {
    validateIntType(T);
    return switch (ValueLayout.fromValue(T, value)) {
        inline .u8, .u16, .u32, .u64, .u128 => |layout| blk: {
            const len = comptime layout.encodedLength();
            const flag_byte = (comptime layout.flagByte()) orelse {
                buffer[0..len].* = .{@intCast(value)};
                break :blk layout;
            };
            buffer[0] = flag_byte;
            std.mem.writeInt(layout.EncodedType(), buffer[1..][0 .. len - 1], @intCast(value), endian);
            break :blk layout;
        },
    };
}

/// Assumes that `buffer.len == ValueLayout.fromFlagByte(flag_byte).?.encodedLength() - 1`.
pub fn decodeBuffer(
    flag_byte: u8,
    buffer: []const u8,
    endian: std.builtin.Endian,
) ValueLayout.max.EncodedType() {
    return switch (ValueLayout.fromFlagByte(flag_byte).?) {
        inline .u8, .u16, .u32, .u64, .u128 => |layout| blk: {
            const len = comptime layout.encodedLength();
            assert(buffer.len == len - 1);

            if (comptime layout.flagByte() == null) {
                comptime assert(len == 1);
                break :blk flag_byte;
            }

            break :blk std.mem.readInt(layout.EncodedType(), buffer[0 .. len - 1], endian);
        },
    };
}

fn testEncodeAndDecode(
    comptime T: type,
    value: T,
    maybe_expected_bytes: ?[]const u8,
    maybe_expected_encoding: ?ValueLayout,
    endian: std.builtin.Endian,
) !void {
    var buffer: [ValueLayout.max.encodedLength()]u8 = undefined;
    const actual_bytes = buffer[0..encodeBuffer(T, value, &buffer, endian).encodedLength()];
    const decoded = decodeBuffer(actual_bytes[0], actual_bytes[1..], endian);
    try std.testing.expectEqual(value, decoded);

    if (maybe_expected_encoding) |expected_encoding| {
        try std.testing.expectEqual(expected_encoding, ValueLayout.fromValue(T, value));
    }

    if (maybe_expected_bytes) |expected_bytes| {
        try std.testing.expectEqualSlices(u8, expected_bytes, actual_bytes);
    }
}

test "encoding & decoding" {
    inline for (.{u9} ++ .{
        u16,  u17,
        u32,  u33,
        u64,  u65,
        u128,
    }) |T| {
        for (0..200) |value| try testEncodeAndDecode(T, @intCast(value), null, null, .little);

        try testEncodeAndDecode(T, 0, &.{0}, .u8, .little);
        try testEncodeAndDecode(T, 1, &.{1}, .u8, .little);
        try testEncodeAndDecode(T, 250, &.{250}, .u8, .little);

        try testEncodeAndDecode(T, 251, &[_]u8{ 251, 251, 0 }, .u16, .little);
        try testEncodeAndDecode(T, 252, &[_]u8{ 251, 252, 0 }, .u16, .little);
        try testEncodeAndDecode(T, 251, &[_]u8{ 251, 0, 251 }, .u16, .big);
        try testEncodeAndDecode(T, 252, &[_]u8{ 251, 0, 252 }, .u16, .big);

        if (std.math.maxInt(T) < 1 << 16 + 1) continue;

        try testEncodeAndDecode(T, (1 << 16) + 0, &[_]u8{ 252, 0, 0, 1, 0 }, .u32, .little);
        try testEncodeAndDecode(T, (1 << 16) + 1, &[_]u8{ 252, 1, 0, 1, 0 }, .u32, .little);
        try testEncodeAndDecode(T, (1 << 16) + 0, &[_]u8{ 252, 0, 1, 0, 0 }, .u32, .big);
        try testEncodeAndDecode(T, (1 << 16) + 1, &[_]u8{ 252, 0, 1, 0, 1 }, .u32, .big);

        if (std.math.maxInt(T) < 1 << 32 + 1) continue;

        try testEncodeAndDecode(T, (1 << 32) + 0, &[_]u8{ 253, 0, 0, 0, 0, 1, 0, 0, 0 }, .u64, .little);
        try testEncodeAndDecode(T, (1 << 32) + 1, &[_]u8{ 253, 1, 0, 0, 0, 1, 0, 0, 0 }, .u64, .little);
        try testEncodeAndDecode(T, (1 << 32) + 0, &[_]u8{ 253, 0, 0, 0, 1, 0, 0, 0, 0 }, .u64, .big);
        try testEncodeAndDecode(T, (1 << 32) + 1, &[_]u8{ 253, 0, 0, 0, 1, 0, 0, 0, 1 }, .u64, .big);

        if (std.math.maxInt(T) < 1 << 64 + 1) continue;

        try testEncodeAndDecode(T, (1 << 64) + 0, &[_]u8{ 254, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0 }, .u128, .little);
        try testEncodeAndDecode(T, (1 << 64) + 1, &[_]u8{ 254, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0 }, .u128, .little);
        try testEncodeAndDecode(T, (1 << 64) + 0, &[_]u8{ 254, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0 }, .u128, .big);
        try testEncodeAndDecode(T, (1 << 64) + 1, &[_]u8{ 254, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1 }, .u128, .big);
    }
}

const std = @import("std");
const assert = std.debug.assert;
