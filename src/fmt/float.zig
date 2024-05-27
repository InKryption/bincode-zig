pub const format: Format = .{};

pub const Format = struct {
    pub const EncodeError = error{};
    pub inline fn encode(
        _: Format,
        int_config: bc.int.Config,
        /// `*const T`, where `@typeInfo(T) == .Int`
        value: anytype,
        writer: anytype,
    ) !void {
        const T = @TypeOf(value.*);
        const AsInt = switch (T) {
            f32 => u32,
            f64 => u64,
            else => @compileError("Expected f32 or f64, got " ++ @typeName(T)),
        };
        const as_int: AsInt = @bitCast(value.*);
        const as_int_endian: AsInt = std.mem.nativeTo(AsInt, as_int, int_config.endian);
        const as_bytes = std.mem.asBytes(&as_int_endian);
        try writer.writeAll(as_bytes);
    }

    pub const DecodeError = error{PrematureEof};
    pub inline fn decode(
        _: Format,
        int_config: bc.int.Config,
        /// `*T`, where `@typeInfo(T) == .Int`
        value: anytype,
        reader: anytype,
        allocator: std.mem.Allocator,
    ) !void {
        _ = allocator;
        const T = @TypeOf(value.*);
        const AsInt = switch (T) {
            f32 => u32,
            f64 => u64,
            else => @compileError("Expected f32 or f64, got " ++ @typeName(T)),
        };
        const as_bytes align(@alignOf(AsInt)) = blk: {
            var as_bytes: [@sizeOf(AsInt)]u8 align(@alignOf(AsInt)) = undefined;
            if (try reader.readAll(&as_bytes) != as_bytes.len) {
                return DecodeError.PrematureEof;
            }
            break :blk as_bytes;
        };
        const as_int_endian: *const AsInt = std.mem.bytesAsValue(AsInt, &as_bytes);
        const as_int = std.mem.toNative(AsInt, as_int_endian.*, int_config.endian);
        value.* = @bitCast(as_int);
    }

    pub inline fn freeDecoded(
        _: Format,
        int_config: bc.int.Config,
        /// `*const T`, where `@typeInfo(T) == .Int`
        value: anytype,
        allocator: std.mem.Allocator,
    ) void {
        _ = int_config;
        _ = allocator;
        const T = @TypeOf(value.*);
        switch (T) {
            f32, f64 => {},
            else => @compileError("Expected f32 or f64, got " ++ @typeName(T)),
        }
    }
};

const bc = @import("../bincode.zig");
const std = @import("std");
const assert = std.debug.assert;
