pub const RoundingMode = enum { unrounded, rounded_type };

pub inline fn format(comptime rounding_mode: RoundingMode) Format(rounding_mode) {
    return .{};
}

pub fn Format(comptime rounding_mode: RoundingMode) type {
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
            const T = @TypeOf(value.*);
            const int_type = intTypeFrom(T, rounding_mode) orelse @compileError("Unsupported integer type " ++ @typeName(T));
            try bincode.int.writeInt(writer, int_config, int_type, value.*);
        }

        pub const DecodeError = bincode.int.ReadIntError;
        pub inline fn decode(
            _: Self,
            int_config: bincode.int.Config,
            /// `*T`, where `@typeInfo(T) == .Int`
            value: anytype,
            reader: anytype,
            allocator: std.mem.Allocator,
        ) !void {
            _ = allocator;
            const T = @TypeOf(value.*);
            const int_type = intTypeFrom(T, rounding_mode) orelse @compileError("Unsupported integer type " ++ @typeName(T));
            value.* = try bincode.int.readInt(reader, int_config, int_type);
        }

        pub inline fn freeDecoded(
            _: Self,
            int_config: bincode.int.Config,
            /// `*const T`, where `@typeInfo(T) == .Int`
            value: anytype,
            allocator: std.mem.Allocator,
        ) void {
            _ = int_config;
            _ = allocator;
            const T = @TypeOf(value.*);
            _ = intTypeFrom(T, rounding_mode) orelse @compileError("Unsupported integer type " ++ @typeName(T));
        }
    };
}

inline fn intTypeFrom(comptime T: type, rounding_mode: RoundingMode) ?bincode.int.IntType {
    comptime return switch (rounding_mode) {
        .unrounded => bincode.int.IntType.fromType(T),
        .rounded_type => bincode.int.IntType.fromTypeRounded(T),
    };
}

const bincode = @import("../bincode.zig");
const DataFormat = bincode.fmt.DataFormat;
const dataFormat = bincode.fmt.dataFormat;

const std = @import("std");
const assert = std.debug.assert;
