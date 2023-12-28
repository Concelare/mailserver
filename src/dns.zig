// Zig Imports
const std = @import("std");
const regex = @import("regex").Regex;

// C Imports
const re = @cImport(@cInclude("regez.h"));

pub const DNSRecord = struct { name: []u8, type: []u8, address: []u8 };

pub fn get_mx_record(alloc: std.mem.Allocator, domain: []const u8) !DNSRecord {
    var thread: std.ChildProcess = std.ChildProcess.init(&.{ "dig", domain, "MX", "+noall", "+answer", "+short" }, alloc);

    thread.stdout_behavior = .Pipe;
    thread.spawn() catch |err| {
        return err;
    };

    const max_output_size = 100 * 1024 * 1024;

    const bytes: []const u8 = try thread.stdout.?.reader().readAllAlloc(alloc, max_output_size);
    errdefer alloc.free(bytes);
    defer alloc.free(bytes);
    const term = try thread.wait();

    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                std.log.warn("DNS MX Query Failed With Code: {any}", .{code});
                return DNSRecord{ .name = "", .type = "", .address = "" };
            }
        },
        else => {
            std.log.warn("DNS MX Query Failed To Resolve", .{});
            return DNSRecord{ .name = "", .type = "", .address = "" };
        },
    }

    var iter = std.mem.splitSequence(u8, bytes, " ");
    iter.index = 3;

    var testing: []const u8 = iter.next().?;

    testing = testing[0 .. testing.len - 2];

    var value = try regex.compile(alloc, "([0-9])\\.([0-9])\\.([0-9])\\.([0-9])");
    defer value.deinit();

    const found = try regex.match(&value, testing);

    if (found) {
        var x: DNSRecord = .{ .name = @constCast(domain), .type = @constCast("MX"), .address = @constCast(testing) };
        return x;
    }

    var thread2: std.ChildProcess = std.ChildProcess.init(&.{ "dig", testing, "+noall", "+answer", "+short" }, alloc);

    thread2.stdout_behavior = .Pipe;

    thread2.spawn() catch |err| {
        return err;
    };

    var bytes_ip: []u8 = try thread2.stdout.?.reader().readAllAlloc(alloc, max_output_size);
    errdefer alloc.free(bytes_ip);
    const term2 = try thread2.wait();

    switch (term2) {
        .Exited => |code| {
            if (code != 0) {
                std.log.warn("DNS CNAME Query Failed With Code: {any}", .{code});
                return DNSRecord{ .name = "", .type = "", .address = "" };
            }
        },
        else => {
            std.log.warn("DNS CNAME Query Failed To Resolve", .{});
            return DNSRecord{ .name = "", .type = "", .address = "" };
        },
    }

    bytes_ip = bytes_ip[0 .. bytes_ip.len - 1];

    return .{ .name = @constCast(domain), .type = @constCast("MX"), .address = bytes_ip };
}

test "MX Record Testing" {
    var testing = try GetMXRecord(&std.testing.allocator, "gmail.com");
    try std.testing.expect(testing != null);
}
