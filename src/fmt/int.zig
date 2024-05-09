pub inline fn format(comptime int_type: bincode.int.IntType) Format(int_type) {
    return .{};
}

pub fn Format(comptime int_type: bincode.int.IntType) type {
    return struct {
        const Self = @This();

        pub const EncodeError = error{};
        pub inline fn encode(
            _: Self,
            int_config: bincode.int.Config,
            /// `*const T`, where `@typeInfo(T) == .Int`
            value: anytype,
            writer: anytype,
        ) !void {
            try bincode.int.writeInt(writer, int_config, int_type, value.*);
        }

        pub const DecodeError = bincode.int.ReadIntError;
        pub inline fn decode(
            _: Self,
            int_config: bincode.int.Config,
            /// `*T`, where `@typeInfo(T) == .Int`
            value: anytype,
            reader: anytype,
        ) !void {
            value.* = try bincode.int.readInt(reader, int_config, int_type);
        }

        pub inline fn freeDecoded(
            _: Self,
            int_config: bincode.int.Config,
            /// `*const T`, where `@typeInfo(T) == .Int`
            value: anytype,
        ) void {
            _ = int_config;
            comptime assert(@typeInfo(@TypeOf(value.*)) == .Int);
        }
    };
}

const bincode = @import("../bincode.zig");
const DataFormat = bincode.fmt.DataFormat;
const dataFormat = bincode.fmt.dataFormat;

const std = @import("std");
const assert = std.debug.assert;
