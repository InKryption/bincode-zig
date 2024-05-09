pub inline fn format(comptime signedness: std.builtin.Signedness) Format(signedness) {
    return .{};
}

pub fn Format(comptime signedness: std.builtin.Signedness) type {
    return struct {
        const Self = @This();

        const T = std.meta.Int(signedness, 8);

        pub const EncodeError = error{};
        pub inline fn encode(
            _: Self,
            int_config: bincode.int.Config,
            value: *const T,
            writer: anytype,
        ) !void {
            _ = int_config;
            try writer.writeByte(@bitCast(value.*));
        }

        pub const DecodeError = error{ByteFormatEof};
        pub inline fn decode(
            _: Self,
            int_config: bincode.int.Config,
            value: *T,
            reader: anytype,
        ) !void {
            _ = int_config;
            value.* = @bitCast(blk: {
                var byte: u8 = undefined;
                switch (try reader.readAll((&byte)[0..1])) {
                    0 => return DecodeError.ByteFormatEof,
                    1 => {},
                    else => unreachable,
                }
                break :blk byte;
            });
        }

        pub inline fn freeDecoded(
            _: Self,
            int_config: bincode.int.Config,
            value: *const T,
        ) void {
            _ = int_config;
            _ = value;
        }
    };
}

const std = @import("std");

const bincode = @import("../bincode.zig");
const dataFormat = bincode.fmt.dataFormat;
