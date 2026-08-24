const std = @import("std");
const emu = @import("emu");
const log = std.log.scoped(.wozmon);

const Bus = struct {
    const Self = @This();

    pub const STACK_START = 0xFF; // [0x0100...0x01FF]
    pub const STACK_RESET = 0xFD;
    pub const RESET_VECTOR = 0xFFFC;
    pub const IRQ_VECTOR = 0xFFFE;
    pub const MEM_SIZE = 1024 * 64;

    ram: [MEM_SIZE]u8 = @embedFile("out/wozmon.bin").*,

    io: std.Io,
    alloc: std.mem.Allocator,

    stdout_buf: [64]u8 = undefined,
    stdout_writer: std.Io.File.Writer,

    keys_queue: std.Deque(u8),
    dsp_cr: u8 = 0,

    pub fn init(io: std.Io, alloc: std.mem.Allocator) !Self {
        var self: Self = .{
            .io = io,
            .alloc = alloc,
            .ram = undefined,
            .stdout_buf = undefined,
            .stdout_writer = undefined,
            .keys_queue = try .initCapacity(alloc, 64),
        };

        self.stdout_writer = std.Io.File.stdout().writerStreaming(io, &self.stdout_buf);

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.keys_queue.deinit(self.alloc);
    }

    pub fn read(self: *Self, addr: u16) !u8 {
        switch (addr) {
            0xD010 => {
                // If a key is staged, return it and clear the ready status
                if (self.keys_queue.popFront()) |char| {
                    return char;
                }
                return 0x00;
            },
            0xD011 => {
                // If we have a key waiting, set Bit 7 high for Wozmon
                return if (self.keys_queue.len > 0) 1 << 7 else 0x00;
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
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var kb_buf: [64]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&kb_buf);
    const alloc = fba.allocator();

    var bus = try Bus.init(io, alloc);
    defer bus.deinit();

    var cpu = emu.CPU(Bus, .{}).init(&bus);
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
        const pr: u8 = if (char == '\n') '\r' else char;

        // Convert lowercase to uppercase
        const upper_char = if (pr >= 'a' and pr <= 'z') pr - 32 else pr;

        try bus.keys_queue.pushBack(bus.alloc, (upper_char | 1 << 7));

        // Yielding
        try io.sleep(.fromNanoseconds(0), .awake);
    }
}
