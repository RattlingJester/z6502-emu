const std = @import("std");
const emu = @import("emu");
const log = std.log.scoped(.wozmon);

const rom = @embedFile("out/wozmon.bin");

const Cpu = emu.CPU(Bus, .{});

const Bus = struct {
    const Self = @This();

    pub const STACK_START = 0xFF; // [0x0100...0x01FF]
    pub const STACK_RESET = 0xFD;
    pub const RESET_VECTOR = 0xFFFC;
    pub const IRQ_VECTOR = 0xFFFE;
    pub const MEM_SIZE = 1024 * 64;

    ram: [MEM_SIZE]u8 = undefined,
    dsp_cr: u8 = 0,

    io: std.Io,
    stdout_buf: [64]u8 = undefined,
    stdout_writer: std.Io.File.Writer,

    next_key: ?u8 = null,

    pub fn init(io: std.Io) Self {
        var self: Self = .{ .io = io, .stdout_writer = undefined };
        self.stdout_writer = std.Io.File.stdout().writerStreaming(io, &self.stdout_buf);
        return self;
    }

    pub fn read(self: *Self, addr: u16) !u8 {
        switch (addr) {
            0xD010 => {
                // If a key is staged, return it and clear the ready status
                if (self.next_key) |char| {
                    self.next_key = null;
                    return char;
                }
                return 0x00;
            },
            0xD011 => {
                // If we have a key waiting, set Bit 7 high for Wozmon
                return if (self.next_key != null) 1 << 7 else 0x00;
            },
            0xD013 => return self.dsp_cr,
            else => return self.ram[addr],
        }
    }

    pub fn write(self: *Self, addr: u16, value: u8) !void {
        switch (addr) {
            0xD013 => self.dsp_cr = value,
            0xD012 => {
                // Print once DSPCR has switched into data-register mode (bit 2 set).
                if ((self.dsp_cr & (1 << 2)) != 0) {
                    // Convert to 7 bit ASCII character
                    const ascii_char = value & 0x7F;

                    self.stdout_writer.interface.writeAll(&.{ascii_char}) catch |err| {
                        log.err("stdout write failed: {}", .{err});
                    };

                    // Add newline after carriage return
                    if (ascii_char == '\r') {
                        try self.stdout_writer.interface.writeAll(&.{'\n'});
                    }

                    try self.stdout_writer.interface.flush();
                }
            },
            else => self.ram[addr] = value,
        }
    }

    pub fn push_keyboard_input(self: *Self, char: u8) void {
        // Convert lowercase to uppercase
        const upper_char = if (char >= 'a' and char <= 'z') char - 32 else char;

        self.next_key = upper_char | 1 << 7;
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var bus = Bus.init(io);
    bus.ram = rom.*;

    var cpu = Cpu.init(&bus);
    cpu.reset();

    var kb_task = io.async(keyboard_listener, .{ io, &bus });
    defer kb_task.cancel(io) catch {};

    const CYCLES = 1000;

    while (true) {
        var cycles_executed: u32 = 0;

        while (cycles_executed < CYCLES) {
            const cycles = cpu.step();
            cycles_executed += cycles;
        }

        // Doing 1ms sleep every 1000 cycles gets us 1Mhz clock (not counting OS overhead)
        try io.sleep(.fromMilliseconds(1), .awake);
    }
}

fn keyboard_listener(io: std.Io, bus: *Bus) !void {
    var read_buf: [64]u8 = undefined;
    var reader = std.Io.File.stdin().readerStreaming(io, &read_buf);
    const stdin = &reader.interface;

    while (true) {
        const char = try stdin.takeByte();

        // In case terminal sends only \n. Maybe not needed?
        const processed: u8 = if (char == '\n') '\r' else char;
        bus.push_keyboard_input(processed);

        // Yielding
        try io.sleep(.fromNanoseconds(0), .awake);
    }
}
