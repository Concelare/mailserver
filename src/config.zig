const std = @import("std");

pub const Encryption = enum { plain, tls, start_tls };

pub const Config = struct {
    hostname: []const u8,
    require_tls: bool,
    certs: []const u8,
    encryption: Encryption,
    timeout: i32,

    pub fn init(allocator: std.mem.Allocator) !Config {
        std.fs.cwd().access("config.json", .{}) catch |err| {
            std.log.err("Config file not found, Created Config File Please fill in", .{});
            switch (err) {
                error.FileNotFound => {
                    var file = std.fs.cwd().createFile("config.json", .{ .exclusive = true }) catch |cerr| {
                        std.log.info("Failed to Create Config File", .{});
                        return cerr;
                    };

                    const default: Config = .{ .hostname = "unknown", .require_tls = false, .certs = "set path", .encryption = .plain, .timeout = 10_000 };

                    var string = std.ArrayList(u8).init(allocator);
                    defer string.deinit();

                    try std.json.stringify(default, .{}, string.writer());

                    try file.writeAll(string.items);
                    return err;
                },
                else => {
                    std.log.err("Unknown Error Occurred Reading Config", .{});
                    return err;
                },
            }
        };

        const data = std.fs.cwd().readFileAlloc(allocator, "config.json", 512) catch |err| {
            std.log.err("Failed to read config file.", .{});
            return err;
        };
        defer allocator.free(data);

        const config = std.json.parseFromSlice(Config, allocator, data, .{ .allocate = .alloc_always }) catch |err| {
            std.log.err("Failed to parse config.", .{});
            return err;
        };

        return config.value;
    }
};
