const std = @import("std");
const clap = @import("clap");
const base64 = @import("base64.zig");

// TODO: Use buffered IO.
var stderr = std.io.getStdErr().writer();
var stdout = std.io.getStdOut().writer();

const ParamsCheckError = error{ NoActionSpecified, BothDecodeAndEncode };
fn checkParams(comptime T: type, clap_result: T) ParamsCheckError!void {
    if (clap_result.args.encode == 0 and clap_result.args.decode == 0) {
        return ParamsCheckError.NoActionSpecified;
    }

    if (clap_result.args.encode != 0 and clap_result.args.decode != 0) {
        return ParamsCheckError.BothDecodeAndEncode;
    }

    return;
}

fn encode(allocator: std.mem.Allocator, input: []const u8) !void {
    const encoded = try base64.encode(allocator, input);
    defer allocator.free(encoded);

    try stdout.print("{s}\n", .{encoded});
    return;
}

fn decode(allocator: std.mem.Allocator, input: []const u8) !void {
    const decoded = try base64.decode(allocator, input);
    defer allocator.free(decoded);

    try stdout.print("{s}\n", .{decoded});
    return;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // TODO: Check return value.
    defer _ = gpa.deinit();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help display help message and exit
        \\-e, --encode encode string or byte stream into base64
        \\-d, --decode decode base64 string into bytes
        \\<STR> string to be decoded or encoded
    );

    const parsers = comptime .{
        .STR = clap.parsers.string,
    };

    var clap_diagnostics = clap.Diagnostic{};
    var clap_result = clap.parse(clap.Help, &params, parsers, .{
        .allocator = gpa.allocator(),
        .diagnostic = &clap_diagnostics,
    }) catch |err| {
        try clap_diagnostics.report(stderr, err);
        return err;
    };
    defer clap_result.deinit();

    if (clap_result.args.help != 0 or clap_result.positionals.len == 0) {
        return clap.help(stderr, clap.Help, &params, .{
            .description_on_new_line = false,
            .spacing_between_parameters = 0,
            .description_indent = 0,
            .indent = 2,
        });
    }

    checkParams(@TypeOf(clap_result), clap_result) catch |err| return switch (err) {
        ParamsCheckError.NoActionSpecified => _ =
            try stderr.write("error: no action was specified\n"),
        ParamsCheckError.BothDecodeAndEncode => _ =
            try stderr.write("error: both -e and -d specified\n"),
    };

    const input = clap_result.positionals[0];
    if (clap_result.args.encode != 0) {
        try encode(gpa.allocator(), input);
    } else {
        try decode(gpa.allocator(), input);
    }

    return;
}
