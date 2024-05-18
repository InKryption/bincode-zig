pub const format: Format = .{};

pub const Format = struct {
    pub const EncodeError = error{};
    pub inline fn encode(
        _: Format,
        int_config: bincode.int.Config,
        /// `*const T`
        value: anytype,
        writer: anytype,
    ) !void {
        _ = int_config;
        try writer.writeByte(@bitCast(value.*));
    }

    pub const DecodeError = error{ByteFormatEof};
    pub inline fn decode(
        _: Format,
        int_config: bincode.int.Config,
        /// `*T`
        value: anytype,
        reader: anytype,
        allocator: std.mem.Allocator,
    ) !void {
        _ = int_config;
        _ = allocator;
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
        _: Format,
        int_config: bincode.int.Config,
        /// `*const T`
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
const dataFormat = bincode.fmt.dataFormat;
