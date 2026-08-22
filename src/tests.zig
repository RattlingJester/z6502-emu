const std = @import("std");
const testing = std.testing;

const emu = @import("root.zig");

const TestBus = struct {
    const Self = @This();

    pub const STACK_START = 0xFF;
    pub const RESET_VECTOR = 0xFFFC;
    pub const IRQ_VECTOR = 0xFFFE;
    pub const MEM_SIZE = 1024 * 64;

    ram: [MEM_SIZE]u8 = [_]u8{0} ** MEM_SIZE,

    pub fn read(self: *Self, addr: u16) u8 {
        return self.ram[addr];
    }
    pub fn write(self: *Self, addr: u16, value: u8) void {
        self.ram[addr] = value;
    }
};

const CPU = emu.CPU(TestBus);

fn setup(program: []const u8) struct { bus: TestBus, cpu: CPU } {
    var bus = TestBus{};
    bus.ram[0xFFFC] = 0x00;
    bus.ram[0xFFFD] = 0x80; // reset vector -> 0x8000
    @memcpy(bus.ram[0x8000..][0..program.len], program);
    return .{ .bus = bus, .cpu = undefined };
}

fn run(bus: *TestBus, program: []const u8) CPU {
    bus.ram[0xFFFC] = 0x00;
    bus.ram[0xFFFD] = 0x80;
    @memcpy(bus.ram[0x8000..][0..program.len], program);
    var cpu = CPU.init(bus);
    cpu.reset();
    return cpu;
}

test "ADC_IM: basic add, no carry/overflow" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x69, 0x10 }); // ADC #$10
    cpu.A = 0x05;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 0x15), cpu.A);
    try testing.expectEqual(@as(u8, 2), cycles);
    try testing.expectEqual(@as(u1, 0), cpu.get_flag(.CARRY));
    try testing.expectEqual(@as(u1, 0), cpu.get_flag(.ZERO));
    try testing.expectEqual(@as(u1, 0), cpu.get_flag(.NEGATIVE));
}

test "ADC_IM: sets carry on unsigned overflow" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x69, 0x01 });
    cpu.A = 0xFF;
    _ = cpu.step();
    try testing.expectEqual(@as(u8, 0x00), cpu.A);
    try testing.expectEqual(@as(u1, 1), cpu.get_flag(.CARRY));
    try testing.expectEqual(@as(u1, 1), cpu.get_flag(.ZERO));
}

test "ADC_IM: sets overflow on signed overflow (127 + 1)" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x69, 0x01 });
    cpu.A = 0x7F; // +127
    _ = cpu.step();
    try testing.expectEqual(@as(u8, 0x80), cpu.A); // -128 signed
    try testing.expectEqual(@as(u1, 1), cpu.get_flag(.OVERFLOW));
    try testing.expectEqual(@as(u1, 1), cpu.get_flag(.NEGATIVE));
}

test "ADC_IM: incoming carry is added" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x69, 0x01 });
    cpu.A = 0x00;
    cpu.set_flag(.CARRY, true);
    _ = cpu.step();
    try testing.expectEqual(@as(u8, 0x02), cpu.A);
}

test "ADC_ZP" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x65, 0x10 }); // ADC $10
    bus.ram[0x10] = 0x22;
    cpu.A = 0x01;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 0x23), cpu.A);
    try testing.expectEqual(@as(u8, 3), cycles);
}

test "ADC_ZP_X" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x75, 0x10 }); // ADC $10,X
    cpu.X = 0x05;
    bus.ram[0x15] = 0x22;
    cpu.A = 0x01;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 0x23), cpu.A);
    try testing.expectEqual(@as(u8, 4), cycles);
}

test "ADC_ZP_X wraps within zero page" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x75, 0xFF }); // ADC $FF,X
    cpu.X = 0x02;
    bus.ram[0x01] = 0x22; // 0xFF + 0x02 wraps to 0x01, not 0x101
    cpu.A = 0x01;
    _ = cpu.step();
    try testing.expectEqual(@as(u8, 0x23), cpu.A);
}

test "ADC_ABS" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x6D, 0x00, 0x20 }); // ADC $2000
    bus.ram[0x2000] = 0x22;
    cpu.A = 0x01;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 0x23), cpu.A);
    try testing.expectEqual(@as(u8, 4), cycles);
}

test "ADC_ABS_X no page cross" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x7D, 0x00, 0x20 }); // ADC $2000,X
    cpu.X = 0x05;
    bus.ram[0x2005] = 0x22;
    cpu.A = 0x01;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 0x23), cpu.A);
    try testing.expectEqual(@as(u8, 4), cycles);
}

test "ADC_ABS_X page cross costs extra cycle" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x7D, 0xFF, 0x20 }); // ADC $20FF,X
    cpu.X = 0x01; // 0x20FF + 1 = 0x2100, page crossed
    bus.ram[0x2100] = 0x22;
    cpu.A = 0x01;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 0x23), cpu.A);
    try testing.expectEqual(@as(u8, 5), cycles);
}

test "ADC_ABS_Y page cross costs extra cycle" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x79, 0xFF, 0x20 }); // ADC $20FF,Y
    cpu.Y = 0x01;
    bus.ram[0x2100] = 0x22;
    cpu.A = 0x01;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 5), cycles);
}

test "ADC_IND_X" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x61, 0x10 }); // ADC ($10,X)
    cpu.X = 0x04;
    bus.ram[0x14] = 0x00; // pointer low
    bus.ram[0x15] = 0x30; // pointer high -> target 0x3000
    bus.ram[0x3000] = 0x22;
    cpu.A = 0x01;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 0x23), cpu.A);
    try testing.expectEqual(@as(u8, 6), cycles);
}

test "ADC_IND_Y" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x71, 0x10 }); // ADC ($10),Y
    bus.ram[0x10] = 0x00;
    bus.ram[0x11] = 0x30; // base -> 0x3000
    cpu.Y = 0x05;
    bus.ram[0x3005] = 0x22;
    cpu.A = 0x01;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 0x23), cpu.A);
    try testing.expectEqual(@as(u8, 5), cycles);
}

test "ADC_IND_Y page cross" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x71, 0x10 });
    bus.ram[0x10] = 0xFF;
    bus.ram[0x11] = 0x30; // base -> 0x30FF
    cpu.Y = 0x01; // -> 0x3100, page crossed
    bus.ram[0x3100] = 0x22;
    cpu.A = 0x01;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 6), cycles);
}

test "AND_IM" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x29, 0x0F });
    cpu.A = 0xFF;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 0x0F), cpu.A);
    try testing.expectEqual(@as(u8, 2), cycles);
}

test "AND_IM sets zero flag" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x29, 0x00 });
    cpu.A = 0xFF;
    _ = cpu.step();
    try testing.expectEqual(@as(u8, 0x00), cpu.A);
    try testing.expectEqual(@as(u1, 1), cpu.get_flag(.ZERO));
}

test "AND_IM sets negative flag" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x29, 0x80 });
    cpu.A = 0xFF;
    _ = cpu.step();
    try testing.expectEqual(@as(u1, 1), cpu.get_flag(.NEGATIVE));
}

test "AND_ZP" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x25, 0x10 });
    bus.ram[0x10] = 0x0F;
    cpu.A = 0xFF;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 0x0F), cpu.A);
    try testing.expectEqual(@as(u8, 3), cycles);
}

test "AND_ZP_X" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x35, 0x10 });
    cpu.X = 0x02;
    bus.ram[0x12] = 0x0F;
    cpu.A = 0xFF;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 0x0F), cpu.A);
    try testing.expectEqual(@as(u8, 4), cycles);
}

test "AND_ABS" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x2D, 0x00, 0x20 });
    bus.ram[0x2000] = 0x0F;
    cpu.A = 0xFF;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 0x0F), cpu.A);
    try testing.expectEqual(@as(u8, 4), cycles);
}

test "AND_ABS_X page cross" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x3D, 0xFF, 0x20 });
    cpu.X = 0x01;
    bus.ram[0x2100] = 0x0F;
    cpu.A = 0xFF;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 5), cycles);
}

test "AND_ABS_Y page cross" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x39, 0xFF, 0x20 });
    cpu.Y = 0x01;
    bus.ram[0x2100] = 0x0F;
    cpu.A = 0xFF;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 5), cycles);
}

test "AND_IND_X" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x21, 0x10 });
    cpu.X = 0x04;
    bus.ram[0x14] = 0x00;
    bus.ram[0x15] = 0x30;
    bus.ram[0x3000] = 0x0F;
    cpu.A = 0xFF;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 0x0F), cpu.A);
    try testing.expectEqual(@as(u8, 6), cycles);
}

test "AND_IND_Y" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x31, 0x10 });
    bus.ram[0x10] = 0x00;
    bus.ram[0x11] = 0x30;
    cpu.Y = 0x05;
    bus.ram[0x3005] = 0x0F;
    cpu.A = 0xFF;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 0x0F), cpu.A);
    try testing.expectEqual(@as(u8, 5), cycles);
}

test "ASL_ACC shifts left, sets carry from old bit 7" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{0x0A});
    cpu.A = 0b1000_0001;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 0b0000_0010), cpu.A);
    try testing.expectEqual(@as(u1, 1), cpu.get_flag(.CARRY));
    try testing.expectEqual(@as(u8, 2), cycles);
}

test "ASL_ZP" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x06, 0x10 });
    bus.ram[0x10] = 0b0100_0001;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 0b1000_0010), bus.ram[0x10]);
    try testing.expectEqual(@as(u1, 0), cpu.get_flag(.CARRY));
    try testing.expectEqual(@as(u1, 1), cpu.get_flag(.NEGATIVE));
    try testing.expectEqual(@as(u8, 5), cycles);
}

test "ASL_ZP_X" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x16, 0x10 });
    cpu.X = 0x02;
    bus.ram[0x12] = 0x01;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 0x02), bus.ram[0x12]);
    try testing.expectEqual(@as(u8, 6), cycles);
}

test "ASL_ABS" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x0E, 0x00, 0x20 });
    bus.ram[0x2000] = 0x01;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 0x02), bus.ram[0x2000]);
    try testing.expectEqual(@as(u8, 6), cycles);
}

test "ASL_ABS_X" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x1E, 0x00, 0x20 });
    cpu.X = 0x05;
    bus.ram[0x2005] = 0x01;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 0x02), bus.ram[0x2005]);
    try testing.expectEqual(@as(u8, 7), cycles);
}

test "ASL sets zero flag" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{0x0A});
    cpu.A = 0x00;
    _ = cpu.step();
    try testing.expectEqual(@as(u1, 1), cpu.get_flag(.ZERO));
}

test "BCC_REL not taken" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x90, 0x10 }); // BCC +16
    cpu.set_flag(.CARRY, true); // carry set -> branch not taken
    const cycles = cpu.step();
    try testing.expectEqual(@as(u16, 0x8002), cpu.PC);
    try testing.expectEqual(@as(u8, 2), cycles);
}

test "BCC_REL taken, no page cross" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x90, 0x10 }); // BCC +16 from 0x8002 -> 0x8012
    cpu.set_flag(.CARRY, false);
    const cycles = cpu.step();
    try testing.expectEqual(@as(u16, 0x8012), cpu.PC);
    try testing.expectEqual(@as(u8, 3), cycles);
}

test "BCC_REL taken, page cross" {
    var bus = TestBus{};
    bus.ram[0xFFFC] = 0xF0;
    bus.ram[0xFFFD] = 0x80; // PC starts at 0x80F0
    bus.ram[0x80F0] = 0x90;
    bus.ram[0x80F1] = 0x20; // BCC +32 -> 0x8112, crosses page
    var cpu = CPU.init(&bus);
    cpu.reset();
    cpu.set_flag(.CARRY, false);
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 4), cycles);
}

test "BCS_REL taken when carry set" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xB0, 0x05 });
    cpu.set_flag(.CARRY, true);
    _ = cpu.step();
    try testing.expectEqual(@as(u16, 0x8007), cpu.PC);
}

test "BEQ_REL taken when zero set" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xF0, 0x05 });
    cpu.set_flag(.ZERO, true);
    _ = cpu.step();
    try testing.expectEqual(@as(u16, 0x8007), cpu.PC);
}

test "BNE_REL taken when zero clear" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xD0, 0x05 });
    cpu.set_flag(.ZERO, false);
    _ = cpu.step();
    try testing.expectEqual(@as(u16, 0x8007), cpu.PC);
}

test "BNE_REL can branch backward" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xD0, 0xFE }); // BNE -2 (infinite loop back to self)
    cpu.set_flag(.ZERO, false);
    _ = cpu.step();
    try testing.expectEqual(@as(u16, 0x8000), cpu.PC);
}

test "BMI_REL taken when negative set" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x30, 0x05 });
    cpu.set_flag(.NEGATIVE, true);
    _ = cpu.step();
    try testing.expectEqual(@as(u16, 0x8007), cpu.PC);
}

test "BPL_REL taken when negative clear" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x10, 0x05 });
    cpu.set_flag(.NEGATIVE, false);
    _ = cpu.step();
    try testing.expectEqual(@as(u16, 0x8007), cpu.PC);
}

test "BVC_REL taken when overflow clear" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x50, 0x05 });
    cpu.set_flag(.OVERFLOW, false);
    _ = cpu.step();
    try testing.expectEqual(@as(u16, 0x8007), cpu.PC);
}

test "BVS_REL taken when overflow set" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x70, 0x05 });
    cpu.set_flag(.OVERFLOW, true);
    _ = cpu.step();
    try testing.expectEqual(@as(u16, 0x8007), cpu.PC);
}

test "CLC_IMPL clears carry" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{0x18});
    cpu.set_flag(.CARRY, true);
    const cycles = cpu.step();
    try testing.expectEqual(@as(u1, 0), cpu.get_flag(.CARRY));
    try testing.expectEqual(@as(u8, 2), cycles);
}

test "CLD_IMPL clears decimal" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{0xD8});
    cpu.set_flag(.DECIMAL, true);
    _ = cpu.step();
    try testing.expectEqual(@as(u1, 0), cpu.get_flag(.DECIMAL));
}

test "CLI_IMPL clears interrupt disable" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{0x58});
    cpu.set_flag(.INTERRUPT_DISABLE, true);
    _ = cpu.step();
    try testing.expectEqual(@as(u1, 0), cpu.get_flag(.INTERRUPT_DISABLE));
}

test "CLV_IMPL clears overflow" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{0xB8});
    cpu.set_flag(.OVERFLOW, true);
    _ = cpu.step();
    try testing.expectEqual(@as(u1, 0), cpu.get_flag(.OVERFLOW));
}

test "CMP_IM equal sets zero and carry" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xC9, 0x10 });
    cpu.A = 0x10;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u1, 1), cpu.get_flag(.ZERO));
    try testing.expectEqual(@as(u1, 1), cpu.get_flag(.CARRY));
    try testing.expectEqual(@as(u8, 2), cycles);
}

test "CMP_IM A greater sets carry, clears zero" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xC9, 0x05 });
    cpu.A = 0x10;
    _ = cpu.step();
    try testing.expectEqual(@as(u1, 1), cpu.get_flag(.CARRY));
    try testing.expectEqual(@as(u1, 0), cpu.get_flag(.ZERO));
}

test "CMP_IM A less clears carry" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xC9, 0x20 });
    cpu.A = 0x10;
    _ = cpu.step();
    try testing.expectEqual(@as(u1, 0), cpu.get_flag(.CARRY));
}

test "CMP_ZP" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xC5, 0x10 });
    bus.ram[0x10] = 0x05;
    cpu.A = 0x05;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u1, 1), cpu.get_flag(.ZERO));
    try testing.expectEqual(@as(u8, 3), cycles);
}

test "CMP_ZP_X" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xD5, 0x10 });
    cpu.X = 0x02;
    bus.ram[0x12] = 0x05;
    cpu.A = 0x05;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 4), cycles);
}

test "CMP_ABS" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xCD, 0x00, 0x20 });
    bus.ram[0x2000] = 0x05;
    cpu.A = 0x05;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 4), cycles);
}

test "CMP_IND_X" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xC1, 0x10 });
    cpu.X = 0x04;
    bus.ram[0x14] = 0x00;
    bus.ram[0x15] = 0x30;
    bus.ram[0x3000] = 0x05;
    cpu.A = 0x05;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 6), cycles);
}

test "CPX_IM" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xE0, 0x05 });
    cpu.X = 0x05;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u1, 1), cpu.get_flag(.ZERO));
    try testing.expectEqual(@as(u8, 2), cycles);
}

test "CPX_ZP" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xE4, 0x10 });
    bus.ram[0x10] = 0x05;
    cpu.X = 0x05;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 3), cycles);
}

test "CPX_ABS" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xEC, 0x00, 0x20 });
    bus.ram[0x2000] = 0x05;
    cpu.X = 0x05;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 4), cycles);
}

test "CPY_IM" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xC0, 0x05 });
    cpu.Y = 0x05;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u1, 1), cpu.get_flag(.ZERO));
    try testing.expectEqual(@as(u8, 2), cycles);
}

test "CPY_ZP" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xC4, 0x10 });
    bus.ram[0x10] = 0x05;
    cpu.Y = 0x05;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 3), cycles);
}

test "CPY_ABS" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xCC, 0x00, 0x20 });
    bus.ram[0x2000] = 0x05;
    cpu.Y = 0x05;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 4), cycles);
}

test "CMP_ABS_X page cross costs extra cycle" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xDD, 0xFF, 0x20 });
    cpu.X = 0x01;
    bus.ram[0x2100] = 0x05;
    cpu.A = 0x05;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 5), cycles);
}

test "BRK_IMPL pushes PC and status, jumps to IRQ vector, sets break flag" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{0x00});
    bus.ram[0xFFFE] = 0x00;
    bus.ram[0xFFFF] = 0x90; // IRQ vector -> 0x9000
    const cycles = cpu.step();
    try testing.expectEqual(@as(u16, 0x9000), cpu.PC);
    try testing.expectEqual(@as(u1, 1), cpu.get_flag(.BREAK));
    try testing.expectEqual(@as(u8, 7), cycles);
}

test "LDA_IM" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xA9, 0x42 });
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 0x42), cpu.A);
    try testing.expectEqual(@as(u8, 2), cycles);
}

test "LDA_IM sets zero flag" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xA9, 0x00 });
    _ = cpu.step();
    try testing.expectEqual(@as(u1, 1), cpu.get_flag(.ZERO));
}

test "LDA_IM sets negative flag" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xA9, 0x80 });
    _ = cpu.step();
    try testing.expectEqual(@as(u1, 1), cpu.get_flag(.NEGATIVE));
}

test "LDA_ZP" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xA5, 0x10 });
    bus.ram[0x10] = 0x42;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 0x42), cpu.A);
    try testing.expectEqual(@as(u8, 3), cycles);
}

test "LDA_ZP_X" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xB5, 0x10 });
    cpu.X = 0x02;
    bus.ram[0x12] = 0x42;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 0x42), cpu.A);
    try testing.expectEqual(@as(u8, 4), cycles);
}

test "LDA_ZP_X wraps within zero page" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xB5, 0xFF });
    cpu.X = 0x02;
    bus.ram[0x01] = 0x42;
    _ = cpu.step();
    try testing.expectEqual(@as(u8, 0x42), cpu.A);
}

test "LDA_ABS" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xAD, 0x00, 0x20 });
    bus.ram[0x2000] = 0x42;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 0x42), cpu.A);
    try testing.expectEqual(@as(u8, 4), cycles);
}

test "LDA_ABS_X no page cross" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xBD, 0x00, 0x20 });
    cpu.X = 0x05;
    bus.ram[0x2005] = 0x42;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 0x42), cpu.A);
    try testing.expectEqual(@as(u8, 4), cycles);
}

test "LDA_ABS_X page cross" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xBD, 0xFF, 0x20 });
    cpu.X = 0x01;
    bus.ram[0x2100] = 0x42;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 0x42), cpu.A);
    try testing.expectEqual(@as(u8, 5), cycles);
}

test "LDA_ABS_Y page cross" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xB9, 0xFF, 0x20 });
    cpu.Y = 0x01;
    bus.ram[0x2100] = 0x42;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 5), cycles);
}

test "LDA_IND_X" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xA1, 0x10 });
    cpu.X = 0x04;
    bus.ram[0x14] = 0x00;
    bus.ram[0x15] = 0x30;
    bus.ram[0x3000] = 0x42;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 0x42), cpu.A);
    try testing.expectEqual(@as(u8, 6), cycles);
}

test "LDA_IND_Y" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xB1, 0x10 });
    bus.ram[0x10] = 0x00;
    bus.ram[0x11] = 0x30;
    cpu.Y = 0x05;
    bus.ram[0x3005] = 0x42;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 0x42), cpu.A);
    try testing.expectEqual(@as(u8, 5), cycles);
}

test "LDA_IND_Y page cross" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0xB1, 0x10 });
    bus.ram[0x10] = 0xFF;
    bus.ram[0x11] = 0x30;
    cpu.Y = 0x01;
    bus.ram[0x3100] = 0x42;
    const cycles = cpu.step();
    try testing.expectEqual(@as(u8, 6), cycles);
}

test "JSR_ABS pushes return address and jumps" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x20, 0x00, 0x90 }); // JSR $9000
    const cycles = cpu.step();
    try testing.expectEqual(@as(u16, 0x9000), cpu.PC);
    try testing.expectEqual(@as(u8, 6), cycles);
    try testing.expectEqual(@as(u8, 0xFB), cpu.SP);
}

test "JSR then RTS returns to instruction after JSR" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x20, 0x00, 0x90 }); // JSR $9000
    bus.ram[0x9000] = 0x60; // RTS
    _ = cpu.step(); // JSR
    _ = cpu.step(); // RTS
    try testing.expectEqual(@as(u16, 0x8003), cpu.PC); // instruction after JSR
    try testing.expectEqual(@as(u8, 0xFD), cpu.SP); // stack balanced
}

test "nested JSR/RTS" {
    var bus = TestBus{};
    var cpu = run(&bus, &.{ 0x20, 0x00, 0x90 }); // JSR $9000
    bus.ram[0x9000] = 0x20; // JSR $A000
    bus.ram[0x9001] = 0x00;
    bus.ram[0x9002] = 0xA0;
    bus.ram[0xA000] = 0x60; // RTS
    bus.ram[0x9003] = 0x60; // RTS
    _ = cpu.step(); // JSR $9000
    _ = cpu.step(); // JSR $A000
    _ = cpu.step(); // RTS -> back to 0x9003
    try testing.expectEqual(@as(u16, 0x9003), cpu.PC);
    _ = cpu.step(); // RTS -> back to 0x8003
    try testing.expectEqual(@as(u16, 0x8003), cpu.PC);
    try testing.expectEqual(@as(u8, 0xFD), cpu.SP);
}

test "reset loads PC from reset vector and sets SP/status defaults" {
    var bus = TestBus{};
    bus.ram[0xFFFC] = 0x34;
    bus.ram[0xFFFD] = 0x12;
    var cpu = CPU.init(&bus);
    cpu.reset();
    try testing.expectEqual(@as(u16, 0x1234), cpu.PC);
    try testing.expectEqual(@as(u8, 0xFD), cpu.SP);
    try testing.expectEqual(@as(u8, 0), cpu.A);
    try testing.expectEqual(@as(u8, 0), cpu.X);
    try testing.expectEqual(@as(u8, 0), cpu.Y);
}
