pub const DuplicateEntryHandling = enum {
    use_latest_duplicate,
    use_first_duplicate,
    err_on_duplicate,
};

pub inline fn format(
    /// Must allow for `fmt.DataFormat(@TypeOf(child))`.
    key_ctx: anytype,
    value_ctx: anytype,
    comptime dupe_entry_handling: DuplicateEntryHandling,
) Format(@TypeOf(key_ctx), @TypeOf(value_ctx), dupe_entry_handling) {
    return .{ .key = key_ctx, .value = value_ctx };
}

pub fn Format(
    comptime KeyCtx: type,
    comptime ValueCtx: type,
    comptime dupe_entry_handling: DuplicateEntryHandling,
) type {
    return struct {
        key: KeyCtx,
        value: ValueCtx,
        const Self = @This();

        inline fn entryCtx(ctx: Self) bc.fmt.tuple.Format(struct { KeyCtx, ValueCtx }) {
            return .{ .field_fmts = .{ ctx.key, ctx.value } };
        }

        pub fn EncodeError(comptime Value: type) type {
            const info = arrayHashMapInfo(Value) orelse return error{};
            return DataFormat(KeyCtx).EncodeError(info.Key) || DataFormat(ValueCtx).EncodeError(info.Value);
        }
        pub inline fn encode(
            ctx: Self,
            int_config: bc.int.Config,
            /// `*const T`, where
            /// `T == std.ArrayHashMap(K, V, Context, store_hash)` or
            /// `T == std.ArrayHashMapUnmanaged(K, V, Context, store_hash)`
            hm: anytype,
            writer: anytype,
        ) !void {
            const T = @TypeOf(hm.*);
            comptime if (arrayHashMapInfo(T) == null) @compileError("Expected `std.ArrayHashMap(K, V, Context, store_hash)` or `std.ArrayHashMapUnmanaged(K, V, Context, store_hash)`, got `" ++ @typeName(T) ++ "`");
            try bc.fmt.int.format(.unrounded).encode(int_config, @as(*const usize, &hm.count()), writer);
            for (hm.keys(), hm.values()) |key, value| {
                try ctx.entryCtx().encode(int_config, &.{ key, value }, writer);
            }
        }

        pub fn DecodeError(comptime Value: type) type {
            const info = arrayHashMapInfo(Value) orelse return error{};
            const DupeError = switch (dupe_entry_handling) {
                .use_latest_duplicate => error{},
                .use_first_duplicate => error{},
                .err_on_duplicate => error{ArrayHashMapDuplicateEntry},
            };
            return DupeError ||
                bc.fmt.int.Format(.unrounded).DecodeError ||
                DataFormat(KeyCtx).DecodeError(info.Key) ||
                DataFormat(ValueCtx).DecodeError(info.Value);
        }
        pub inline fn decode(
            ctx: Self,
            int_config: bc.int.Config,
            /// `*T`, where
            /// `T == std.ArrayListAlignedUnmanaged(E, _)` or
            /// `T == std.ArrayListAligned(E, _)`
            hm: anytype,
            reader: anytype,
            allocator: std.mem.Allocator,
        ) !void {
            const T = @TypeOf(hm.*);
            const hm_info = comptime arrayHashMapInfo(T) orelse @compileError("Expected `std.ArrayHashMap(K, V, Context, store_hash)` or `std.ArrayHashMapUnmanaged(K, V, Context, store_hash)`, got `" ++ @typeName(T) ++ "`");

            var hash_map = std.ArrayHashMap(hm_info.Key, hm_info.Value, hm_info.Context, hm_info.store_hash).init(allocator);
            errdefer hash_map.deinit();
            errdefer for (hash_map.keys(), hash_map.values()) |key, value| {
                ctx.entryCtx().freeDecoded(int_config, &.{ key, value }, allocator);
            };

            const count: usize = blk: {
                var count: usize = undefined;
                try bc.fmt.int.format(.unrounded).decode(int_config, &count, reader, allocator);
                break :blk count;
            };

            try hash_map.ensureUnusedCapacity(count);
            for (0..count) |_| {
                var kv: struct { hm_info.Key, hm_info.Value } = undefined;
                try ctx.entryCtx().decode(int_config, &kv, reader, allocator);
                errdefer ctx.entryCtx().freeDecoded(int_config, &kv, allocator);

                const gop = hash_map.getOrPutAssumeCapacity(kv[0]);
                if (!gop.found_existing) {
                    gop.value_ptr.* = kv[1];
                    continue;
                }
                if (gop.found_existing) switch (dupe_entry_handling) {
                    .use_latest_duplicate => {
                        ctx.entryCtx().freeDecoded(int_config, &.{ gop.key_ptr.*, gop.value_ptr.* }, allocator);
                        gop.key_ptr.* = kv[0];
                        gop.value_ptr.* = kv[1];
                    },
                    .use_first_duplicate => ctx.entryCtx().freeDecoded(int_config, &kv),
                    .err_on_duplicate => return DecodeError(T).ArrayHashMapDuplicateEntry,
                };
            }

            hm.* = switch (hm_info.allocator_kind) {
                .managed => hash_map,
                .unmanaged => hash_map.unmanaged,
            };
        }

        pub inline fn freeDecoded(
            ctx: Self,
            int_config: bc.int.Config,
            /// `*const T`, where
            /// `T == std.ArrayListAlignedUnmanaged(E, _)` or
            /// `T == std.ArrayListAligned(E, _)`
            hm: anytype,
            allocator: std.mem.Allocator,
        ) void {
            const T = @TypeOf(hm.*);
            const hm_info = comptime arrayHashMapInfo(T) orelse @compileError("Expected `std.ArrayHashMap(K, V, Context, store_hash)` or `std.ArrayHashMapUnmanaged(K, V, Context, store_hash)`, got `" ++ @typeName(T) ++ "`");
            for (hm.keys(), hm.values()) |key, value| {
                ctx.entryCtx().freeDecoded(int_config, &.{ key, value }, allocator);
            }
            var copy = switch (hm_info.allocator_kind) {
                .managed => hm.*,
                .unmanaged => hm.promote(allocator),
            };
            copy.deinit();
        }
    };
}

const ArrayHashMapInfo = struct {
    Key: type,
    Value: type,
    Context: type,
    store_hash: bool,
    allocator_kind: AllocatorKind,

    const AllocatorKind = enum {
        managed,
        unmanaged,
    };
};

inline fn arrayHashMapInfo(comptime HashMapType: type) ?ArrayHashMapInfo {
    comptime {
        if (@typeInfo(HashMapType) != .Struct) return null;

        const is_managed = @hasDecl(HashMapType, "Unmanaged") and @TypeOf(HashMapType.Unmanaged) == type;
        const is_unmanaged = @hasDecl(HashMapType, "Managed") and @TypeOf(HashMapType.Managed) == type;

        if (is_managed and is_unmanaged) return false;
        if (!is_managed and !is_unmanaged) return false;

        const Managed = if (is_managed) HashMapType else HashMapType.Managed;

        if (!@hasField(Managed, "ctx")) return null;
        const Context = @TypeOf(@as(Managed, undefined).ctx);

        if (!@hasDecl(Managed, "KV") or @TypeOf(Managed.Entry) != type) return null;
        const KV = Managed.KV;

        if (!@hasDecl(Managed, "Hash") or @TypeOf(Managed.Hash) != type) return null;
        const store_hash = switch (Managed.Hash) {
            u32 => true,
            void => false,
            else => return null,
        };

        if (@typeInfo(KV) != .Struct) return null;

        if (!@hasField(KV, "key")) return null;
        const Key = @TypeOf(@as(KV, undefined).key);

        if (!@hasField(KV, "value")) return null;
        const Value = @TypeOf(@as(KV, undefined).value);

        const TypeFn = if (is_managed) std.ArrayHashMap else std.ArrayHashMapUnmanaged;
        if (TypeFn(Key, Value, Context, store_hash) != HashMapType) return null;

        return .{
            .Key = Key,
            .Value = Value,
            .Context = Context,
            .store_hash = store_hash,
            .allocator_kind = if (is_managed) .managed else .unmanaged,
        };
    }
}

const std = @import("std");
const assert = std.debug.assert;

const bc = @import("../bincode.zig");
const DataFormat = bc.fmt.DataFormat;
const dataFormat = bc.fmt.dataFormat;
