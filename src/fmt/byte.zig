//! General context used for bools, bytes, and integers that fit into a byte.

pub const format: Format = .{};

pub const Format = struct {
    pub const EncodeError = error{};
    pub inline fn encode(
        _: Format,
        int_config: bc.int.Config,
        /// `*const T`, where `@typeInfo(T).Int.bits <= 8`
        value: anytype,
        writer: anytype,
    ) !void {
        const T = @TypeOf(value.*);
        _ = int_config;
        comptime assert(@bitSizeOf(*anyopaque) > @bitSizeOf(u8));
        const byte_value: u8 = switch (@typeInfo(T)) {
            .Int => |info| switch (info.signedness) {
                .signed => @bitCast(@as(i8, value.*)),
                .unsigned => value.*,
            },
            .Bool => @intFromBool(value.*),
            else => @compileError("Unsupported type :" ++ @typeName(T)),
        };
        try writer.writeByte(byte_value);
    }

    pub fn DecodeError(comptime Value: type) type {
        const OverflowError = switch (@typeInfo(Value)) {
            .Int => |info| blk: {
                if (info.bits > 8) return error{};
                break :blk if (info.bits < 8) error{ByteOverflow} else error{};
            },
            .Bool => error{InvalidBoolean},
            else => return error{},
        };
        return OverflowError || error{ByteFormatEof};
    }
    pub inline fn decode(
        _: Format,
        int_config: bc.int.Config,
        /// `*T`, where `@typeInfo(T).Int.bits <= 8`
        value: anytype,
        reader: anytype,
        allocator: std.mem.Allocator,
    ) !void {
        const T = @TypeOf(value.*);
        _ = int_config;
        _ = allocator;
        const byte_value: u8 = blk: {
            var byte_value: u8 = undefined;
            switch (try reader.readAll((&byte_value)[0..1])) {
                0 => return DecodeError(T).ByteFormatEof,
                1 => {},
                else => unreachable,
            }
            break :blk byte_value;
        };
        const signedness: std.builtin.Signedness = switch (@typeInfo(T)) {
            .Int => |info| info.signedness,
            .Bool => .unsigned,
            else => @compileError("Unsupported type :" ++ @typeName(T)),
        };
        const wide_value = switch (signedness) {
            .unsigned => byte_value,
            .signed => @as(i8, @bitCast(byte_value)),
        };
        value.* = switch (@typeInfo(T)) {
            .Int => blk: {
                if (wide_value < comptime std.math.minInt(T)) return DecodeError(T).ByteOverflow;
                if (wide_value > comptime std.math.maxInt(T)) return DecodeError(T).ByteOverflow;
                break :blk @intCast(wide_value);
            },
            .Bool => switch (wide_value) {
                0 => false,
                1 => true,
                else => return DecodeError(T).InvalidBoolean,
            },
            else => @compileError("Unsupported type :" ++ @typeName(T)),
        };
    }

    pub inline fn freeDecoded(
        _: Format,
        int_config: bc.int.Config,
        /// `*const T`, where `@typeInfo(T).Int.bits <= 8`
        value: anytype,
        allocator: std.mem.Allocator,
    ) void {
        _ = int_config;
        _ = allocator;
        const T = @TypeOf(value.*);
        switch (@typeInfo(T)) {
            .Int => |info| if (info.bits > 8) @compileError("Unsupported type :" ++ @typeName(T)),
            .Bool => {},
            else => @compileError("Unsupported type :" ++ @typeName(T)),
        }
    }
};

const std = @import("std");
const assert = std.debug.assert;

const bc = @import("../bincode.zig");
