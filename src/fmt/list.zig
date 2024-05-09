pub const LengthEncoding = enum {
    /// Encode the length if the type is a slice, sentinel terminated pointer,
    /// a pointer to an array, or a pointer to a vector.
    /// Don't encode the length if the type is an array or vector.
    encode_len_based_on_type,
    /// Always encode the length, even if the type is an array or vector.
    encode_len_always,
    /// Only encode the length if the type is a slice, or a sentinel terminated pointer.
    encode_len_if_needed,
};

pub inline fn format(
    /// Must allow for `fmt.DataFormat(@TypeOf(child_ctx))`.
    child_ctx: anytype,
    comptime length_encoding: LengthEncoding,
    allocator: std.mem.Allocator,
) Format(@TypeOf(child_ctx), length_encoding) {
    return .{
        .child_ctx = child_ctx,
        .allocator = allocator,
    };
}

inline fn listContantLength(comptime Value: type) ?usize {
    const ptr_info = switch (@typeInfo(Value)) {
        .Pointer => |info| info,
        inline .Array, .Vector => |info| return info.len,
        else => return null,
    };
    if (ptr_info.size != .One) {
        return null;
    }
    return switch (@typeInfo(ptr_info.child)) {
        inline //
        .Array, .Vector => |info| info.len,
        else => null,
    };
}

inline fn mustHaveEncodedLength(
    comptime Value: type,
    comptime length_encoding: LengthEncoding,
) bool {
    switch (length_encoding) {
        .encode_len_always => return true,
        .encode_len_if_needed => return listContantLength(Value) == null,
        .encode_len_based_on_type => {
            if (listContantLength(Value) == null) return true;
            return switch (@typeInfo(Value)) {
                .Array, .Vector => false,
                else => true,
            };
        },
    }
}

fn ListElem(comptime Value: type) ?type {
    return switch (@typeInfo(Value)) {
        .Pointer => |ptr_info| switch (ptr_info.size) {
            .One => switch (@typeInfo(ptr_info.child)) {
                inline .Array, .Vector => |array_info| array_info.child,
                else => null,
            },
            else => ptr_info.child,
        },
        inline .Array, .Vector => |array_info| array_info.child,
        else => null,
    };
}

pub fn Format(
    comptime ChildCtx: type,
    comptime length_encoding: LengthEncoding,
) type {
    return struct {
        child_ctx: ChildCtx,
        allocator: std.mem.Allocator,
        const Self = @This();

        pub fn EncodeError(comptime Value: type) type {
            const LengthErr = if (mustHaveEncodedLength(Value, length_encoding)) DataFormat(bincode.fmt.int.Format(.usize)).EncodeError(usize) else error{};
            const ElementErr = DataFormat(ChildCtx).EncodeError(ListElem(Value) orelse @compileError("unsupported list type " ++ @typeName(Value)));
            return LengthErr || ElementErr;
        }
        pub inline fn encode(
            ctx: Self,
            int_config: bincode.int.Config,
            /// `*const L`, where `L` =
            /// `[n]T`                 |
            /// `@Vector(n, T)`        |
            /// `*const [n]T`          |
            /// `*const @Vector(n, T)` |
            /// `[*:s]const T`         |
            /// `[]const T`
            value: anytype,
            writer: anytype,
        ) !void {
            const List = @TypeOf(value.*);
            const value_len: usize = switch (@typeInfo(List)) {
                .Array, .Vector => value.len,
                .Pointer => |ptr_info| switch (ptr_info.size) {
                    .Many => std.mem.indexOfSentinel(ptr_info.child, std.meta.sentinel(List) orelse @compileError("unsupported list type `" ++ @typeName(List) ++ "`"), value.*),
                    else => value.*.len,
                },
                else => @compileError("unsupported list type `" ++ @typeName(List) ++ "`"),
            };
            if (comptime mustHaveEncodedLength(List, length_encoding)) {
                try dataFormat(bincode.fmt.int.format(.usize)).encode(int_config, &value_len, writer);
            }
            const iterable_ptr = switch (@typeInfo(List)) {
                .Array, .Vector => value,
                .Pointer => |ptr_info| switch (ptr_info.size) {
                    .One => value.*,
                    .Slice => value.*,
                    .Many => value.*[0..value_len :std.meta.sentinel(List).?],
                    else => @compileError("unsupported list type `" ++ @typeName(List) ++ "`"),
                },
                else => @compileError("unsupported list type `" ++ @typeName(List) ++ "`"),
            };
            for (iterable_ptr) |*elem| {
                try dataFormat(ctx.child_ctx).encode(int_config, elem, writer);
            }
        }

        pub fn DecodeError(comptime Value: type) type {
            const ElementErr = DataFormat(ChildCtx).DecodeError(ListElem(Value) orelse @compileError("unsupported list type " ++ @typeName(Value)));
            const LengthErr = blk: {
                var LengthErr = error{};
                if (mustHaveEncodedLength(Value, length_encoding)) {
                    if (listContantLength(Value) != null) LengthErr = LengthErr || error{
                        ListFormatLengthPrefixMismatch,
                    };
                    LengthErr = LengthErr || DataFormat(bincode.fmt.int.Format(.usize)).DecodeError(usize);
                }
                break :blk LengthErr;
            };
            return LengthErr || ElementErr;
        }
        pub inline fn decode(
            ctx: Self,
            int_config: bincode.int.Config,
            /// `*L`, where `L` =
            /// `[n]T`                 |
            /// `@Vector(n, T)`        |
            /// `*const [n]T`          |
            /// `*const @Vector(n, T)` |
            /// `[*:s]const T`         |
            /// `[]const T`
            value: anytype,
            reader: anytype,
        ) !void {
            const List = @TypeOf(value.*);
            const decoded_len = if (comptime !mustHaveEncodedLength(List, length_encoding)) {} else blk: {
                var decoded_len: usize = undefined;
                try dataFormat(bincode.fmt.int.format(.usize)).decode(int_config, &decoded_len, reader);
                break :blk decoded_len;
            };

            const sentinel: ?ListElem(List).? = comptime switch (@typeInfo(List)) {
                .Vector => null,
                .Array, .Pointer => std.meta.sentinel(List),
                else => unreachable,
            };
            const allocation = blk: {
                const constant_len = (comptime listContantLength(List)) orelse {
                    comptime assert(@TypeOf(decoded_len) == usize);

                    const allocation = try ctx.allocator.alignedAlloc(ListElem(List).?, @typeInfo(List).Pointer.alignment, decoded_len + @intFromBool(sentinel != null));
                    errdefer ctx.allocator.free(allocation);

                    if (sentinel) |s| allocation[decoded_len] = s;
                    value.* = if (sentinel) |s| allocation[0..decoded_len :s] else allocation[0..decoded_len];

                    break :blk allocation;
                };

                switch (@TypeOf(decoded_len)) {
                    else => comptime unreachable,
                    void => {},
                    usize => if (decoded_len != constant_len) {
                        return DecodeError(List).ListFormatLengthPrefixMismatch;
                    },
                }

                switch (@typeInfo(List)) {
                    .Pointer => {
                        const allocation = try ctx.allocator.alignedAlloc(ListElem(List).?, @typeInfo(List).Pointer.alignment, comptime (constant_len + @intFromBool(sentinel != null)));
                        errdefer ctx.allocator.free(allocation);

                        if (sentinel) |s| allocation[constant_len] = s;
                        value.* = if (sentinel) |s| allocation[0..constant_len :s] else allocation[0..constant_len];

                        break :blk allocation;
                    },
                    .Array, .Vector => {
                        if (sentinel) |s| value[constant_len] = s;
                    },
                    else => comptime unreachable,
                }

                break :blk;
            };
            errdefer switch (@typeInfo(List)) {
                .Pointer => ctx.allocator.free(allocation),
                .Array, .Vector => {},
                else => comptime unreachable,
            };

            for (allocation, 0..) |*elem, initialized_elems| {
                errdefer ctx.freeDecodedElemsPartial(int_config, value, initialized_elems);
                try dataFormat(ctx.child_ctx).decode(int_config, elem, reader);
            }
        }

        pub inline fn freeDecoded(
            ctx: Self,
            int_config: bincode.int.Config,
            /// `*const L`, where `L` =
            /// `[n]T`                 |
            /// `@Vector(n, T)`        |
            /// `*const [n]T`          |
            /// `*const @Vector(n, T)` |
            /// `[*:s]const T`         |
            /// `[]const T`
            value: anytype,
        ) void {
            const List = @TypeOf(value.*);
            ctx.freeDecodedElemsPartial(int_config, value, switch (@typeInfo(List)) {
                .Pointer => |ptr_info| switch (ptr_info.size) {
                    .One => switch (@typeInfo(ptr_info.child)) {
                        .Array => value.*.len,
                        .Vector => |vec_info| vec_info.len,
                        else => comptime unreachable,
                    },
                    .Many => std.mem.indexOfSentinel(ptr_info.child, std.meta.sentinel(List).?, value.*),
                    else => value.*.len,
                },
                .Vector => |vec_info| vec_info.len,
                .Array => value.*.len,
                else => comptime unreachable,
            });
            switch (@typeInfo(List)) {
                .Pointer => |ptr_info| switch (ptr_info.size) {
                    .Many => {
                        const sentinel = comptime std.meta.sentinel(List).?;
                        ctx.allocator.free(std.mem.sliceTo(value.*, sentinel));
                    },
                    else => ctx.allocator.free(value.*),
                },
                .Array, .Vector => {},
                else => comptime unreachable,
            }
        }

        inline fn freeDecodedElemsPartial(
            ctx: Self,
            int_config: bincode.int.Config,
            value: anytype,
            up_to: usize,
        ) void {
            for (value.*[0..up_to]) |*elem| dataFormat(ctx.child_ctx).freeDecoded(int_config, elem);
        }
    };
}

const std = @import("std");
const assert = std.debug.assert;

const bincode = @import("../bincode.zig");
const DataFormat = bincode.fmt.DataFormat;
const dataFormat = bincode.fmt.dataFormat;
