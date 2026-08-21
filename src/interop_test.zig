const std = @import("std");
const bzip2 = @import("bzip2.zig");
const testing = std.testing;

const interop_text_line = "Firmware image compatibility vector: bzip2 1.0.8 / bzip2z.\n";
const interop_firmware_size = 1_200_000;

fn makeInteropText(allocator: std.mem.Allocator) ![]u8 {
    const data = try allocator.alloc(u8, interop_text_line.len * 256);
    for (0..256) |i| {
        @memcpy(data[i * interop_text_line.len ..][0..interop_text_line.len], interop_text_line);
    }
    return data;
}

fn makeInteropBinary(allocator: std.mem.Allocator) ![]u8 {
    const data = try allocator.alloc(u8, 65_536);
    for (data, 0..) |*byte, i| {
        byte.* = @truncate(i * 37 + (i >> 3) * 11);
    }
    return data;
}

fn makeInteropFirmware(allocator: std.mem.Allocator) ![]u8 {
    const data = try allocator.alloc(u8, interop_firmware_size);
    for (data, 0..) |*byte, i| {
        const page = i / 4096;
        const offset = i % 4096;
        byte.* = @truncate(
            (offset * 73 + (offset >> 3) * 19 + page * 29) ^
                (page >> 2) ^
                (offset >> 7),
        );
    }
    return data;
}

fn expectInteropDecode(compressed: []const u8, expected: []const u8) !void {
    const decoded = try bzip2.decompress(testing.allocator, compressed);
    defer testing.allocator.free(decoded);
    try testing.expectEqualSlices(u8, expected, decoded);
}

fn findBits(data: []const u8, pattern: u48) ?usize {
    if (data.len * 8 < 48) return null;
    var bit_index: usize = 32;
    while (bit_index + 48 <= data.len * 8) : (bit_index += 1) {
        var candidate: u48 = 0;
        for (0..48) |offset| {
            const absolute = bit_index + offset;
            const bit = (data[absolute / 8] >> @intCast(7 - (absolute % 8))) & 1;
            candidate = (candidate << 1) | bit;
        }
        if (candidate == pattern) return bit_index;
    }
    return null;
}

test "decode deterministic libbz2 1.0.8 compatibility fixtures" {
    const allocator = testing.allocator;

    const text = try makeInteropText(allocator);
    defer allocator.free(text);
    try expectInteropDecode(
        @embedFile("testdata/libbz2-1.0.8-text.bz2"),
        text,
    );

    const binary = try makeInteropBinary(allocator);
    defer allocator.free(binary);
    try expectInteropDecode(
        @embedFile("testdata/libbz2-1.0.8-binary.bz2"),
        binary,
    );

    const firmware = try makeInteropFirmware(allocator);
    defer allocator.free(firmware);
    try expectInteropDecode(
        @embedFile("testdata/libbz2-1.0.8-firmware-multiblock.bz2"),
        firmware,
    );
}

test "single-stream compression is byte-compatible with libbz2 1.0.8" {
    const allocator = testing.allocator;
    const input = [_]u8{0xa5} ** 100;

    const compressed = try bzip2.compressWithOptions(allocator, &input, .{
        .level = 9,
        .threads = 1,
        .multi_stream = false,
    });
    defer allocator.free(compressed);

    try testing.expectEqualSlices(
        u8,
        @embedFile("testdata/libbz2-1.0.8-single-stream.bz2"),
        compressed,
    );
}

test "libbz2 fixture rejects corrupted block CRC" {
    const allocator = testing.allocator;
    const fixture = @embedFile("testdata/libbz2-1.0.8-text.bz2");
    const corrupted = try allocator.dupe(u8, fixture);
    defer allocator.free(corrupted);

    // Stream header (4 bytes), block magic (6 bytes), then block CRC.
    corrupted[10] ^= 0x80;
    try testing.expectError(bzip2.Error.BlockCrcMismatch, bzip2.decompress(allocator, corrupted));
}

test "libbz2 fixture rejects corrupted stream CRC" {
    const allocator = testing.allocator;
    const fixture = @embedFile("testdata/libbz2-1.0.8-text.bz2");
    const corrupted = try allocator.dupe(u8, fixture);
    defer allocator.free(corrupted);

    const footer_bit = findBits(corrupted, bzip2.FOOTER_MAGIC) orelse return error.TestUnexpectedResult;
    const crc_bit = footer_bit + 48;
    corrupted[crc_bit / 8] ^= @as(u8, 0x80) >> @intCast(crc_bit % 8);
    try testing.expectError(bzip2.Error.StreamCrcMismatch, bzip2.decompress(allocator, corrupted));
}

test "libbz2 fixture rejects truncation at stream boundaries" {
    const allocator = testing.allocator;
    const fixture = @embedFile("testdata/libbz2-1.0.8-text.bz2");
    const boundaries = [_]usize{
        0,
        1,
        3,
        4,
        9,
        10,
        fixture.len / 2,
        fixture.len - 10,
        fixture.len - 1,
    };

    for (boundaries) |boundary| {
        try testing.expectError(bzip2.Error.UnexpectedEof, bzip2.decompress(allocator, fixture[0..boundary]));
    }
}

test "libbz2 fixture validates invalid magic and trailing bytes" {
    const allocator = testing.allocator;
    const fixture = @embedFile("testdata/libbz2-1.0.8-text.bz2");

    const invalid_magic = try allocator.dupe(u8, fixture);
    defer allocator.free(invalid_magic);
    invalid_magic[0] = 'X';
    try testing.expectError(bzip2.Error.InvalidMagic, bzip2.decompress(allocator, invalid_magic));

    const short_trailing = try std.mem.concat(allocator, u8, &.{ fixture, &.{ 0xaa, 0xbb, 0xcc } });
    defer allocator.free(short_trailing);
    try expectInteropDecode(short_trailing, interop_text_line ** 256);
}
