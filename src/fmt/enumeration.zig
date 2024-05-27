pub const Encoding = enum {
    /// The enum value is encoded as the index at which it's declared at using a u32.
    /// This is used for the backing tag of tagged unions/rust enums.
    tag_index_u32,
    /// The enum value is encoded as the backing integer value.
    tag_value,
};

pub inline fn format(comptime encoding: Encoding) Format(encoding) {
    return .{};
}

pub fn Format(comptime encoding: Encoding) type {
    return struct {
        const Self = @This();

        const IntFormat = bc.fmt.int.Format(.rounded);
        const int_format = bc.fmt.dataFormat(bc.fmt.int.format(.rounded));

        pub const EncodeError = IntFormat.EncodeError;
        pub inline fn encode(
            _: Self,
            int_config: bc.int.Config,
            /// `*const T`, where `@typeInfo(T) == .Enum`
            value: anytype,
            writer: anytype,
        ) !void {
            const T = @TypeOf(value.*);
            const int_value = switch (encoding) {
                .tag_index_u32 => @as(u32, @intFromEnum(switch (value.*) {
                    inline else => |tag| @field(std.meta.FieldEnum(T), @tagName(tag)),
                })),
                .tag_value => @intFromEnum(value.*),
            };
            const encode_as_byte = switch (encoding) {
                .tag_index_u32 => false,
                .tag_value => @bitSizeOf(T) <= 8,
            };
            if (encode_as_byte) {
                try bc.fmt.byte.format.encode(int_config, &int_value, writer);
            } else {
                try int_format.encode(int_config, &int_value, writer);
            }
        }

        pub fn DecodeError(comptime Value: type) type {
            const TagError = switch (@typeInfo(Value)) {
                else => return error{},
                .Enum => |info| switch (encoding) {
                    .tag_index_u32 => blk: {
                        const IndexInt = std.math.IntFittingRange(0, info.fields.len);
                        if (bc.int.Type.fromType(IndexInt) != null) break :blk error{};
                        break :blk error{EnumInvalidIndexValue};
                    },
                    .tag_value => blk: {
                        if (!info.is_exhaustive) break :blk error{};
                        if (info.fields.len == std.math.maxInt(info.tag_type)) break :blk error{};
                        break :blk error{EnumInvalidTagValue};
                    },
                },
            };
            return TagError || IntFormat.DecodeError;
        }
        pub inline fn decode(
            _: Self,
            int_config: bc.int.Config,
            /// `*T`, where `@typeInfo(T) == .Enum`
            value: anytype,
            reader: anytype,
            allocator: std.mem.Allocator,
        ) !void {
            const T = @TypeOf(value.*);
            const int_value = blk: {
                const encode_as_byte = switch (encoding) {
                    .tag_index_u32 => false,
                    .tag_value => @bitSizeOf(T) <= 8,
                };
                const EnumTag = @typeInfo(T).Enum.tag_type;
                const Int = comptime switch (encoding) {
                    .tag_index_u32 => u32,
                    .tag_value => if (encode_as_byte) EnumTag else bc.int.Type.fromTypeRounded(EnumTag).?.ToType(),
                };

                var int_value: Int = undefined;
                if (encode_as_byte) {
                    try bc.fmt.byte.format.decode(int_config, &int_value, reader, allocator);
                } else {
                    try int_format.decode(int_config, &int_value, reader, allocator);
                }

                break :blk int_value;
            };
            value.* = switch (encoding) {
                .tag_index_u32 => blk: {
                    const values = comptime std.enums.values(T);
                    if (int_value >= values.len) return DecodeError(T).EnumInvalidIndexValue;
                    break :blk values[int_value];
                },
                .tag_value => blk: {
                    const info = @typeInfo(T).Enum;
                    if (!info.is_exhaustive) break :blk @enumFromInt(int_value);
                    if (info.fields.len == std.math.maxInt(info.tag_type)) break :blk @enumFromInt(int_value);
                    break :blk std.meta.intToEnum(T, int_value) catch |err| switch (err) {
                        error.InvalidEnumTag => return DecodeError(T).EnumInvalidTagValue,
                    };
                },
            };
        }

        pub inline fn freeDecoded(
            _: Self,
            int_config: bc.int.Config,
            /// `*const T`, where `@typeInfo(T) == .Enum`
            value: anytype,
            allocator: std.mem.Allocator,
        ) void {
            _ = int_config;
            _ = allocator;
            _ = value;
        }
    };
}

const bc = @import("../bincode.zig");
const DataFormat = bc.fmt.DataFormat;

const std = @import("std");
const assert = std.debug.assert;
