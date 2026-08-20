const std = @import("std");
const RomBuilder = @import("rombuiler.zig").RomBuilder;
const Opcodes = @import("instructions.zig").Opcodes;

const log = std.log.scoped(.emulator);

const MAX_MEM = 1024 * 64;

const MemoryBus = struct {
    const Self = @This();

    ram: [MAX_MEM]u8 = undefined,

    pub fn read(self: *Self, addr: u16) u8 {
        return self.ram[addr];
    }

    pub fn write(self: *Self, addr: u16, value: u8) void {
        self.ram[addr] = value;
    }
};

pub fn CPU(comptime Bus: type) type {
    return struct {
        const Self = @This();

        PC: u16 = 0xFFFC,

        A: u8 = 0,
        X: u8 = 0,
        Y: u8 = 0,

        SP: u8 = 0xFD,
        status: u8 = 0b00110100,

        bus: *Bus = null,

        pub fn init(bus: *Bus) Self {
            return .{ .bus = bus };
        }

        pub fn reset(self: *Self) void {
            const lo: u16 = self.bus.read(0xFFFC);
            const hi: u16 = self.bus.read(0xFFFD);

            self.PC = (hi << 8) | lo;
            self.A = 0;
            self.X = 0;
            self.Y = 0;

            self.SP = 0xFD;
            self.status = 0b00110100;
        }

        pub fn fetch_zp(self: *Self, addr: u8) u8 {
            self.PC += 1;
            return self.bus.read(addr);
        }

        pub fn fetch_byte(self: *Self, addr: u16) u8 {
            self.PC += 1;
            return self.bus.read(addr);
        }

        pub fn fetch_word(self: *Self, addr: u16) u16 {
            const lo: u16 = self.bus.read(addr);
            const hi: u16 = self.bus.read(addr + 1);

            self.PC += 2;
            return (hi << 8) | lo;
        }

        pub fn read_byte(self: *const Self, addr: u16) u8 {
            return self.bus.read(addr);
        }

        pub fn write_byte(self: *Self, addr: u16, value: u8) void {
            self.bus.write(addr, value);
        }

        pub fn write_word(self: *Self, addr: u16, value: u16) void {
            self.bus.write(addr, @truncate(value & 0xFF));
            self.bus.write(addr + 1, @truncate(value >> 8));
        }

        pub fn update_status(self: *Self) void {
            if (self.A == 0) self.status |= (1 << 1) else self.status &= ~@as(u8, 1 << 1);
            if ((self.A & 0x80) != 0) self.status |= (1 << 7) else self.status &= ~@as(u8, 1 << 7);
        }

        pub fn execute(self: *Self, i: Opcodes) u8 {
            return switch (i) {
                Opcodes.LDA_IM => block: {
                    self.A = self.fetch_byte(self.PC);
                    self.update_status();
                    break :block 2;
                },
                Opcodes.LDA_ZP => block: {
                    const addr = self.fetch_byte(self.PC);
                    self.A = self.read_byte(addr);
                    self.update_status();
                    break :block 3;
                },

                else => {
                    std.log.err("Instruction {} (0x{X}) is not handled", .{ i, i });
                    unreachable;
                },
            };
        }

        pub fn cycle(self: *Self) u8 {
            const instuction = self.fetch_byte(self.PC);

            return self.execute(@enumFromInt(instuction));
        }
    };
}

const rom = blk: {
    var builder = RomBuilder(MAX_MEM){};
    break :blk builder
        .reset_vector(0x8000)
        .org(0x8000)
        .op(Opcodes.LDA_IM).byte(10)
        .op(Opcodes.LDA_ZP).byte(0x42)
        .org(0x42).byte(69)
        .build();
};

pub fn main() void {
    var execute_cycles: i8 = 5;
    var elapsed_cycles: u8 = 0;

    var bus = MemoryBus{ .ram = rom };
    var cpu = CPU(MemoryBus).init(&bus);

    cpu.reset();

    while (execute_cycles > 0) {
        elapsed_cycles = cpu.cycle();
        execute_cycles -= @intCast(elapsed_cycles);
    }

    if (execute_cycles != 0) {
        log.err("Cycle count mismatch! Elapsed: {}, Remaining: {}", .{ elapsed_cycles, execute_cycles });
    }

    log.info("CPU PC register: 0x{X}", .{cpu.PC});
    log.info("CPU A register: {}", .{cpu.A});
    log.info("CPU status register: 0b{b}", .{cpu.status});
}
