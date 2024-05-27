pub inline fn format(
    /// Must allow for `fmt.DataFormat(@TypeOf(payload_ctx))`.
    payload_ctx: anytype,
) Format(@TypeOf(payload_ctx)) {
    return .{ .payload = payload_ctx };
}

pub fn Format(comptime PayloadCtx: type) type {
    return struct {
        payload: PayloadCtx,
        const Self = @This();

        pub fn EncodeError(comptime Value: type) type {
            return bc.fmt.byte.Format.EncodeError || DataFormat(PayloadCtx).EncodeError(@typeInfo(Value).Optional.child);
        }
        pub inline fn encode(
            ctx: Self,
            int_config: bc.int.Config,
            /// `*const T`, where `T = ?U`.
            value: anytype,
            writer: anytype,
        ) !void {
            const discriminant_byte: u8 = @intFromBool(value.* != null);
            try dataFormat(bc.fmt.byte.format).encode(int_config, &discriminant_byte, writer);
            const payload = if (value.*) |*payload| payload else return;
            try dataFormat(ctx.payload).encode(int_config, payload, writer);
        }

        pub fn DecodeError(comptime Value: type) type {
            return bc.fmt.byte.Format.DecodeError(u8) || DataFormat(PayloadCtx).DecodeError(@typeInfo(Value).Optional.child);
        }
        pub inline fn decode(
            ctx: Self,
            int_config: bc.int.Config,
            /// `*T`, where `T = ?U`.
            value: anytype,
            reader: anytype,
            allocator: std.mem.Allocator,
        ) !void {
            const discriminant_byte: u8 = blk: {
                var discriminant_byte: u8 = undefined;
                try dataFormat(bc.fmt.byte.format).decode(int_config, &discriminant_byte, reader, allocator);
                break :blk discriminant_byte;
            };
            if (discriminant_byte == 0) {
                value.* = null;
                return;
            }
            value.* = @as(@TypeOf(value.*.?), undefined);
            try dataFormat(ctx.payload).decode(int_config, &value.*.?, reader, allocator);
        }

        pub inline fn freeDecoded(
            ctx: Self,
            int_config: bc.int.Config,
            /// `*const T`, where `T = ?U`.
            value: anytype,
            allocator: std.mem.Allocator,
        ) void {
            const payload = if (value.*) |*payload| payload else return;
            dataFormat(ctx.payload).freeDecoded(int_config, payload, allocator);
        }
    };
}

const bc = @import("../bincode.zig");
const DataFormat = bc.fmt.DataFormat;
const dataFormat = bc.fmt.dataFormat;

const std = @import("std");
const assert = std.debug.assert;
