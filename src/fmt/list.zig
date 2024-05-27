//! Context for encoding/decoding a list of values, supporting both variable and fixed length list types.

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
    /// Must allow for `fmt.DataFormat(@TypeOf(child))`.
    child_ctx: anytype,
    comptime length_encoding: LengthEncoding,
) Format(@TypeOf(child_ctx), length_encoding) {
    return .{ .child = child_ctx };
}

pub fn Format(
    comptime ChildCtx: type,
    comptime length_encoding: LengthEncoding,
) type {
    return struct {
        child: ChildCtx,
        const Self = @This();

        pub fn EncodeError(comptime Value: type) type {
            const LengthErr = if (mustHaveEncodedLength(Value, length_encoding)) DataFormat(bc.fmt.int.Format(.unrounded)).EncodeError(usize) else error{};
            const ElementErr = DataFormat(ChildCtx).EncodeError(ListElem(Value) orelse @compileError("unsupported list type " ++ @typeName(Value)));
            return LengthErr || ElementErr;
        }
        pub inline fn encode(
            ctx: Self,
            int_config: bc.int.Config,
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
                .Array => |info| info.len,
                .Vector => |info| info.len,
                .Pointer => |ptr_info| switch (ptr_info.size) {
                    .Many => std.mem.indexOfSentinel(ptr_info.child, std.meta.sentinel(List) orelse @compileError("unsupported list type `" ++ @typeName(List) ++ "`"), value.*),
                    else => value.*.len,
                },
                else => @compileError("unsupported list type `" ++ @typeName(List) ++ "`"),
            };
            if (comptime mustHaveEncodedLength(List, length_encoding)) {
                try dataFormat(bc.fmt.int.format(.unrounded)).encode(int_config, &value_len, writer);
            }
            const closest_ptr = switch (@typeInfo(List)) {
                .Array, .Vector => value,
                .Pointer => |ptr_info| switch (ptr_info.size) {
                    .Many => value.*[0..value_len :std.meta.sentinel(List).?],
                    else => value.*,
                },
                else => @compileError("unsupported list type `" ++ @typeName(List) ++ "`"),
            };
            if (comptime isVectorPtr(@TypeOf(closest_ptr))) {
                for (0..@typeInfo(@TypeOf(closest_ptr.*)).Vector.len) |elem_idx| {
                    try dataFormat(ctx.child).encode(int_config, &closest_ptr[elem_idx], writer);
                }
            } else {
                for (closest_ptr) |*elem| {
                    try dataFormat(ctx.child).encode(int_config, elem, writer);
                }
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
                    LengthErr = LengthErr || DataFormat(bc.fmt.int.Format(.unrounded)).DecodeError(usize);
                }
                break :blk LengthErr;
            };
            return LengthErr || ElementErr;
        }
        pub inline fn decode(
            ctx: Self,
            int_config: bc.int.Config,
            /// `*L`, where `L` =
            /// `[n]T`                 |
            /// `@Vector(n, T)`        |
            /// `*const [n]T`          |
            /// `*const @Vector(n, T)` |
            /// `[*:s]const T`         |
            /// `[]const T`
            value: anytype,
            reader: anytype,
            allocator: std.mem.Allocator,
        ) !void {
            const List = @TypeOf(value.*);
            const decoded_len = if (comptime !mustHaveEncodedLength(List, length_encoding)) {} else blk: {
                var decoded_len: usize = undefined;
                try dataFormat(bc.fmt.int.format(.unrounded)).decode(int_config, &decoded_len, reader, allocator);
                break :blk decoded_len;
            };

            if (@TypeOf(decoded_len) != void) validate_len: {
                const constant_len = comptime switch (@typeInfo(List)) {
                    .Array => |info| info.len,
                    .Vector => |info| info.len,
                    .Pointer => |ptr_info| switch (ptr_info.size) {
                        .One => switch (@typeInfo(ptr_info.child)) {
                            .Array => |info| info.len,
                            .Vector => |info| info.len,
                            else => unreachable,
                        },
                        else => break :validate_len,
                    },
                    else => unreachable,
                };
                if (decoded_len != constant_len) {
                    return DecodeError(List).ListFormatLengthPrefixMismatch;
                }
            }

            const Elem = comptime switch (@typeInfo(List)) {
                .Array => |info| info.child,
                .Vector => |info| info.child,
                .Pointer => |ptr_info| switch (ptr_info.size) {
                    .One => switch (@typeInfo(ptr_info.child)) {
                        .Array => |info| info.child,
                        .Vector => |info| info.child,
                        else => unreachable,
                    },
                    else => ptr_info.child,
                },
                else => unreachable,
            };
            const sentinel: ?Elem = comptime blk: {
                const maybe_sentinel_ptr = switch (@typeInfo(List)) {
                    .Vector => break :blk null,
                    .Array => |info| info.sentinel,
                    .Pointer => |ptr_info| switch (ptr_info.size) {
                        .One => switch (@typeInfo(ptr_info.child)) {
                            .Vector => break :blk null,
                            .Array => |info| info.sentinel,
                            else => unreachable,
                        },
                        else => ptr_info.sentinel,
                    },
                    else => unreachable,
                };
                const sentinel_ptr = maybe_sentinel_ptr orelse break :blk null;
                const sentinel: *align(1) const Elem = @ptrCast(sentinel_ptr);
                break :blk sentinel.*;
            };

            const closest_ptr, const must_be_freed = switch (@typeInfo(List)) {
                .Array => .{ value, false },
                .Vector => .{ value, false },
                .Pointer => |ptr_info| switch (ptr_info.size) {
                    .One => switch (@typeInfo(ptr_info.child)) {
                        .Vector => blk: {
                            const bytes = try allocator.alignedAlloc(u8, ptr_info.alignment, ptr_info.child);
                            errdefer allocator.free(bytes);

                            const ptr: *align(ptr_info.alignment) ptr_info.child = @ptrCast(bytes.ptr);
                            value.* = ptr;

                            break :blk .{ ptr, true };
                        },
                        .Array => |info| blk: {
                            const slice = try allocator.allocWithOptions(Elem, info.len, ptr_info.alignment, sentinel);
                            errdefer allocator.free(slice);

                            const ptr: *align(ptr_info.alignment) ptr_info.child = if (sentinel) |s| slice[0..info.len :s] else slice[0..info.len];
                            value.* = ptr;

                            break :blk .{ ptr, true };
                        },
                        else => comptime unreachable,
                    },
                    else => |ptr_size| blk: {
                        const slice = try allocator.allocWithOptions(Elem, decoded_len, ptr_info.alignment, sentinel);
                        errdefer allocator.free(slice);

                        value.* = switch (ptr_size) {
                            .Slice => slice,
                            .Many => slice.ptr,
                            else => comptime unreachable,
                        };

                        break :blk .{ slice, true };
                    },
                },
                else => comptime unreachable,
            };
            errdefer if (comptime must_be_freed) allocator.free(closest_ptr);

            if (comptime isVectorPtr(@TypeOf(closest_ptr))) {
                for (0..@typeInfo(@TypeOf(closest_ptr.*)).Vector.len) |elem_idx| {
                    errdefer ctx.freeDecodedElemsPartial(int_config, closest_ptr, elem_idx, allocator);
                    var elem: Elem = undefined;
                    try dataFormat(ctx.child).decode(int_config, &elem, reader, allocator);
                    closest_ptr[elem_idx] = elem;
                }
            } else {
                for (closest_ptr, 0..) |*elem, elem_idx| {
                    errdefer ctx.freeDecodedElemsPartial(int_config, closest_ptr, elem_idx, allocator);
                    try dataFormat(ctx.child).decode(int_config, elem, reader, allocator);
                }
            }
        }

        pub inline fn freeDecoded(
            ctx: Self,
            int_config: bc.int.Config,
            value: anytype,
            allocator: std.mem.Allocator,
        ) void {
            const List = @TypeOf(value.*);
            const value_len = switch (@typeInfo(List)) {
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
            };
            const closest_ptr = switch (@typeInfo(List)) {
                .Array, .Vector => value,
                .Pointer => |ptr_info| switch (ptr_info.size) {
                    .One => switch (@typeInfo(ptr_info.child)) {
                        .Array, .Vector => value.*,
                        else => comptime unreachable,
                    },
                    .Many => value.*[0..value_len :std.meta.sentinel(List).?],
                    else => value.*,
                },
                else => comptime unreachable,
            };
            ctx.freeDecodedElemsPartial(int_config, closest_ptr, value_len, allocator);
            if (@typeInfo(List) == .Pointer) allocator.free(closest_ptr);
        }

        inline fn freeDecodedElemsPartial(
            ctx: Self,
            int_config: bc.int.Config,
            closest_ptr: anytype,
            up_to: usize,
            allocator: std.mem.Allocator,
        ) void {
            if (comptime isVectorPtr(@TypeOf(closest_ptr))) {
                for (0..up_to) |elem_idx| dataFormat(ctx.child).freeDecoded(int_config, &closest_ptr[elem_idx], allocator);
            } else {
                for (closest_ptr[0..up_to]) |*elem| dataFormat(ctx.child).freeDecoded(int_config, elem, allocator);
            }
        }
    };
}

inline fn listContantLength(comptime Value: type) ?usize {
    const ptr_info = switch (@typeInfo(Value)) {
        .Pointer => |info| info,
        .Array => |info| return info.len,
        .Vector => |info| return info.len,
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
                .Array => |info| info.child,
                .Vector => |info| info.child,
                else => null,
            },
            else => ptr_info.child,
        },
        .Array => |info| info.child,
        .Vector => |info| info.child,
        else => null,
    };
}

inline fn isVectorPtr(comptime ClosestPtr: type) bool {
    const ptr_info = @typeInfo(ClosestPtr).Pointer;
    comptime if (ptr_info.size != .One) return false;
    comptime return switch (@typeInfo(ptr_info.child)) {
        .Array => false,
        .Vector => true,
        else => unreachable,
    };
}

const std = @import("std");
const assert = std.debug.assert;

const bc = @import("../bincode.zig");
const DataFormat = bc.fmt.DataFormat;
const dataFormat = bc.fmt.dataFormat;
