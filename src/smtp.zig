// Zig Imports
const std = @import("std");
const dns = @import("dns.zig");
const tls = @import("tls.zig");
const Config = @import("config.zig");

// Sends A Message In plain trext
pub fn send_message(allocator: std.mem.Allocator, recipient: []u8, sender: []u8, message: []u8) !void {

    // Splits up the recipient to get the domain
    var splititer = std.mem.splitSequence(u8, recipient, "@");

    splititer.index = 1;
    const item: []const u8 = splititer.next().?;
    // gets MX record from dns
    const record = dns.get_mx_record(allocator, item) catch |err| {
        std.log.err("Failed to Get DNS Record Sending Message To \"{any}\" From \"{any}\"", .{ recipient, sender });
        return err;
    };

    // Connects to the SMTP Server
    const connection = std.net.tcpConnectToHost(allocator, record.address, 25) catch |err| {
        std.log.err("Failed To Open TCP Connection To {any}", record.address);
        return err;
    };

    // Allocate a 256 buffer for responses
    var currentResponse = allocator.alloc(u8, 256) catch |err| {
        std.log.err("Failed To Allocator Response Buffer For TCP Connection with {any}", .{record.address});
        return err;
    };

    // Send Email
    connection.writeAll("HELO") catch |err| {
        std.log.err("Error Occurred Writing TCP Connection with {any}", .{record.address});
        connection.close();
        return err;
    };

    connection.readAll(&currentResponse) catch |err| {
        std.log.err("Error Occurred Reading TCP Connection with {any}", .{record.address});
        connection.close();
        return err;
    };

    if (currentResponse != 250) {
        std.log.err("Incorrect Response Connection Terminated With {any}\nMessage: {any}", .{ record.address, currentResponse });
        connection.close();
        return;
    }

    connection.writeAll("MAIL FROM: " + sender) catch |err| {
        std.log.err("Error Occurred Writing TCP Connection with {any}", .{record.address});
        connection.close();
        return err;
    };

    connection.readAll(&currentResponse) catch |err| {
        std.log.err("Error Occurred Reading TCP Connection with {any}", .{record.address});
        connection.close();
        return err;
    };

    if (currentResponse != 250) {
        std.log.err("Incorrect Response Connection Terminated With {any}\nMessage: {any}", .{ record.address, currentResponse });
        connection.close();
        return;
    }

    connection.writeAll("RCP TO: " + recipient) catch |err| {
        std.log.err("Error Occurred Writing TCP Connection with {any}", .{record.address});
        connection.close();
        return err;
    };

    connection.readAll(&currentResponse) catch |err| {
        std.log.err("Error Occurred Reading TCP Connection with {any}", .{record.address});
        connection.close();
        return err;
    };

    if (currentResponse != 250) {
        std.log.err("Incorrect Response Connection Terminated With {any}\nMessage: {any}", .{ record.address, currentResponse });
        connection.close();
        return;
    }

    connection.writeAll("DATA") catch |err| {
        std.log.err("Error Occurred Writing TCP Connection with {any}", .{record.address});
        connection.close();
        return err;
    };

    connection.readAll(&currentResponse) catch |err| {
        std.log.err("Error Occurred Reading TCP Connection with {any}", .{record.address});
        connection.close();
        return err;
    };

    if (currentResponse != 354) {
        std.log.err("Incorrect Response Connection Terminated With {any}\nMessage: {any}", .{ record.address, currentResponse });
        connection.close();
        return;
    }

    connection.writeAll(message) catch |err| {
        std.log.err("Error Occurred Writing TCP Connection with {any}", .{record.address});
        connection.close();
        return err;
    };

    connection.writeAll("QUIT") catch |err| {
        std.log.err("Error Occurred Writing TCP Connection with {any}", .{record.address});
        connection.close();
        return err;
    };

    connection.readAll(&currentResponse) catch |err| {
        std.log.err("Error Occurred Reading TCP Connection with {any}", .{record.address});
        connection.close();
        return err;
    };

    if (currentResponse != 221) {
        std.log.err("Incorrect Response Connection Terminated With {any}\nMessage: {any}", .{ record.address, currentResponse });
        connection.close();
        return;
    }

    connection.close();
}

// Sends Message Using TLS
pub fn send_message_tls(allocator: std.mem.Allocator, recipient: []u8, sender: []u8, message: []u8) !void {
    // Splits recipent to get domain
    var splititer = std.mem.splitSequence(u8, recipient, "@");

    // Skip first one
    splititer.index = 1;
    const item: []const u8 = splititer.next().?;
    // Gets MX Record From DNS
    const record = dns.get_mx_record(allocator, item) catch |err| {
        std.log.err("Failed to Get DNS Record Sending Message To \"{any}\" From \"{any}\"", .{ recipient, sender });
        return err;
    };

    // Loads the Config
    const config = Config.Config.init(allocator) catch |err| {
        std.log.err("Failed to Load Config, Sending Mail To {any}", .{recipient});
        return err;
    };

    // Initialises the tls_stream variable cos of different tls methods
    var tls_stream: ?tls.TlsStream = null;
    // Starts TLS Stream by either tls or starttls
    if (config.encryption == Config.Encryption.tls) {
        const connection = std.net.tcpConnectToHost(allocator, record.address, 465) catch |err| {
            std.log.err("Failed To Open TCP Connection To {any}", record.address);
            return err;
        };

        tls_stream = tls.TlsStream.to_tls(allocator, connection, config) catch |err| {
            std.log.err("Error Occurred Initialising TLS Connection with {any}", .{record.address});
            return err;
        };
    }

    if (config.encryption == Config.Encryption.start_tls) {
        const connection = std.net.tcpConnectToHost(allocator, record.address, 587) catch |err| {
            std.log.err("Failed To Open TCP Connection To {any}", record.address);
            return err;
        };

        tls_stream = tls.TlsStream.start_tls(allocator, connection, config) catch |err| {
            std.log.err("Error Occurred Initialising TLS Connection with {any}", .{record.address});
            return err;
        };
    }

    if (tls_stream == null) {
        std.log.err("Error Occurred Initialising TLS Connection with {any}", .{record.address});
        return;
    }

    // Allocates response buffer
    var currentResponse = allocator.alloc(u8, 256) catch |err| {
        std.log.err("Failed To Allocator Response Buffer For TCP Connection with {any}", .{record.address});
        return err;
    };

    tls_stream.?.writeAll("MAIL FROM:" + sender) catch |err| {
        std.log.err("Error Occurred: Writing Connection With {any}", .{record.address});
        return err;
    };

    tls_stream.?.readAll(&currentResponse) catch |err| {
        std.log.err("Error Occurred: Reading Data From Connection with {any}", .{record.address});
        return err;
    };

    if (currentResponse != 250) {
        std.log.err("Incorrect Response Connection Terminated With {any}\nMessage: {any}", .{ record.address, currentResponse });
        tls_stream.?.stream.close();
        return;
    }

    tls_stream.?.writeAll("RCP TO: " + recipient) catch |err| {
        std.log.err("Error Occurred Writing TCP Connection with {any}", .{record.address});
        tls_stream.?.stream.close();
        return err;
    };

    tls_stream.?.readAll(&currentResponse) catch |err| {
        std.log.err("Error Occurred Reading TCP Connection with {any}", .{record.address});
        tls_stream.?.stream.close();
        return err;
    };

    if (currentResponse != 250) {
        std.log.err("Incorrect Response Connection Terminated With {any}\nMessage: {any}", .{ record.address, currentResponse });
        tls_stream.?.stream.close();
        return;
    }

    tls_stream.?.writeAll("DATA") catch |err| {
        std.log.err("Error Occurred Writing TCP Connection with {any}", .{record.address});
        tls_stream.?.stream.close();
        return err;
    };

    tls_stream.?.readAll(&currentResponse) catch |err| {
        std.log.err("Error Occurred Reading TCP Connection with {any}", .{record.address});
        tls_stream.?.stream.close();
        return err;
    };

    if (currentResponse != 354) {
        std.log.err("Incorrect Response Connection Terminated With {any}\nMessage: {any}", .{ record.address, currentResponse });
        tls_stream.?.stream.close();
        return;
    }

    tls_stream.?.writeAll(message) catch |err| {
        std.log.err("Error Occurred Writing TCP Connection with {any}", .{record.address});
        tls_stream.?.stream.close();
        return err;
    };

    tls_stream.?.writeAll("QUIT") catch |err| {
        std.log.err("Error Occurred Writing TCP Connection with {any}", .{record.address});
        tls_stream.?.stream.close();
        return err;
    };

    tls_stream.?.readAll(&currentResponse) catch |err| {
        std.log.err("Error Occurred Reading TCP Connection with {any}", .{record.address});
        tls_stream.?.stream.close();
        return err;
    };

    if (currentResponse != 221) {
        std.log.err("Incorrect Response Connection Terminated With {any}\nMessage: {any}", .{ record.address, currentResponse });
        tls_stream.?.stream.close();
        return;
    }
}
