pub const format: Format = .{};

pub const Format = struct {
    pub const EncodeError = error{};
    pub inline fn encode(
        _: Format,
        int_config: bincode.int.Config,
        /// `*const T`, where `@typeInfo(T).Int.bits <= 8`
        value: anytype,
        writer: anytype,
    ) !void {
        const T = @TypeOf(value.*);
        _ = int_config;
        const byte_value: u8 = switch (@typeInfo(T).Int.signedness) {
            .signed => @bitCast(@as(i8, value.*)),
            .unsigned => value.*,
        };
        try writer.writeByte(byte_value);
    }

    pub fn DecodeError(comptime Value: type) type {
        const OverflowError = switch (@typeInfo(Value)) {
            else => return error{},
            .Int => |info| blk: {
                if (info.bits > 8) return error{};
                break :blk if (info.bits < 8) error{ByteOverflow} else error{};
            },
        };
        return OverflowError || error{ByteFormatEof};
    }
    pub inline fn decode(
        _: Format,
        int_config: bincode.int.Config,
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
        const wide_value = switch (@typeInfo(T).Int.signedness) {
            .signed => @as(i8, @bitCast(byte_value)),
            .unsigned => byte_value,
        };
        if (wide_value > std.math.maxInt(T)) return DecodeError(T).ByteOverflow;
        value.* = @intCast(wide_value);
    }

    pub inline fn freeDecoded(
        _: Format,
        int_config: bincode.int.Config,
        /// `*const T`, where `@typeInfo(T).Int.bits <= 8`
        value: anytype,
        allocator: std.mem.Allocator,
    ) void {
        _ = int_config;
        _ = value;
        _ = allocator;
    }
};

const std = @import("std");

const bincode = @import("../bincode.zig");
