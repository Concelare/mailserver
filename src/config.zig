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
            std.log.info("Config file not found, Created Config File Please fill in", .{});
            switch (err) {
                error.FileNotFound => {
                    std.fs.cwd().createFile("config.json", .{ .exclusive = true }) catch |cerr| {
                        std.log.info("Failed to Create Config File", .{});
                        return cerr;
                    };
                    return err;
                },
            }
        };

        const data = std.fs.cwd().readFileAlloc(allocator, "config.json", 512) catch |err| {
            std.log.err("Failed to read config file.", .{});
            return err;
        };
        defer allocator.free(data);

        var config = std.json.parseFromSlice(Config, allocator, data, .{ .allocate = .alloc_always }) catch |err| {
            std.log.err("Failed to parse config.", .{});
            return err;
        };

        return config.value;
    }
};
