const std = @import("std");

const padding_symbol: u8 = '=';
const padding_index: u8 = 64;
const table =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ" ++
    "abcdefghijklmnopqrstuvwxyz" ++
    "0123456789+/" ++
    std.fmt.comptimePrint("{c}", .{padding_symbol});
const table_inv_len = 255;
const table_inv = invert: {
    var result: [table_inv_len]u8 = [1]u8{0} ** table_inv_len;
    for (table, 0..) |c, i| {
        result[c] = i;
    }

    break :invert result;
};

test "table_inv" {
    try std.testing.expectEqual(table_inv['A'], 0);
    try std.testing.expectEqual(table_inv['B'], 1);
    try std.testing.expectEqual(table_inv['='], 64);

    for (table, 0..) |x, i| {
        try std.testing.expectEqual(table_inv[x], i);
    }
}

fn getEncodedLength(decodedLength: usize) usize {
    return switch (decodedLength) {
        0 => 0,
        1...3 => 4,
        // TODO: Think of some optimization without division.
        else => {
            return 4 * (std.math.divCeil(usize, decodedLength, 3) catch unreachable);
        },
    };
}

test "getEncodedLength" {
    const decoded_lengths = [_]usize{ 0, 1, 2, 3, 4, 5, 6 };
    const expected_encoded_lengths = [_]usize{ 0, 4, 4, 4, 8, 8, 8 };

    for (decoded_lengths, expected_encoded_lengths) |decoded_length, expected| {
        std.debug.print("\nTRY {}\n", .{decoded_length});
        const result = getEncodedLength(decoded_length);
        std.debug.print("\tRESULT: {}\n", .{decoded_length});
        std.debug.print("\tEXPECTED: {}\n", .{decoded_length});
        try std.testing.expectEqual(expected, result);
        std.debug.print("\tOK\n", .{});
    }
}

inline fn firstSextetIndex(n: u8) u8 {
    return n >> 2;
}

inline fn secondSextetIndex(n: u8, m: u8) u8 {
    return ((n & 0b0000_0011) << 4) + (m >> 4);
}

inline fn thirdSextetIndex(n: u8, m: u8) u8 {
    return ((n & 0b0000_1111) << 2) + (m >> 6);
}

inline fn fourthSextetIndex(n: u8) u8 {
    return n & 0b0011_1111;
}

/// Encode bytes in base64 encoding.
pub fn encode(allocator: std.mem.Allocator, decoded: []const u8) ![]const u8 {
    const encoded_length = getEncodedLength(decoded.len);
    const encoded = try allocator.alloc(u8, encoded_length);
    errdefer allocator.free(encoded);

    // TODO: Extract 3 into constant, make buffer variable.
    var buffer = [3]u8{ 0, 0, 0 };
    var buffer_i: u8 = 0;
    var encoded_i: u8 = 0;

    for (decoded) |d| {
        buffer[buffer_i] = d;
        buffer_i += 1;

        if (buffer_i == 3) {
            encoded[encoded_i] = table[firstSextetIndex(buffer[0])];
            encoded[encoded_i + 1] = table[secondSextetIndex(buffer[0], buffer[1])];
            encoded[encoded_i + 2] = table[thirdSextetIndex(buffer[1], buffer[2])];
            encoded[encoded_i + 3] = table[fourthSextetIndex(buffer[2])];

            encoded_i += 4;
            buffer_i = 0;
        }
    }

    if (buffer_i == 1) {
        encoded[encoded_i] = table[firstSextetIndex(buffer[0])];
        encoded[encoded_i + 1] = table[secondSextetIndex(buffer[0], 0)];
        encoded[encoded_i + 2] = padding_symbol;
        encoded[encoded_i + 3] = padding_symbol;
    }

    if (buffer_i == 2) {
        encoded[encoded_i] = table[firstSextetIndex(buffer[0])];
        encoded[encoded_i + 1] = table[secondSextetIndex(buffer[0], buffer[1])];
        encoded[encoded_i + 2] = table[thirdSextetIndex(buffer[1], 0)];
        encoded[encoded_i + 3] = padding_symbol;
    }

    return encoded;
}

test "encode" {
    const xs = [_][]const u8{ "", "abc", "abcabc", "hi" };
    const ys = [_][]const u8{ "", "YWJj", "YWJjYWJj", "aGk=" };

    for (xs, ys) |x, y| {
        std.debug.print("\nTRY {s}\n", .{x});

        const result = try encode(std.testing.allocator, x);
        defer std.testing.allocator.free(result);

        std.debug.print("\tRESULT: {s}\n", .{result});
        std.debug.print("\tEXPECTED: {s}\n", .{y});

        try std.testing.expect(std.mem.eql(u8, y, result));

        std.debug.print("\tOK\n", .{});
    }
}

inline fn firstByte(n: u8, m: u8) u8 {
    return (n << 2) + (m >> 4);
}

inline fn secondByte(n: u8, m: u8) u8 {
    return (n << 4) + (m >> 2);
}

inline fn thirdByte(n: u8, m: u8) u8 {
    return (n << 6) + m;
}

inline fn getLastBatch(encoded: []const u8) []const u8 {
    return encoded[encoded.len - 4 ..];
}

// Called when encoded.len <= 4
fn getSmallDecodedLength(encoded: []const u8) usize {
    if (encoded[3] != padding_symbol) {
        return 3;
    }

    if (encoded[2] != padding_symbol) {
        return 2;
    }

    return 1;
}

fn getDecodedLength(encoded: []const u8) usize {
    return switch (encoded.len) {
        0 => 0,
        1...4 => getSmallDecodedLength(encoded),
        // TODO: Think of some optimization without division.
        else => {
            const last_batch = getLastBatch(encoded);
            const divided = std.math.divFloor(usize, encoded.len, 4) catch unreachable;
            return 3 * (divided - 1) + getSmallDecodedLength(last_batch);
        },
    };
}

// TODO: Consider invalid encoded strings.
/// Decode base64 string into an array of bytes.
pub fn decode(allocator: std.mem.Allocator, encoded: []const u8) ![]const u8 {
    const decoded_length = getDecodedLength(encoded);
    const decoded = try allocator.alloc(u8, decoded_length);
    errdefer allocator.free(decoded);

    // TODO: Extract 3 into constant, make buffer variable.
    var buffer = [4]u8{ 0, 0, 0, 0 };
    var buffer_i: u8 = 0;
    var decoded_i: u8 = 0;

    for (encoded) |e| {
        buffer[buffer_i] = table_inv[e];
        buffer_i += 1;

        if (buffer_i == 4) {
            decoded[decoded_i] = firstByte(buffer[0], buffer[1]);
            if (buffer[2] != padding_index) {
                decoded[decoded_i + 1] = secondByte(buffer[1], buffer[2]);
            }
            if (buffer[3] != padding_index) {
                decoded[decoded_i + 2] = thirdByte(buffer[2], buffer[3]);
            }

            decoded_i += 3;
            buffer_i = 0;
        }
    }

    if (buffer_i != 0) {
        // TODO: Return error.
    }

    return decoded;
}

test "decode" {
    const xs = [_][]const u8{ "", "abc", "abcabc", "hi", "abcd", "abcde", "abcdef", "abcdefg" };
    const ys = [_][]const u8{ "", "YWJj", "YWJjYWJj", "aGk=", "YWJjZA==", "YWJjZGU=", "YWJjZGVm", "YWJjZGVmZw==" };

    for (xs, ys) |x, y| {
        std.debug.print("\nTRY {s}\n", .{y});

        const result = try decode(std.testing.allocator, y);
        defer std.testing.allocator.free(result);

        std.debug.print("\tRESULT: {s}\n", .{result});
        std.debug.print("\tEXPECTED: {s}\n", .{x});

        try std.testing.expect(std.mem.eql(u8, x, result));

        std.debug.print("\tOK\n", .{});
    }
}
