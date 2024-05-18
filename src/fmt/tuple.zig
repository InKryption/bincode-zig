pub inline fn format(
    /// Struct or tuple whose fields are all `fmt.DataFormat(...)`,
    /// with each field name corresponding to one in the struct for
    /// which this will be used to encode/decode.
    /// Comptime fields and zero-sized fields are to be excluded.
    field_fmts: anytype,
) Format(@TypeOf(field_fmts)) {
    return .{ .field_fmts = field_fmts };
}

fn verifyFields(comptime T: type, comptime FieldFormats: type) !void {
    comptime {
        const data_info = @typeInfo(T).Struct;
        @setEvalBranchQuota(data_info.fields.len + 1);

        const FieldFormatId = std.meta.FieldEnum(FieldFormats);
        var ignored_fields = std.EnumSet(FieldFormatId).initFull();

        for (data_info.fields) |field| {
            if (field.is_comptime or
                @sizeOf(field.type) == 0 //
            ) {
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

        return;
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
            return EncodeDecodeErrorSets(Value).Encode;
        }
        pub inline fn encode(
            ctx: Self,
            int_config: bincode.int.Config,
            /// `*const T`, where `@typeInfo(T) == .Struct`
            value: anytype,
            writer: anytype,
        ) !void {
            comptime verifyFields(@TypeOf(value.*), FieldFormats) catch |e| @compileError(@errorName(e));

            @setEvalBranchQuota(fmt_info.fields.len * 3 + 1);
            inline for (fmt_info.fields) |field| {
                const field_value = &@field(value, field.name);
                const field_fmt = dataFormat(@field(ctx.field_fmts, field.name));
                try field_fmt.encode(int_config, field_value, writer);
            }
        }

        pub fn DecodeError(comptime Value: type) type {
            verifyFields(Value, FieldFormats) catch return error{};
            return EncodeDecodeErrorSets(Value).Decode;
        }
        pub inline fn decode(
            ctx: Self,
            int_config: bincode.int.Config,
            /// `*T`, where `@typeInfo(T) == .Struct`
            value: anytype,
            reader: anytype,
            allocator: std.mem.Allocator,
        ) !void {
            comptime verifyFields(@TypeOf(value.*), FieldFormats) catch |e| @compileError(@errorName(e));

            @setEvalBranchQuota(fmt_info.fields.len * 4 + 1);
            inline for (fmt_info.fields, 0..) |field, initialized_fields| {
                errdefer ctx.freeDecodedFieldsPartial(int_config, value, initialized_fields, allocator);

                const field_value = &@field(value, field.name);
                const field_fmt = dataFormat(@field(ctx.field_fmts, field.name));
                try field_fmt.decode(int_config, field_value, reader, allocator);
            }
        }

        pub inline fn freeDecoded(
            ctx: Self,
            int_config: bincode.int.Config,
            /// `*const T`, where `@typeInfo(T) == .Struct`
            value: anytype,
            allocator: std.mem.Allocator,
        ) void {
            comptime verifyFields(@TypeOf(value.*), FieldFormats) catch |e| @compileError(@errorName(e));
            ctx.freeDecodedFieldsPartial(int_config, value, fmt_info.fields.len, allocator);
        }

        inline fn freeDecodedFieldsPartial(
            ctx: Self,
            int_config: bincode.int.Config,
            value: anytype,
            comptime up_to: usize,
            allocator: std.mem.Allocator,
        ) void {
            @setEvalBranchQuota(fmt_info.fields.len * 3 + 1);
            inline for (fmt_info.fields[0..up_to]) |field| {
                const field_value = &@field(value, field.name);
                const field_fmt = dataFormat(@field(ctx.field_fmts, field.name));
                field_fmt.freeDecoded(int_config, field_value, allocator);
            }
        }
    };
}

const bincode = @import("../bincode.zig");
const DataFormat = bincode.fmt.DataFormat;
const dataFormat = bincode.fmt.dataFormat;

const std = @import("std");
