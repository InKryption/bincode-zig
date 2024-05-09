//! Simple algorithm for encoding signed integers such that
//! values closer to 0 are represented using smaller values
//! than they would be by simply bitcasting them.

pub fn toUnsigned(comptime T: type, signed: T) std.meta.Int(.unsigned, @bitSizeOf(T)) {
    comptime assert(@typeInfo(T).Int.signedness == .signed);
    const Unsigned = std.meta.Int(.unsigned, @bitSizeOf(T));
    if (@bitSizeOf(T) == 1) return @bitCast(signed);
    if (signed == 0) return 0;

    const raw_bits: Unsigned = @bitCast(signed);
    if (signed < 0) return (~raw_bits * 2) + 1;
    if (signed > 0) return raw_bits * 2;
    unreachable;
}

pub fn fromUnsigned(comptime T: type, unsigned: std.meta.Int(.unsigned, @bitSizeOf(T))) T {
    if (@bitSizeOf(T) == 1) return @bitCast(unsigned);
    if (unsigned == 0) return 0;

    const is_odd_bit: u1 = @intCast(unsigned & 1);
    return switch (is_odd_bit) {
        1 => @bitCast(~((unsigned - 1) / 2)),
        0 => @bitCast(unsigned / 2),
    };
}

fn testConversion(
    comptime T: type,
    signed_input: T,
    expected_signed: ?std.meta.Int(.unsigned, @bitSizeOf(T)),
) !void {
    const actual_out = toUnsigned(T, signed_input);
    try std.testing.expectEqual(expected_signed, actual_out);

    const signed_output = fromUnsigned(T, actual_out);
    try std.testing.expectEqual(signed_input, signed_output);
}

test testConversion {
    try testConversion(i0, 0, 0);

    try testConversion(i1, 0, 0);
    try testConversion(i1, -1, 1);

    try testConversion(i2, 0, 0);
    try testConversion(i2, -1, 1);
    try testConversion(i2, 1, 2);
    try testConversion(i2, -2, 3);

    try testConversion(i3, 0, 0);
    try testConversion(i3, -1, 1);
    try testConversion(i3, 1, 2);
    try testConversion(i3, -2, 3);
    try testConversion(i3, 2, 4);
    try testConversion(i3, -3, 5);
    try testConversion(i3, 3, 6);
    try testConversion(i3, -4, 7);

    try testConversion(i4, 0, 0);
    try testConversion(i4, -1, 1);
    try testConversion(i4, 1, 2);
    try testConversion(i4, -2, 3);
    try testConversion(i4, 2, 4);
    try testConversion(i4, -3, 5);
    try testConversion(i4, 3, 6);
    try testConversion(i4, -4, 7);
    try testConversion(i4, 4, 8);
    try testConversion(i4, -5, 9);
    try testConversion(i4, 5, 10);
    try testConversion(i4, -6, 11);
    try testConversion(i4, 6, 12);
    try testConversion(i4, -7, 13);
    try testConversion(i4, 7, 14);
    try testConversion(i4, -8, 15);

    try testConversion(i8, 0, 0);
    try testConversion(i8, -1, 1);
    try testConversion(i8, 1, 2);
    try testConversion(i8, -2, 3);
    try testConversion(i8, 2, 4);
    try testConversion(i8, -3, 5);
    try testConversion(i8, 3, 6);
    try testConversion(i8, -4, 7);
    try testConversion(i8, 4, 8);
}

const std = @import("std");
const assert = std.debug.assert;
