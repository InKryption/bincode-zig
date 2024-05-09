pub inline fn format(
    comptime T: type,
    /// Struct or tuple whose fields are all `fmt.DataFormat(...)`,
    /// with each field name corresponding to one in `T`.
    /// Comptime fields and zero-sized fields are excluded.
    field_fmts: anytype,
) Format(T, @TypeOf(field_fmts)) {
    return .{ .field_fmts = field_fmts };
}

pub fn Format(comptime T: type, comptime FieldFormats: type) type {
    const fmt_info = @typeInfo(FieldFormats).Struct;

    {
        const data_info = @typeInfo(T).Struct;
        @setEvalBranchQuota(data_info.fields.len + 1);

        var required_field_count: usize = 0;
        for (data_info.fields) |field| {
            if (field.is_comptime or
                @sizeOf(field.type) == 0 //
            ) {
                if (@hasField(FieldFormats, field.name)) @compileError(
                    "Format field '" ++ field.name ++ "' is ignored",
                );
            } else {
                required_field_count += 1;
                if (!@hasField(FieldFormats, field.name)) @compileError(
                    "Format field for '" ++ field.name ++ "' is missing",
                );
            }
        }

        if (fmt_info.fields.len != required_field_count) {
            @compileError("Unrecognized format fields");
        }
    }

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
            return EncodeDecodeErrorSets(Value).Encode;
        }
        pub inline fn encode(
            ctx: Self,
            int_config: bincode.int.Config,
            value: *const T,
            writer: anytype,
        ) !void {
            @setEvalBranchQuota(fmt_info.fields.len * 3 + 1);
            inline for (fmt_info.fields) |field| {
                const field_value = &@field(value, field.name);
                const field_fmt = dataFormat(@field(ctx.field_fmts, field.name));
                try field_fmt.encode(int_config, field_value, writer);
            }
        }

        pub fn DecodeError(comptime Value: type) type {
            return EncodeDecodeErrorSets(Value).Decode;
        }
        pub inline fn decode(
            ctx: Self,
            int_config: bincode.int.Config,
            value: *T,
            reader: anytype,
        ) !void {
            @setEvalBranchQuota(fmt_info.fields.len * 4 + 1);
            inline for (fmt_info.fields, 0..) |field, initialized_fields| {
                errdefer ctx.freeDecodedPartial(int_config, value, initialized_fields);

                const field_value = &@field(value, field.name);
                const field_fmt = dataFormat(@field(ctx.field_fmts, field.name));
                try field_fmt.decode(int_config, field_value, reader);
            }
        }

        pub inline fn freeDecoded(
            ctx: Self,
            int_config: bincode.int.Config,
            value: *const T,
        ) void {
            ctx.freeDecodedPartial(int_config, value, fmt_info.fields.len);
        }

        inline fn freeDecodedPartial(
            ctx: Self,
            int_config: bincode.int.Config,
            value: *const T,
            comptime up_to: usize,
        ) void {
            @setEvalBranchQuota(fmt_info.fields.len * 3 + 1);
            inline for (fmt_info.fields[0..up_to]) |field| {
                const field_value = &@field(value, field.name);
                const field_fmt = dataFormat(@field(ctx.field_fmts, field.name));
                field_fmt.freeDecoded(int_config, field_value);
            }
        }
    };
}

const bincode = @import("../bincode.zig");
const DataFormat = bincode.fmt.DataFormat;
const dataFormat = bincode.fmt.dataFormat;
