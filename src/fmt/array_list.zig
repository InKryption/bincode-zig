pub inline fn format(
    /// Must allow for `fmt.DataFormat(@TypeOf(child))`.
    child_ctx: anytype,
) Format(@TypeOf(child_ctx)) {
    return .{ .child = child_ctx };
}

const ArrayListInfo = struct {
    Slice: type,
    alignment: comptime_int,
    allocator_kind: AllocatorKind,

    const AllocatorKind = enum {
        managed,
        unmanaged,
    };

    fn Element(comptime ali: ArrayListInfo) type {
        return @typeInfo(ali.Slice).Pointer.child;
    }
};
inline fn arrayListInfo(comptime ArrayListType: type) ?ArrayListInfo {
    comptime {
        if (@typeInfo(ArrayListType) != .Struct) return null;
        if (!@hasDecl(ArrayListType, "Slice")) return null;
        if (@TypeOf(ArrayListType.Slice) != type) return null;
        const Slice = ArrayListType.Slice;
        const ptr_info = switch (@typeInfo(Slice)) {
            .Pointer => |info| info,
            else => return null,
        };
        if (ptr_info.size != .Slice) return null;
        const allocator_kind: ArrayListInfo.AllocatorKind = switch (ArrayListType) {
            std.ArrayListAlignedUnmanaged(ptr_info.child, ptr_info.alignment) => .unmanaged,
            std.ArrayListAligned(ptr_info.child, ptr_info.alignment) => .managed,
            else => return null,
        };
        return .{
            .Slice = Slice,
            .alignment = ptr_info.alignment,
            .allocator_kind = allocator_kind,
        };
    }
}

pub fn Format(comptime ChildCtx: type) type {
    return struct {
        child: ChildCtx,
        const Self = @This();

        pub fn EncodeError(comptime Value: type) type {
            if (arrayListInfo(Value) == null) return error{};
            return ListFmt.EncodeError(Value.Slice);
        }
        pub inline fn encode(
            ctx: Self,
            int_config: bincode.int.Config,
            /// `*const T`, where
            /// `T == std.ArrayListAlignedUnmanaged(E, alignment)` or
            /// `T == std.ArrayListAligned(E, alignment)`
            value: anytype,
            writer: anytype,
        ) !void {
            const T = @TypeOf(value.*);
            comptime if (arrayListInfo(T) == null) @compileError("Expected `std.ArrayListAligned(T, alignment)` or `std.ArrayListAlignedUnmanaged(T, alignment)`, got `" ++ @typeName(T) ++ "`");
            try ctx.listFmt().encode(int_config, &value.items, writer);
        }

        pub fn DecodeError(comptime Value: type) type {
            if (arrayListInfo(Value) == null) return error{};
            return ListFmt.DecodeError(Value.Slice);
        }
        pub inline fn decode(
            ctx: Self,
            int_config: bincode.int.Config,
            /// `*T`, where
            /// `T == std.ArrayListAlignedUnmanaged(E, _)` or
            /// `T == std.ArrayListAligned(E, _)`
            value: anytype,
            reader: anytype,
            allocator: std.mem.Allocator,
        ) !void {
            const T = @TypeOf(value.*);
            const array_list_info = comptime arrayListInfo(T) orelse @compileError("Expected `std.ArrayListAligned(T, alignment)` or `std.ArrayListAlignedUnmanaged(T, alignment)`, got `" ++ @typeName(T) ++ "`");

            var slice: array_list_info.Slice = undefined;
            try ctx.listFmt().decode(int_config, &slice, reader, allocator);

            var array_list = std.ArrayListAlignedUnmanaged(array_list_info.Element(), array_list_info.alignment).initBuffer(slice);
            value.* = switch (array_list_info.allocator_kind) {
                .managed => array_list.toManaged(allocator),
                .unmanaged => array_list,
            };
        }

        pub inline fn freeDecoded(
            ctx: Self,
            int_config: bincode.int.Config,
            /// `*const T`, where
            /// `T == std.ArrayListAlignedUnmanaged(E, _)` or
            /// `T == std.ArrayListAligned(E, _)`
            value: anytype,
            allocator: std.mem.Allocator,
        ) void {
            const T = @TypeOf(value.*);
            comptime if (arrayListInfo(T) == null) @compileError("Expected `std.ArrayListAligned(T, alignment)` or `std.ArrayListAlignedUnmanaged(T, alignment)`, got `" ++ @typeName(T) ++ "`");
            ctx.listFmt().freeDecoded(int_config, &value.items, allocator);
        }

        const ListFmt = bincode.fmt.DataFormat(bincode.fmt.list.Format(ChildCtx, .encode_len_always));
        inline fn listFmt(ctx: Self) ListFmt {
            return bincode.fmt.dataFormat(bincode.fmt.list.format(ctx.child, .encode_len_always));
        }
    };
}

const std = @import("std");
const assert = std.debug.assert;

const bincode = @import("../bincode.zig");
