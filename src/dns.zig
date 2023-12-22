// Zig Imports
const std = @import("std");

// Zig Imports
const regex = @cImport(@cInclude("regex.h"));

pub const DNSRecord = struct {
    name: []u8,
    type: []u8,
    address: []u8,
    ttl: u32,
};

pub fn GetMXRecord(allocator: *const std.mem.Allocator, domain: []const u8) !?DNSRecord {
    var alloc: std.mem.Allocator = @constCast(allocator);

    const thread: std.ChildProcess = std.ChildProcess.init(.{ "dig", domain, "MX +noall +answer +short" }, alloc) catch |err| {
        std.log.warn("DNS Dig Command Initialisation Failed\n", .{});
        return err;
    };

    thread.stdout_behavior = .Pipe;
    thread.spawn();

    const max_output_size = 100 * 1024 * 1024;

    const bytes: []u8 = try thread.stdout.?.reader().readAllAlloc(alloc, max_output_size);
    errdefer alloc.free(bytes);

    const term = try thread.wait();

    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                std.log.warn("DNS MX Query Failed With Code: {any}", .{code});
                return .{};
            }
        },
        else => {
            std.log.warn("The following command terminated unexpectedly:\n", .{});
            return .{};
        },
    }

    var iter = std.mem.split(u8, bytes, " ");

    iter.index = iter.index.? + 1;

    var field = iter.next().?;


    if ()

    const thread2: std.ChildProcess = std.ChildProcess.init(.{ "dig", field, "+noall +answer +short" }, alloc) catch |err| {
        std.log.warn("DNS Dig Command Initialisation", .{});
        return err;
    };

    thread2.stdout_behavior = .Pipe;

    const bytes_ip: []u8 = try thread2.stdout.?.reader().readAllAlloc(alloc, max_output_size);
    errdefer alloc.free(bytes_ip);
}
