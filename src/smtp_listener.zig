// Imports
const Config = @import("config.zig");
const std = @import("std");
const pg = @import("pg");
const net = std.net;
const io = std.io;
const mem = std.mem;

// Set Buffer Size
const BUFFER_SIZE = 4096;

// SMTP Listener, Handles all SMTP Connections
pub fn listener(config: *Config.Config, allocator: std.mem.Allocator) !void {
    _ = config;
    // Sets up Postgres Connection Pool
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

    // Init Address
    const address = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 587);

    // Creates Listener on Address
    var server = address.listen(.{}) catch |err| {
        std.log.err("Error Occurred Starting SMTP Server Listener", .{});
        return err;
    };

    std.log.info("SMTP Server Successfully Started", .{});

    while (true) {
        const conn = try server.accept();
        // Spawns Thread to handle Connection so multiple Requests can be accepted at once
        _ = try std.Thread.spawn(.{}, handleClient, .{ @constCast(&conn), pool, @constCast(&allocator) });
    }
}

fn handleClient(conn: *net.Server.Connection, db: *pg.Pool, allocator: *std.mem.Allocator) !void {
    _ = db;

    // Sets Buffers For Email Data
    var buffer: [0]u8 = undefined;

    // Get Reader & Writer For Stream
    var reader = conn.stream.reader();
    var writer = conn.stream.writer();

    // Send successfully connection message
    _ = try writer.write("220\r\n");

    // Initialise Variables
    var mailFrom: []const u8 = undefined;
    var rcptTo: []const u8 = undefined;
    var emailData: [0]u8 = undefined;

    // Allocate the buffer for the line
    const line = allocator.alloc(u8, 256) catch |err| {
        std.log.err("Failed To Allocator Response Buffer For SMTP Listener Connection", .{});
        return err;
    };

    while (true) {
        // reads new line
        _ = try reader.readAll(line);
        if (line.len == 0) {
            break;
        }

        // Parses command to Command Enum
        const command: Command = parseCommand(line);
        switch (command) {
            // Responds to HEllo Command
            Command.HELO, Command.EHLO => try writer.writeAll("250 Hello\r\n"),
            // Starts Recieve MAIL
            Command.MAIL => {
                mailFrom = extractArgument(line);
                _ = try writer.write("250 OK\r\n");
            },
            // Recipient of the email
            Command.RCPT => {
                rcptTo = extractArgument(line);
                _ = try writer.write("250 OK\r\n");
            },
            // The Email Data Recieved
            Command.DATA => {
                _ = try writer.writeAll("354 Start mail input; end with <CRLF>.CRLF>\r\n");

                // Read email data
                while (true) {
                    const bytesRead = try reader.read(buffer[0..]);
                    if (bytesRead == 0) {
                        break;
                    }
                    emailData = emailData ++ buffer;

                    // Check for end of email data (".CRLF")
                    if (emailData.len >= 3 and
                        emailData[emailData.len - 3] == '.' and
                        emailData[emailData.len - 2] == '\r' and
                        emailData[emailData.len - 1] == '\n')
                    {
                        break;
                    }
                }

                _ = try writer.write("250 OK\r\n");
            },
            // Closes Connection
            Command.QUIT => {
                _ = try writer.write("221 Bye\r\n");
                conn.stream.close();
                break;
            },
            // Handles unknown commands
            else => _ = try writer.write("500 Syntax error, command unrecognized\r\n"),
        }
    }

    // Now Parses email to format
    const email = try parseEmail(&emailData, allocator);
    _ = email; // discard to stop error
    // Need to add email saving to postgres
}

// Command Enum
const Command = enum {
    HELO,
    EHLO,
    MAIL,
    RCPT,
    DATA,
    QUIT,
    UNKNOWN,
};

// Parses request into Command
fn parseCommand(line: []const u8) Command {
    // Splits request by whitespace
    var command_iter = std.mem.splitSequence(u8, line, " ");
    // Parses command from string to enum or if not found returns UNKNOWN command enum
    const parsed = std.meta.stringToEnum(Command, command_iter.first()) orelse Command.UNKNOWN;
    return parsed;
}

// Extracts Argument from requests
fn extractArgument(line: []const u8) []const u8 {
    // Splits request by whitespace
    var parts = std.mem.splitSequence(u8, line, " ");
    if (parts.buffer.len >= 2) {
        // Skip first item
        parts.index = 0;
        return parts.next().?;
    } else {
        return undefined;
    }
}

const Email = struct {
    headers: []const u8,
    body: []const u8,
    attachments: []Attachment,
};

const Attachment = struct {
    filename: []const u8,
    content: []const u8,
};

// Parses email into struct
fn parseEmail(rawEmail: []const u8, allocator: *std.mem.Allocator) !Email {
    var email = Email{
        .headers = undefined,
        .body = undefined,
        .attachments = undefined,
    };

    // Find the index of the first occurrence of "\r\n\r\n" indicating the end of headers
    const doubleCRLF = "\r\n\r\n";
    const headersEndIndex = mem.indexOf(u8, rawEmail, doubleCRLF);
    if (headersEndIndex == null) {
        return email;
    }

    // Extract headers and body
    email.headers = rawEmail[0..headersEndIndex.?];
    email.body = rawEmail[headersEndIndex.? + doubleCRLF.len ..];

    // Find and extract attachments
    const boundary = getBoundary(email.headers);
    if (boundary != null) {
        email.attachments = try extractAttachments(email.body, boundary.?, allocator);
    }

    return email;
}

// Gets boundary of MIME Attachments
fn getBoundary(headers: []const u8) ?[]const u8 {
    const boundaryPrefix = "boundary=";
    const boundaryIndex = mem.indexOf(u8, headers, boundaryPrefix);
    if (boundaryIndex == null) {
        return null;
    }

    const boundaryStart = boundaryIndex.? + boundaryPrefix.len;
    const boundaryEnd = mem.indexOf(u8, headers[boundaryStart..], "\r\n");
    if (boundaryEnd == null) {
        return null;
    }

    return headers[boundaryStart .. boundaryStart + boundaryEnd.?];
}

// Extracts the attachments from the email
fn extractAttachments(body: []const u8, boundary: []const u8, allocator: *std.mem.Allocator) ![]Attachment {
    var attachments: []Attachment = undefined;
    var capacity: usize = 0;
    var length: usize = 0;

    // Split the body into parts using the boundary
    var parts = std.mem.split(u8, body, boundary);

    while (parts.next()) |part| {

        // Skip empty parts
        if (part.len == 0) continue;

        var attachment = Attachment{
            .filename = undefined,
            .content = undefined,
        };

        // Find Content-Disposition header to get attachment filename
        const contentDisposition = try findHeader(part, "Content-Disposition", allocator);
        if (contentDisposition != null) {
            const filenameStart = std.mem.indexOf(u8, contentDisposition.?, "filename=");
            if (filenameStart != null) {
                const filenameEnd = std.mem.indexOf(u8, part[filenameStart.?..], "\r\n");
                if (filenameEnd != null) {
                    attachment.filename = validateFilename(part[filenameStart.? + "filename=".len .. filenameEnd.?]);
                }
            }
        }

        // Skip headers and empty lines to get attachment content
        const contentStart = skipHeaders(part);
        attachment.content = try decodeContent(part[contentStart..], allocator);

        try increaseCapacity(allocator, &attachments, &capacity, &length);
        attachments[length] = attachment;
        length += 1;
    }

    return attachments;
}

// Increases Capacity of array
fn increaseCapacity(allocator: *std.mem.Allocator, attachments: *[]Attachment, capacity: *usize, length: *usize) !void {
    const newCapacity = capacity.* + 1;
    const newAttachments = try allocator.alloc(Attachment, newCapacity);
    // Copy existing attachments to the new slice
    if (length.* != 0) {
        _ = @memcpy(newAttachments, attachments.*);
    }
    attachments.* = newAttachments;
    capacity.* = newCapacity;
}

// Finds Header in email
fn findHeader(part: []const u8, headerName: []const u8, allocator: *mem.Allocator) !?[]const u8 {
    const header = try std.fmt.allocPrint(allocator.*, "\r\n {any}: ", .{headerName});
    const headerIndex = std.mem.indexOf(u8, part, header);
    if (headerIndex != null) {
        const valueStart = headerIndex.? + header.len;

        const valueEnd = std.mem.indexOf(u8, part[valueStart..], "\r\n");

        if (valueEnd != null) {
            return part[valueStart..valueEnd.?];
        }
    }
    return null;
}

// Gets the position to skip the headers
fn skipHeaders(part: []const u8) usize {
    // Find the index of the first occurrence of "\r\n\r\n" indicating the end of headers
    const doubleCRLF = "\r\n\r\n";
    const headersEndIndex = mem.indexOf(u8, part, doubleCRLF);
    if (headersEndIndex != null) {
        // Return the index after the headers
        return headersEndIndex.? + doubleCRLF.len;
    }
    // If no headers found, return 0
    return 0;
}

// Added to allow the validating of file names later on
fn validateFilename(filename: []const u8) []const u8 {
    return filename;
}

// MIME Encoding types
const encoding_types = enum { base64, quotedprintable };

// Decodes Attachments
fn decodeContent(content: []const u8, allocator: *mem.Allocator) ![]const u8 {
    // Find Content-Transfer-Encoding header to determine the encoding
    const contentTransferEncoding = try findHeader(content, "Content-Transfer-Encoding", allocator);
    if (contentTransferEncoding != null) {
        // Decode content based on the specified encoding
        const content_encoding = std.meta.stringToEnum(encoding_types, contentTransferEncoding.?);
        switch (content_encoding.?) {
            encoding_types.base64 => return decodeBase64(content),
            encoding_types.quotedprintable => return decodeQuotedPrintable(content),
        }
    }
    // If no encoding specified, return content as is
    return content;
}

// Decodes Base64 Attachments
fn decodeBase64(content: []const u8) []const u8 {
    // TODO: Implement base64 decoding logic
    return content;
}

// Decodes QuotedPrintable Attachments
fn decodeQuotedPrintable(content: []const u8) []const u8 {
    // TODO: Implement quoted-printable decoding logic
    return content;
}
