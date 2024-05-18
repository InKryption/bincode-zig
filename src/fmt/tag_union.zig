pub inline fn format(
    /// Struct or tuple whose fields are all `fmt.DataFormat(...)`,
    /// with each field name corresponding to one in the tagged union for
    /// which this will be used to encode/decode.
    /// Comptime fields and zero-sized fields are to be excluded.
    field_fmts: anytype,
) Format(@TypeOf(field_fmts)) {
    return .{ .field_fmts = field_fmts };
}

fn verifyFields(comptime T: type, comptime FieldFormats: type) !void {
    comptime {
        const data_info = @typeInfo(T).Union;
        @setEvalBranchQuota(data_info.fields.len + 1);

        const FieldFormatId = std.meta.FieldEnum(FieldFormats);
        var ignored_fields = std.EnumSet(FieldFormatId).initFull();

        for (data_info.fields) |field| {
            if (@sizeOf(field.type) == 0) {
                if (@hasField(FieldFormats, field.name)) {
                    return @field(anyerror, "Format field '" ++ field.name ++ "' is ignored");
                }
            } else {
                if (!@hasField(FieldFormats, field.name)) {
                    return @field(anyerror, "Format field for '" ++ field.name ++ "' is missing");
                }
                ignored_fields.setPresent(@field(FieldFormatId, field.name), false);
            }
        }

        var iter = ignored_fields.iterator();
        if (iter.next()) |field_id| {
            return @field(anyerror, "Format field '" ++ @tagName(field_id) ++ "' is ignored");
        }
    }
}

pub fn Format(comptime FieldFormats: type) type {
    const fmt_info = @typeInfo(FieldFormats).Struct;

    return struct {
        field_fmts: FieldFormats,
        const Self = @This();

        fn EncodeDecodeErrorSets(comptime Value: type) struct { Encode: type, Decode: type } {
            var FieldEncodeError = error{};
            var FieldDecodeError = error{};

            @setEvalBranchQuota(fmt_info.fields.len + 1);
            for (fmt_info.fields) |field| {
                const FieldType = @TypeOf(@field(@as(Value, undefined), field.name));
                FieldEncodeError = FieldEncodeError || DataFormat(field.type).EncodeError(FieldType);
                FieldDecodeError = FieldDecodeError || DataFormat(field.type).DecodeError(FieldType);
            }

            return .{
                .Encode = FieldEncodeError,
                .Decode = FieldDecodeError,
            };
        }

        pub fn EncodeError(comptime Value: type) type {
            verifyFields(Value, FieldFormats) catch return error{};
            return bincode.fmt.int.Format(.unrounded).EncodeError || EncodeDecodeErrorSets(Value).Encode;
        }
        pub inline fn encode(
            ctx: Self,
            int_config: bincode.int.Config,
            /// `*const T`, where `@typeInfo(T) == .Struct`
            value: anytype,
            writer: anytype,
        ) !void {
            const T = @TypeOf(value.*);
            comptime verifyFields(T, FieldFormats) catch |e| @compileError(@errorName(e));

            @setEvalBranchQuota(fmt_info.fields.len * 3 + 1);
            switch (value.*) {
                inline else => |*payload_value, tag| {
                    // take advantage of `std.meta.FieldEnum` always having numerically consecutive tags.
                    const tag_index: u32 = @intFromEnum(@field(std.meta.FieldEnum(T), @tagName(tag)));
                    try dataFormat(bincode.fmt.int.format(.unrounded)).encode(int_config, &tag_index, writer);

                    if (@sizeOf(@TypeOf(payload_value.*)) == 0) return;
                    const payload_fmt = dataFormat(@field(ctx.field_fmts, @tagName(tag)));
                    try payload_fmt.encode(int_config, payload_value, writer);
                },
            }
        }

        pub fn DecodeError(comptime Value: type) type {
            verifyFields(Value, FieldFormats) catch return error{};
            return error{InvalidDiscriminant} ||
                bincode.fmt.int.Format(.unrounded).DecodeError ||
                EncodeDecodeErrorSets(Value).Decode;
        }
        pub inline fn decode(
            ctx: Self,
            int_config: bincode.int.Config,
            /// `*T`, where `@typeInfo(T) == .Struct`
            value: anytype,
            reader: anytype,
            allocator: std.mem.Allocator,
        ) !void {
            const T = @TypeOf(value.*);
            comptime verifyFields(@TypeOf(value.*), FieldFormats) catch |e| @compileError(@errorName(e));

            @setEvalBranchQuota(fmt_info.fields.len * 4 + 1);
            const field_tag_index = blk: {
                var tag_index: u32 = undefined;
                try dataFormat(bincode.fmt.int.format(.unrounded)).decode(int_config, &tag_index, reader, allocator);
                break :blk tag_index;
            };
            const field_tag: std.meta.FieldEnum(T) = std.meta.intToEnum(std.meta.FieldEnum(T), field_tag_index) catch |err| switch (err) {
                error.InvalidEnumTag => return DecodeError(T).InvalidDiscriminant,
            };

            switch (field_tag) {
                inline else => |tag| {
                    value.* = @unionInit(T, @tagName(tag), undefined);
                    const payload_value = &@field(value, @tagName(tag));

                    if (@sizeOf(@TypeOf(payload_value.*)) == 0) return;
                    const payload_fmt = dataFormat(@field(ctx.field_fmts, @tagName(tag)));
                    try payload_fmt.decode(int_config, payload_value, reader, allocator);
                },
            }
        }

        pub inline fn freeDecoded(
            ctx: Self,
            int_config: bincode.int.Config,
            /// `*const T`, where `@typeInfo(T) == .Struct`
            value: anytype,
            allocator: std.mem.Allocator,
        ) void {
            @setEvalBranchQuota(fmt_info.fields.len * 4 + 1);
            switch (value.*) {
                inline else => |*payload_value, tag| {
                    if (@sizeOf(@TypeOf(payload_value.*)) == 0) return;
                    const payload_fmt = dataFormat(@field(ctx.field_fmts, @tagName(tag)));
                    payload_fmt.freeDecoded(int_config, payload_value, allocator);
                },
            }
        }
    };
}

const bincode = @import("../bincode.zig");
const DataFormat = bincode.fmt.DataFormat;
const dataFormat = bincode.fmt.dataFormat;

const std = @import("std");
