const std = @import("std");
const emu = @import("emu");

const log = std.log.scoped(.main);

const RomBuilder = emu.RomBuilder;
const Opcodes = emu.Opcode;
const CPU = emu.CPU;

const MAX_MEM = 1024 * 64;

const MemoryBus = struct {
    const Self = @This();

    pub const STACK_START = 0xFD;

    ram: [MAX_MEM]u8 = undefined,

    pub fn read(self: *Self, addr: u16) u8 {
        if (addr < MAX_MEM)
            return self.ram[addr]
        else
            unreachable;
    }

    pub fn write(self: *Self, addr: u16, value: u8) void {
        if (addr < MAX_MEM)
            self.ram[addr] = value
        else
            unreachable;
    }
};

const rom = blk: {
    var builder = RomBuilder(MAX_MEM){};
    break :blk builder
        .reset_vector(0x8000)
        .org(0x8000).op(Opcodes.JSR_ABS).word(0x4000) // JUMP SBR
        .op(Opcodes.LDA_ZP).byte(0x47)
        .org(0x47).byte(0x25)
        .org(0x4000).op(Opcodes.LDA_IM).byte(0x69) // : SBR
        .op(Opcodes.RTS_IMPL) // RTS
        .build();
};

pub fn main() void {
    var execute_cycles: i8 = 17;
    var elapsed_cycles: u8 = 0;

    var bus = MemoryBus{ .ram = rom };
    var cpu = CPU(MemoryBus).init(&bus);

    cpu.reset();

    while (execute_cycles > 0) {
        elapsed_cycles = cpu.tick();
        execute_cycles -= @intCast(elapsed_cycles);
    }

    if (execute_cycles != 0) {
        log.err("Cycle count mismatch! Elapsed: {}, Remaining: {}", .{ elapsed_cycles, execute_cycles });
    }

    cpu.print_state();
}
