// Imports
const std = @import("std");
const Config = @import("config.zig");
const pg = @import("pg");
const User = @import("user.zig");
const Email = @import("email.zig");
const time = std.time;
const crypto = std.crypto;
const rand = std.rand;
const fs = std.fs;
const io = std.io;
const heap = std.heap;

pub const Command = enum {
    Login,
    Select,
    Fetch,
    Store,
    Namespace,
    Unknown,
};

pub fn listener(config: *Config.Config, allocator: std.mem.Allocator) !void {
    // Discards config to mute error as maybe needed later
    _ = config;

    // Initialises the postgres connection pool
    var pool = try pg.Pool.init(allocator, .{ .size = 5, .connect = .{
        .port = 5432,
        .host = "127.0.0.1",
    }, .auth = .{
        .username = "postgres",
        .database = "postgres",
        .password = "mysecretpassword",
        .timeout = 10_000,
    } });
    defer pool.deinit();

    // Initialises the address and attaches listener to it
    const address = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 587);
    var server = address.listen(.{}) catch |err| {
        std.log.err("Error Occurred Starting SMTP Server Listener", .{});
        return err;
    };

    std.log.info("IMAP Server Successfully Started", .{});

    while (true) {
        const conn = try server.accept();
        // spawns that to handle request so that server can handle multiple requests
        _ = try std.Thread.spawn(.{}, imapHandshake, .{ @constCast(&conn), pool, &allocator });
    }
}

fn imapHandshake(connection: std.net.Server.Connection, pool: pg.Pool, allocator: *std.mem.Allocator) !void {
    var writer = connection.stream.writer();
    var reader = connection.stream.reader();
    // IMAP Greeting
    try writer.writeAll("OK IMAP4rev1 Service Ready\r\n");

    // Init User
    var user: ?User.User = null;

    while (true) {

        // Read TCP Line
        const line = try reader.readUntilDelimiterOrEof("\r\n");
        if (line == null) {
            connection.stream.close();
            return;
        }

        // Parse Client Request
        const request_args = try parseCommand(line, allocator);

        // Handle Client Request Based On Command Found
        switch (request_args.command) {
            Command.Login => {

                // Getting Username & Password Out of Request
                const username = request_args.tokens[1];
                const password = request_args.tokens[2];

                // Getting User
                user = try User.findUser(username, pool, allocator);

                // User Not Found
                if (user == null) {
                    try writer.writeAll("NO Authentication failed\r\n");
                    connection.stream.close();
                    return;
                }

                // Creditinals Check
                if (std.meta.eql(user.?.username, username) and std.meta.eql(user.?.password, password)) {
                    try writer.writeAll("OK Authentication successful\r\n");
                } else {
                    try writer.writeAll("NO Authentication failed\r\n");
                }
            },
            Command.Select => {
                // Checks if user is logged in
                if (user == null) {
                    try writer.writeAll("NO LOGIN Required. Authentication required.\r\n");
                    return;
                }

                // Gets select arg
                const select_arg = request_args.tokens[1];

                // Check that select arg equals INBOX if not refuse it
                if (!std.meta.eql(select_arg, "INBOX")) {
                    try writer.writeAll("NO [NONEXISTENT] Mailbox does not exist.");
                    break;
                }

                // Get the Recent Emails From Database
                const emails = try Email.get_recent_emails(user.?.username, pool);

                // Get Email Count for Exists Count
                var x = try pool.exec("SELECT COUNT(*) FROM Emails", .{});
                if (x == null) {
                    x = 0;
                }

                x += 1;

                // Make Inbox name
                const inbox_name = user.?.username ++ "INBOX";
                // Write Response
                try writer.write("OK [UIDVALIDITY {}] UIDs valid.\r\n", .{generateUidValidity(inbox_name)});
                try writer.write("OK [UIDNEXT {}] Predicted next UID.\r\n", .{x.?});
                try writer.write("OK [HIGHESTMODSEQ {}] Highest ModSeq.\r\n", .{getHighestModSeq(inbox_name, allocator)});
                try writer.write("* {} EXISTS\r\n", .{user.?.email_ids.len});
                try writer.write("* {} RECENT\r\n", .{emails.len});
            },
            Command.Fetch => {},
            Command.Store => {},
            Command.Namespace => {
                if (user == null) {
                    try writer.writeAll("NO LOGIN Required. Authentication required.\r\n");
                    return;
                }

                try writer.writeAll("NAMESPACE ((\"INBOX\" \"/\")) NIL NIL\r\n");
            },
            Command.Unknown => {},
        }
    }
}

pub fn parseCommand(input: []const u8, allocator: *std.mem.Allocator) !struct { command: Command, tokens: ?[][]const u8 } {
    var command = Command.Unknown;

    var tokens = std.mem.splitSequence(u8, input, " ");

    if (tokens.peek() == null) return .{ .command = command, .tokens = null };

    command = std.meta.stringToEnum(Command, tokens.next().?) orelse Command.Unknown;

    var arraylist = std.ArrayList([]const u8).init(allocator.*);
    while (tokens.next()) |token| {
        try arraylist.append(token);
    }

    const slice = try arraylist.toOwnedSlice();
    return .{ .command = command, .tokens = slice };
}

fn getHighestModSeq(mailboxName: []const u8, allocator: std.mem.Allocator) !u64 {
    const fileName = buildFileName(mailboxName);

    // Read the highest mod-sequence value from the file
    var highestModSeq: u64 = 0;

    const data = std.fs.cwd().readFileAlloc(allocator, fileName, 2048) catch {
        std.log.err("Failed to read ModSeq file.", .{});

        // Create the file if it doesn't exist
        const file = try fs.cwd().createFile(fileName);
        defer file.close();

        // Write an initial value of 0 to the file
        const initialModSeq: u64 = 0;
        const initialModSeqBytes = std.mem.bytes(&initialModSeq);
        try file.writeAll(initialModSeqBytes);
        return 0;
    };
    defer allocator.free(data);

    highestModSeq = std.mem.readInt(u64, data, std.builtin.Endian.big);
    return highestModSeq;
}

fn buildFileName(mailboxName: []const u8) []const u8 {
    // Makes the mailbox name
    return std.mem.join(u8, &[_][]const u8{ "", mailboxName, ".modseq" });
}

fn generateUidValidity(mailboxName: []const u8) u32 {
    // Get current timestamp
    const currentTime = time.currentTime();

    // Generate a random value
    var randomBytes: [16]u8 = undefined;
    rand.fillRandomBytes(u8, randomBytes[0..]);

    // Adds mailbox name, timestamp, and random value
    const combinedData = std.mem.alloc(u8, mailboxName.len + 8 + 16);
    defer std.mem.free(combinedData);

    const writer = std.mem.Writer.init(combinedData);
    writer.writeAll(mailboxName);
    writer.writeIntLE(u64, currentTime.nanoseconds(), 8);
    writer.writeSlice(randomBytes);

    // Calculate hash of the combined data
    const hash: []const u8 = []const u8{};
    crypto.hash.sha2.Sha256.hash(combinedData, &hash, .{});

    // Convert the first 4 bytes of the hash to a u32 value as UIDVALIDITY
    var uidValidity: u32 = 0;
    for (hash[0..4]) |byte| {
        uidValidity <<= 8;
        uidValidity |= byte;
    }

    return uidValidity;
}
