const std = @import("std");
const emu = @import("emu");
const log = std.log.scoped(.main);

const MemoryBus = struct {
    const Self = @This();

    pub const STACK_START = 0xFF; // [0x0100...0x01FF]
    pub const SP_RESET = 0xFD;
    pub const RESET_VECTOR_ADDR = 0xFFFC;
    pub const IRQ_VECTOR = 0xFFFE;
    pub const MEM_SIZE = 1024 * 64;

    ram: [MEM_SIZE]u8 = undefined,

    pub fn read(self: *Self, addr: u16) !u8 {
        return self.ram[addr];
    }

    pub fn write(self: *Self, addr: u16, value: u8) !void {
        self.ram[addr] = value;
    }
};

const rom = blk: {
    var builder = emu.RomBuilder(MemoryBus){};
    break :blk builder
        .reset_vector(0x8000)
        .irq_vector(0x2000)
        .org(0x8000).op(.JSR_ABS).word(0x4000) // JUMP SBR
        .op(.LDA_ZP).byte(0x47)
        .org(0x47).byte(0x25)
        .org(0x4000).op(.LDA_IM).byte(0x69) // : SBR
        .op(.RTS_IMPL) // RTS
        .org(0x2000).op(.NOP_IMPL)
        .build();
};

pub fn main() void {
    var exec_instr: u8 = 6;
    var elapsed_cycles: u16 = 0;

    var bus = MemoryBus{ .ram = rom };
    var cpu = emu.CPU(MemoryBus, .{}).init(&bus);

    cpu.reset();

    while (exec_instr > 0) {
        elapsed_cycles += cpu.step();
        exec_instr -= 1;
    }

    log.info("Took {} cycles to execute", .{elapsed_cycles});

    cpu.print_state();
    cpu.print_stack();
}
