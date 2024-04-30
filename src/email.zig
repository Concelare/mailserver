const std = @import("std");
const pg = @import("pg");

pub const Email = struct {
    id: u16,
    messageId: []const u8,
    raw: []const u8,
    replyTo: []const u8,
    recievedFrom: []const u8,
    returnTo: []const u8,
    subject: []const u8,
    to: []const u8,
    from: []const u8,
    mime: []const u8,
    dkimSignature: []const u8,
    spf: []const u8,
    body: []const u8,
    read: bool,
    recent: bool,
    date_created: []const u8,
};

pub fn insert_email(email: Email, pool: pg.Pool) !void {
    const date = std;
    _ = date; // autofix
    _ = try pool.query("INSERT INTO Emails (messageId, \"to\", \"from\", subject, body, replyTo, recievedFrom, returnTo, mime, dkimSignature, spf, read, date_created, recent, raw) values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)", .{ email.id, email.to, email.from, email.subject, email.replyTo, email.recievedFrom, email.returnTo, email.mime, email.dkimSignature, email.spf, email.read, email.date_created, email.recent, email.raw });
}

pub fn get_recent_emails(username: []const u8, pool: pg.Pool) ![]Email {
    var result = try pool.query("SELECT * FROM Emails WHERE recent EQUALS true AND \"to\" EQUALS $1", .{username});
    var emails = [2048]std.ArrayList(Email);
    while (try result.next()) |row| {
        const email = Email{
            .id = row.getCol([]const u8, "id"),
            .raw = row.getCol([]const u8, "raw"),
            .replyTo = row.getCol([]const u8, "replyTo"),
            .recievedFrom = row.getCol([]const u8, "recievedFrom"),
            .returnTo = row.getCol([]const u8, "returnTo"),
            .subject = row.getCol([]const u8, "subject"),
            .to = row.getCol([]const u8, "to"),
            .from = row.getCol([]const u8, "from"),
            .mime = row.getCol([]const u8, "mime"),
            .dkimSignature = row.getCol([]const u8, "dkimSignature"),
            .spf = row.getCol([]const u8, "spf"),
            .body = row.getCol([]const u8, "body"),
            .read = row.getCol(bool, "read"),
            .recent = row.getCol(bool, "recent"),
            .date_created = row.getCol([]const u8, "date_created"),
        };

        emails.append(email);
    }

    return emails.Slice();
}

const HeaderFields = struct {
    replyTo: ?[]const u8,
    received: ?[]const u8,
    returnTo: ?[]const u8,
    subject: ?[]const u8,
    to: ?[]const u8,
    from: ?[]const u8,
    messageId: ?[]const u8,
    mime: ?[]const u8,
    dkimSignature: ?[]const u8,
    spf: ?[]const u8,
};

const Header = struct {
    name: []const u8,
    value: []const u8,
};

pub fn parseEmailHeaders(headers: []const u8) !HeaderFields {
    var iter = std.mem.splitSequence(u8, headers, "\r\n");

    var fields = HeaderFields{
        .replyTo = null,
        .received = null,
        .returnTo = null,
        .subject = null,
        .to = null,
        .from = null,
        .messageId = null,
        .mime = null,
        .dkimSignature = null,
        .spf = null,
    };

    while (iter.next()) |line| {
        const header = parseHeader(line);
        if (std.mem.eql(u8, header.name, "Reply-To")) {
            fields.replyTo = header.value;
        } else if (std.mem.eql(u8, header.name, "Received")) {
            fields.received = header.value;
        } else if (std.mem.eql(u8, header.name, "Return-Path")) {
            fields.returnTo = header.value;
        } else if (std.mem.eql(u8, header.name, "Subject")) {
            fields.subject = header.value;
        } else if (std.mem.eql(u8, header.name, "To")) {
            fields.to = header.value;
        } else if (std.mem.eql(u8, header.name, "From")) {
            fields.from = header.value;
        } else if (std.mem.eql(u8, header.name, "Message-ID")) {
            fields.messageId = header.value;
        } else if (std.mem.eql(u8, header.name, "MIME-Version")) {
            fields.mime = header.value;
        } else if (std.mem.eql(u8, header.name, "DKIM-Signature")) {
            fields.dkimSignature = header.value;
        } else if (std.mem.eql(u8, header.name, "Received-SPF")) {
            fields.spf = header.value;
        }
    }
    return fields;
}

fn parseHeader(line: []const u8) Header {
    const colonIndex: ?usize = std.mem.indexOf(u8, line, ":");
    if (colonIndex == null) {
        return Header{ .name = "", .value = "" };
    }

    const name = line[0..colonIndex.?];
    const valueStart = colonIndex.? + 1;
    const value = line[valueStart..];

    return Header{ .name = name, .value = value };
}
