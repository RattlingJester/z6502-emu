const std = @import("std");
const opcodes = @import("opcodes.zig");
const log = std.log.scoped(.emulator);

pub const RomBuilder = @import("rom_builder.zig").RomBuilder;
pub const Op = opcodes.Op;

pub const CpuOptions = struct {
    decimal_mode: bool = false,
};

pub const StatusFlag = enum(u8) {
    CARRY = 1 << 0,
    ZERO = 1 << 1,
    INTERRUPT_DISABLE = 1 << 2,
    DECIMAL = 1 << 3,
    BREAK = 1 << 4,
    UNUSED = 1 << 5,
    OVERFLOW = 1 << 6,
    NEGATIVE = 1 << 7,
};

pub fn CPU(comptime Bus: type, comptime options: CpuOptions) type {
    return struct {
        const Self = @This();

        PC: u16 = Bus.RESET_VECTOR_ADDR,

        A: u8 = 0,
        X: u8 = 0,
        Y: u8 = 0,

        SP: u8 = Bus.STACK_START,
        status: u8 = 0b00110100,

        bus: *Bus,

        last_op: Op = undefined,

        pub fn init(bus: *Bus) Self {
            return .{ .bus = bus };
        }

        pub fn reset(self: *Self) void {
            self.PC = self.read_word(Bus.RESET_VECTOR_ADDR);
            self.A = 0;
            self.X = 0;
            self.Y = 0;

            self.SP = Bus.SP_RESET;
            self.status = 0b00110100;
        }

        pub fn fetch_byte(self: *Self) u8 {
            const op = self.read_byte(self.PC);
            self.PC +%= 1;
            return op;
        }

        pub fn fetch_word(self: *Self) u16 {
            const lo: u16 = self.fetch_byte();
            const hi: u16 = self.fetch_byte();

            return (hi << 8) | lo;
        }

        pub fn read_byte(self: *const Self, addr: u16) u8 {
            return self.bus.read(addr) catch @panic("Bus read returned error"); // TODO: proper error handling
        }

        pub fn read_word(self: *const Self, addr: u16) u16 {
            const lo: u16 = self.read_byte(addr);
            const hi: u16 = self.read_byte(addr +% 1);

            return (hi << 8) | lo;
        }

        pub fn read_word_zp(self: *const Self, addr: u8) u16 {
            const lo: u16 = self.read_byte(addr);
            const hi: u16 = self.read_byte(addr +% 1);

            return (hi << 8) | lo;
        }

        pub fn write_byte(self: *Self, addr: u16, value: u8) void {
            self.bus.write(addr, value) catch @panic("Bus write returned error"); // TODO: proper error handling
        }

        pub fn write_word(self: *Self, addr: u16, value: u16) void {
            self.write_byte(addr, @truncate(value & 0xFF));
            self.write_byte(addr +% 1, @truncate(value >> 8));
        }

        /// Stack is located on page 1, so 0x0100 is added to the adress
        pub fn push_byte(self: *Self, value: u8) void {
            self.write_byte(@as(u16, self.SP) + 0x0100, value);
            self.SP -%= 1;
        }

        /// Stack is located on page 1, so 0x0100 is added to the adress
        pub fn pop_byte(self: *Self) u8 {
            self.SP +%= 1;
            const value = self.read_byte(@as(u16, self.SP) + 0x0100);

            return value;
        }

        pub fn push_word(self: *Self, value: u16) void {
            self.push_byte(@truncate(value >> 8));
            self.push_byte(@truncate(value & 0xFF));
        }

        pub fn pop_word(self: *Self) u16 {
            const lo: u16 = self.pop_byte();
            const hi: u16 = self.pop_byte();

            return (hi << 8) | lo;
        }

        pub fn set_flag(self: *Self, flag: StatusFlag, on: bool) void {
            const bit = @intFromEnum(flag);

            if (on) {
                self.status |= bit;
            } else {
                self.status &= ~bit;
            }
        }

        pub fn get_flag(self: *const Self, flag: StatusFlag) u1 {
            return @intFromBool((self.status & @intFromEnum(flag)) != 0);
        }

        /// Returns number of cycles it took to execute the instruction
        pub fn execute(self: *Self, op: Op) u8 {
            self.last_op = op;
            return switch (op) {
                .ADC_IM => blk: {
                    const operand = self.fetch_byte();
                    self._adc(operand);
                    break :blk 2;
                },
                .ADC_ZP => blk: {
                    const addr = self.fetch_byte();
                    const operand = self.read_byte(addr);
                    self._adc(operand);

                    break :blk 3;
                },
                .ADC_ZP_X => blk: {
                    const base = self.fetch_byte();
                    const addr: u8 = base +% self.X;
                    const operand = self.read_byte(addr);
                    self._adc(operand);

                    break :blk 4;
                },
                .ADC_ABS => blk: {
                    const addr = self.fetch_word();
                    const operand = self.read_byte(addr);
                    self._adc(operand);

                    break :blk 4;
                },
                .ADC_ABS_X => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.X;
                    const operand = self.read_byte(addr);
                    self._adc(operand);

                    const extra: u8 = if (page_crossed(base, addr)) 1 else 0;
                    break :blk 4 + extra;
                },
                .ADC_ABS_Y => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.Y;
                    const operand = self.read_byte(addr);

                    self._adc(operand);

                    const extra: u8 = if (page_crossed(base, addr)) 1 else 0;
                    break :blk 4 + extra;
                },
                .ADC_IND_X => blk: {
                    const base = self.fetch_byte();
                    const addr = base +% self.X;
                    const target = self.read_word_zp(addr);
                    const operand = self.read_byte(target);
                    self._adc(operand);

                    break :blk 6;
                },
                .ADC_IND_Y => blk: {
                    const operand_addr = self.fetch_byte();
                    const base = self.read_word_zp(operand_addr);
                    const target = base +% self.Y;
                    const operand = self.read_byte(target);

                    self._adc(operand);

                    const extra: u8 = if (page_crossed(base, target)) 1 else 0;

                    break :blk 5 + extra;
                },

                .AND_IM => blk: {
                    const operand = self.fetch_byte();
                    self._and(operand);

                    break :blk 2;
                },
                .AND_ZP => blk: {
                    const addr = self.fetch_byte();
                    const operand = self.read_byte(addr);
                    self._and(operand);

                    break :blk 3;
                },
                .AND_ZP_X => blk: {
                    const base = self.fetch_byte();
                    const addr = base +% self.X;
                    const operand = self.read_byte(addr);
                    self._and(operand);

                    break :blk 4;
                },
                .AND_ABS => blk: {
                    const addr = self.fetch_word();
                    const operand = self.read_byte(addr);
                    self._and(operand);

                    break :blk 4;
                },
                .AND_ABS_X => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.X;
                    const operand = self.read_byte(addr);
                    self._and(operand);

                    const extra: u8 = if (page_crossed(base, addr)) 1 else 0;
                    break :blk 4 + extra;
                },
                .AND_ABS_Y => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.Y;
                    const operand = self.read_byte(addr);
                    self._and(operand);

                    const extra: u8 = if (page_crossed(base, addr)) 1 else 0;
                    break :blk 4 + extra;
                },
                .AND_IND_X => blk: {
                    const base = self.fetch_byte();
                    const addr = base +% self.X;
                    const target = self.read_word_zp(addr);
                    const operand = self.read_byte(target);
                    self._and(operand);

                    break :blk 6;
                },
                .AND_IND_Y => blk: {
                    const operand_addr = self.fetch_byte();
                    const base = self.read_word_zp(operand_addr);
                    const target = base +% self.Y;
                    const operand = self.read_byte(target);
                    self._and(operand);

                    const extra: u8 = if (page_crossed(base, target)) 1 else 0;
                    break :blk 5 + extra;
                },

                .ASL_ACC => blk: {
                    self.A = self._asl(self.A);

                    break :blk 2;
                },
                .ASL_ZP => blk: {
                    const addr = self.fetch_byte();
                    const operand = self.read_byte(addr);
                    const result = self._asl(operand);

                    self.write_byte(addr, result);

                    break :blk 5;
                },
                .ASL_ZP_X => blk: {
                    const base = self.fetch_byte();
                    const addr = base +% self.X;
                    const operand = self.read_byte(addr);
                    const result = self._asl(operand);

                    self.write_byte(addr, result);

                    break :blk 6;
                },
                .ASL_ABS => blk: {
                    const addr = self.fetch_word();
                    const operand = self.read_byte(addr);
                    const result = self._asl(operand);

                    self.write_byte(addr, result);

                    break :blk 6;
                },
                .ASL_ABS_X => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.X;
                    const operand = self.read_byte(addr);
                    const result = self._asl(operand);

                    self.write_byte(addr, result);

                    break :blk 7;
                },

                .BCC_REL => blk: {
                    const condition = self.get_flag(.CARRY) == 0;
                    const extra = self._bnc(condition);
                    break :blk 2 + extra;
                },
                .BCS_REL => blk: {
                    const condition = self.get_flag(.CARRY) == 1;
                    const extra = self._bnc(condition);
                    break :blk 2 + extra;
                },
                .BEQ_REL => blk: {
                    const condition = self.get_flag(.ZERO) == 1;
                    const extra = self._bnc(condition);
                    break :blk 2 + extra;
                },

                .BIT_ZP => blk: {
                    const addr = self.fetch_byte();
                    const operand = self.read_byte(addr);
                    self._bit(operand);
                    break :blk 3;
                },
                .BIT_ABS => blk: {
                    const addr = self.fetch_word();
                    const operand = self.read_byte(addr);
                    self._bit(operand);
                    break :blk 4;
                },

                .BMI_REL => blk: {
                    const condition = self.get_flag(.NEGATIVE) == 1;
                    const extra = self._bnc(condition);
                    break :blk 2 + extra;
                },
                .BNE_REL => blk: {
                    const condition = self.get_flag(.ZERO) == 0;
                    const extra = self._bnc(condition);
                    break :blk 2 + extra;
                },
                .BPL_REL => blk: {
                    const condition = self.get_flag(.NEGATIVE) == 0;
                    const extra = self._bnc(condition);
                    break :blk 2 + extra;
                },

                .BRK_IMPL => blk: {
                    const status = self.status | @intFromEnum(StatusFlag.BREAK) | @intFromEnum(StatusFlag.UNUSED);

                    self.push_word(self.PC +% 1);
                    self.push_byte(status);

                    self.PC = self.read_word(Bus.IRQ_VECTOR);
                    self.set_flag(.INTERRUPT_DISABLE, true);

                    break :blk 7;
                },

                .BVC_REL => blk: {
                    const condition = self.get_flag(.OVERFLOW) == 0;
                    const extra = self._bnc(condition);
                    break :blk 2 + extra;
                },
                .BVS_REL => blk: {
                    const condition = self.get_flag(.OVERFLOW) == 1;
                    const extra = self._bnc(condition);
                    break :blk 2 + extra;
                },

                .CLC_IMPL => blk: {
                    self.set_flag(.CARRY, false);
                    break :blk 2;
                },
                .CLD_IMPL => blk: {
                    self.set_flag(.DECIMAL, false);
                    break :blk 2;
                },
                .CLI_IMPL => blk: {
                    self.set_flag(.INTERRUPT_DISABLE, false);
                    break :blk 2;
                },
                .CLV_IMPL => blk: {
                    self.set_flag(.OVERFLOW, false);
                    break :blk 2;
                },

                .CMP_IM => blk: {
                    const operand = self.fetch_byte();
                    self._cmp(self.A, operand);

                    break :blk 2;
                },

                .CMP_ZP => blk: {
                    const addr = self.fetch_byte();
                    const operand = self.read_byte(addr);
                    self._cmp(self.A, operand);

                    break :blk 3;
                },

                .CMP_ZP_X => blk: {
                    const base = self.fetch_byte();
                    const addr = base +% self.X;
                    const operand = self.read_byte(addr);
                    self._cmp(self.A, operand);

                    break :blk 4;
                },

                .CMP_ABS => blk: {
                    const addr = self.fetch_word();
                    const operand = self.read_byte(addr);
                    self._cmp(self.A, operand);

                    break :blk 4;
                },

                .CMP_ABS_X => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.X;
                    const operand = self.read_byte(addr);
                    self._cmp(self.A, operand);

                    const extra: u8 = if (page_crossed(base, addr)) 1 else 0;
                    break :blk 4 + extra;
                },

                .CMP_ABS_Y => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.Y;
                    const operand = self.read_byte(addr);
                    self._cmp(self.A, operand);

                    const extra: u8 = if (page_crossed(base, addr)) 1 else 0;
                    break :blk 4 + extra;
                },

                .CMP_IND_X => blk: {
                    const base = self.fetch_byte();
                    const addr = base +% self.X;
                    const target = self.read_word_zp(addr);
                    const operand = self.read_byte(target);
                    self._cmp(self.A, operand);

                    break :blk 6;
                },

                .CMP_IND_Y => blk: {
                    const operand_addr = self.fetch_byte();
                    const base = self.read_word_zp(operand_addr);
                    const target = base +% self.Y;
                    const operand = self.read_byte(target);
                    self._cmp(self.A, operand);

                    const extra: u8 = if (page_crossed(base, target)) 1 else 0;
                    break :blk 5 + extra;
                },

                .CPX_IM => blk: {
                    const operand = self.fetch_byte();
                    self._cmp(self.X, operand);

                    break :blk 2;
                },
                .CPX_ZP => blk: {
                    const addr = self.fetch_byte();
                    const operand = self.read_byte(addr);
                    self._cmp(self.X, operand);

                    break :blk 3;
                },
                .CPX_ABS => blk: {
                    const addr = self.fetch_word();
                    const operand = self.read_byte(addr);
                    self._cmp(self.X, operand);

                    break :blk 4;
                },

                .CPY_IM => blk: {
                    const operand = self.fetch_byte();
                    self._cmp(self.Y, operand);

                    break :blk 2;
                },
                .CPY_ZP => blk: {
                    const addr = self.fetch_byte();
                    const operand = self.read_byte(addr);
                    self._cmp(self.Y, operand);

                    break :blk 3;
                },
                .CPY_ABS => blk: {
                    const addr = self.fetch_word();
                    const operand = self.read_byte(addr);
                    self._cmp(self.Y, operand);

                    break :blk 4;
                },

                .DEC_ZP => blk: {
                    const addr = self.fetch_byte();
                    const operand = self.read_byte(addr);
                    const result = self._dec(operand);
                    self.write_byte(addr, result);

                    break :blk 5;
                },
                .DEC_ZP_X => blk: {
                    const base = self.fetch_byte();
                    const addr = base +% self.X;
                    const operand = self.read_byte(addr);
                    const result = self._dec(operand);
                    self.write_byte(addr, result);

                    break :blk 6;
                },
                .DEC_ABS => blk: {
                    const addr = self.fetch_word();
                    const operand = self.read_byte(addr);
                    const result = self._dec(operand);
                    self.write_byte(addr, result);

                    break :blk 6;
                },
                .DEC_ABS_X => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.X;
                    const operand = self.read_byte(addr);
                    const result = self._dec(operand);
                    self.write_byte(addr, result);

                    break :blk 7;
                },
                .DEX_IMPL => blk: {
                    const result = self.X -% 1;
                    self.X = result;

                    self.set_flag(.ZERO, result == 0);
                    self.set_flag(.NEGATIVE, (result & (1 << 7)) != 0);

                    break :blk 2;
                },
                .DEY_IMPL => blk: {
                    const result = self.Y -% 1;
                    self.Y = result;

                    self.set_flag(.ZERO, result == 0);
                    self.set_flag(.NEGATIVE, (result & (1 << 7)) != 0);

                    break :blk 2;
                },

                .EOR_IM => blk: {
                    const operand = self.fetch_byte();
                    self._eor(operand);

                    break :blk 2;
                },
                .EOR_ZP => blk: {
                    const addr = self.fetch_byte();
                    const operand = self.read_byte(addr);
                    self._eor(operand);

                    break :blk 3;
                },
                .EOR_ZP_X => blk: {
                    const base = self.fetch_byte();
                    const addr = base +% self.X;
                    const operand = self.read_byte(addr);
                    self._eor(operand);

                    break :blk 4;
                },
                .EOR_ABS => blk: {
                    const addr = self.fetch_word();
                    const operand = self.read_byte(addr);
                    self._eor(operand);

                    break :blk 4;
                },
                .EOR_ABS_X => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.X;
                    const operand = self.read_byte(addr);
                    self._eor(operand);

                    const extra: u8 = if (page_crossed(base, addr)) 1 else 0;
                    break :blk 4 + extra;
                },
                .EOR_ABS_Y => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.Y;
                    const operand = self.read_byte(addr);
                    self._eor(operand);

                    const extra: u8 = if (page_crossed(base, addr)) 1 else 0;
                    break :blk 4 + extra;
                },
                .EOR_IND_X => blk: {
                    const base = self.fetch_byte();
                    const addr = base +% self.X;
                    const target = self.read_word_zp(addr);
                    const operand = self.read_byte(target);
                    self._eor(operand);

                    break :blk 6;
                },
                .EOR_IND_Y => blk: {
                    const operand_addr = self.fetch_byte();
                    const base = self.read_word_zp(operand_addr);
                    const target = base +% self.Y;
                    const operand = self.read_byte(target);
                    self._eor(operand);

                    const extra: u8 = if (page_crossed(base, target)) 1 else 0;
                    break :blk 5 + extra;
                },

                .INC_ZP => blk: {
                    const addr = self.fetch_byte();
                    const operand = self.read_byte(addr);
                    const result = self._inc(operand);
                    self.write_byte(addr, result);

                    break :blk 5;
                },
                .INC_ZP_X => blk: {
                    const base = self.fetch_byte();
                    const addr = base +% self.X;
                    const operand = self.read_byte(addr);
                    const result = self._inc(operand);
                    self.write_byte(addr, result);

                    break :blk 6;
                },
                .INC_ABS => blk: {
                    const addr = self.fetch_word();
                    const operand = self.read_byte(addr);
                    const result = self._inc(operand);
                    self.write_byte(addr, result);

                    break :blk 6;
                },
                .INC_ABS_X => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.X;
                    const operand = self.read_byte(addr);
                    const result = self._inc(operand);
                    self.write_byte(addr, result);

                    break :blk 7;
                },
                .INX_IMPL => blk: {
                    const result = self.X +% 1;
                    self.X = result;

                    self.set_flag(.ZERO, result == 0);
                    self.set_flag(.NEGATIVE, (result & (1 << 7)) != 0);

                    break :blk 2;
                },
                .INY_IMPL => blk: {
                    const result = self.Y +% 1;
                    self.Y = result;

                    self.set_flag(.ZERO, result == 0);
                    self.set_flag(.NEGATIVE, (result & (1 << 7)) != 0);

                    break :blk 2;
                },

                .JMP_ABS => blk: {
                    const addr = self.fetch_word();
                    self.PC = addr;

                    break :blk 3;
                },
                .JMP_IND => blk: {
                    const vector = self.fetch_word();

                    const lo = self.read_byte(vector);

                    // An original 6502 has does not correctly fetch the target address if the indirect vector falls on a page boundary
                    // (e.g. $xxFF where xx is any value from $00 to $FF).
                    // In this case fetches the LSB from $xxFF as expected but takes the MSB from $xx00.

                    const hi_addr = if ((vector & 0x00FF) == 0x00FF)
                        vector & 0xFF00
                    else
                        vector +% 1;

                    const hi = self.read_byte(hi_addr);

                    self.PC = (@as(u16, hi) << 8) | lo;

                    break :blk 5;
                },

                .JSR_ABS => blk: {
                    const target = self.fetch_word();
                    self.push_word(self.PC -% 1);
                    self.PC = target;

                    break :blk 6;
                },

                .LDA_IM => blk: {
                    self.A = self.fetch_byte();

                    self.set_flag(.ZERO, self.A == 0);
                    self.set_flag(.NEGATIVE, (self.A & 1 << 7) != 0);

                    break :blk 2;
                },
                .LDA_ZP => blk: {
                    const target = self.fetch_byte();
                    self._ld(&self.A, target);

                    break :blk 3;
                },
                .LDA_ZP_X => blk: {
                    const operand = self.fetch_byte();
                    const target: u8 = operand +% self.X;
                    self._ld(&self.A, target);

                    break :blk 4;
                },
                .LDA_ABS => blk: {
                    const operand = self.fetch_word();
                    self._ld(&self.A, operand);

                    break :blk 4;
                },
                .LDA_ABS_X => blk: {
                    const operand = self.fetch_word();
                    const addr = operand +% self.X;
                    self._ld(&self.A, addr);

                    const extra: u8 = if (page_crossed(operand, addr)) 1 else 0;
                    break :blk 4 + extra;
                },
                .LDA_ABS_Y => blk: {
                    const operand = self.fetch_word();
                    const addr = operand +% self.Y;
                    self._ld(&self.A, addr);

                    const extra: u8 = if (page_crossed(operand, addr)) 1 else 0;
                    break :blk 4 + extra;
                },
                .LDA_IND_X => blk: {
                    const operand = self.fetch_byte();
                    const addr = operand +% self.X;
                    const target = self.read_word_zp(addr);
                    self._ld(&self.A, target);

                    break :blk 6;
                },
                .LDA_IND_Y => blk: {
                    const operand = self.fetch_byte();
                    const addr = self.read_word_zp(operand);
                    const target = addr +% self.Y;
                    self._ld(&self.A, target);

                    const extra: u8 = if (page_crossed(addr, target)) 1 else 0;
                    break :blk 5 + extra;
                },

                .LDX_IM => blk: {
                    self.X = self.fetch_byte();
                    self.set_flag(.ZERO, self.X == 0);
                    self.set_flag(.NEGATIVE, (self.X & (1 << 7)) != 0);

                    break :blk 2;
                },
                .LDX_ZP => blk: {
                    const addr = self.fetch_byte();
                    self._ld(&self.X, addr);
                    break :blk 3;
                },

                .LDX_ZP_Y => blk: {
                    const base = self.fetch_byte();
                    const addr = base +% self.Y;
                    self._ld(&self.X, addr);
                    break :blk 4;
                },

                .LDX_ABS => blk: {
                    const addr = self.fetch_word();
                    self._ld(&self.X, addr);
                    break :blk 4;
                },

                .LDX_ABS_Y => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.Y;
                    self._ld(&self.X, addr);

                    const extra: u8 = if (page_crossed(base, addr)) 1 else 0;
                    break :blk 4 + extra;
                },

                .LDY_IM => blk: {
                    const operand = self.fetch_byte();
                    self.Y = operand;
                    self.set_flag(.ZERO, self.Y == 0);
                    self.set_flag(.NEGATIVE, (self.Y & (1 << 7)) != 0);

                    break :blk 2;
                },
                .LDY_ZP => blk: {
                    const addr = self.fetch_byte();
                    self._ld(&self.Y, addr);

                    break :blk 3;
                },
                .LDY_ZP_X => blk: {
                    const base = self.fetch_byte();
                    const addr = base +% self.X;
                    self._ld(&self.Y, addr);

                    break :blk 4;
                },
                .LDY_ABS => blk: {
                    const addr = self.fetch_word();
                    self._ld(&self.Y, addr);

                    break :blk 4;
                },

                .LDY_ABS_X => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.X;
                    self._ld(&self.Y, addr);

                    const extra: u8 = if (page_crossed(base, addr)) 1 else 0;
                    break :blk 4 + extra;
                },

                .LSR_ACC => blk: {
                    self.A = self._lsr(self.A);

                    break :blk 2;
                },
                .LSR_ZP => blk: {
                    const addr = self.fetch_byte();
                    const operand = self.read_byte(addr);
                    const result = self._lsr(operand);
                    self.write_byte(addr, result);

                    break :blk 5;
                },
                .LSR_ZP_X => blk: {
                    const base = self.fetch_byte();
                    const addr = base +% self.X;
                    const operand = self.read_byte(addr);
                    const result = self._lsr(operand);
                    self.write_byte(addr, result);

                    break :blk 6;
                },
                .LSR_ABS => blk: {
                    const addr = self.fetch_word();
                    const operand = self.read_byte(addr);
                    const result = self._lsr(operand);
                    self.write_byte(addr, result);

                    break :blk 6;
                },

                .LSR_ABS_X => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.X;
                    const operand = self.read_byte(addr);
                    const result = self._lsr(operand);
                    self.write_byte(addr, result);

                    break :blk 7;
                },

                .NOP_IMPL => blk: {
                    break :blk 2;
                },

                .ORA_IM => blk: {
                    const operand = self.fetch_byte();
                    self._ora(operand);

                    break :blk 2;
                },
                .ORA_ZP => blk: {
                    const addr = self.fetch_byte();
                    const operand = self.read_byte(addr);
                    self._ora(operand);

                    break :blk 3;
                },
                .ORA_ZP_X => blk: {
                    const base = self.fetch_byte();
                    const addr = base +% self.X;
                    const operand = self.read_byte(addr);
                    self._ora(operand);

                    break :blk 4;
                },
                .ORA_ABS => blk: {
                    const addr = self.fetch_word();
                    const operand = self.read_byte(addr);
                    self._ora(operand);

                    break :blk 4;
                },
                .ORA_ABS_X => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.X;
                    const operand = self.read_byte(addr);
                    self._ora(operand);

                    const extra: u8 = if (page_crossed(base, addr)) 1 else 0;
                    break :blk 4 + extra;
                },
                .ORA_ABS_Y => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.Y;
                    const operand = self.read_byte(addr);
                    self._ora(operand);

                    const extra: u8 = if (page_crossed(base, addr)) 1 else 0;
                    break :blk 4 + extra;
                },
                .ORA_IND_X => blk: {
                    const base = self.fetch_byte();
                    const addr = base +% self.X;
                    const target = self.read_word_zp(addr);
                    const operand = self.read_byte(target);
                    self._ora(operand);

                    break :blk 6;
                },
                .ORA_IND_Y => blk: {
                    const operand_addr = self.fetch_byte();
                    const base = self.read_word_zp(operand_addr);

                    const target = base +% self.Y;
                    const operand = self.read_byte(target);
                    self._ora(operand);

                    const extra: u8 = if (page_crossed(base, target)) 1 else 0;
                    break :blk 5 + extra;
                },

                .PHA_IMPL => blk: {
                    self.push_byte(self.A);

                    break :blk 3;
                },
                .PHP_IMPL => blk: {
                    const status = self.status | @intFromEnum(StatusFlag.BREAK) | @intFromEnum(StatusFlag.UNUSED);
                    self.push_byte(status);

                    break :blk 3;
                },
                .PLA_IMPL => blk: {
                    self.A = self.pop_byte();

                    self.set_flag(.ZERO, self.A == 0);
                    self.set_flag(.NEGATIVE, (self.A & 1 << 7) != 0);

                    break :blk 4;
                },
                .PLP_IMPL => blk: {
                    self.status = self.pop_byte();

                    break :blk 4;
                },

                .ROL_ACC => blk: {
                    self.A = self._rol(self.A);

                    break :blk 2;
                },
                .ROL_ZP => blk: {
                    const addr = self.fetch_byte();
                    const operand = self.read_byte(addr);
                    const result = self._rol(operand);
                    self.write_byte(addr, result);

                    break :blk 5;
                },
                .ROL_ZP_X => blk: {
                    const base = self.fetch_byte();
                    const addr = base +% self.X;
                    const operand = self.read_byte(addr);
                    const result = self._rol(operand);
                    self.write_byte(addr, result);

                    break :blk 6;
                },
                .ROL_ABS => blk: {
                    const addr = self.fetch_word();
                    const operand = self.read_byte(addr);
                    const result = self._rol(operand);
                    self.write_byte(addr, result);

                    break :blk 6;
                },
                .ROL_ABS_X => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.X;
                    const operand = self.read_byte(addr);
                    const result = self._rol(operand);
                    self.write_byte(addr, result);

                    break :blk 7;
                },
                .ROR_ACC => blk: {
                    self.A = self._ror(self.A);

                    break :blk 2;
                },
                .ROR_ZP => blk: {
                    const addr = self.fetch_byte();
                    const operand = self.read_byte(addr);
                    const result = self._ror(operand);
                    self.write_byte(addr, result);

                    break :blk 5;
                },
                .ROR_ZP_X => blk: {
                    const base = self.fetch_byte();
                    const addr = base +% self.X;
                    const operand = self.read_byte(addr);
                    const result = self._ror(operand);
                    self.write_byte(addr, result);

                    break :blk 6;
                },
                .ROR_ABS => blk: {
                    const addr = self.fetch_word();
                    const operand = self.read_byte(addr);
                    const result = self._ror(operand);
                    self.write_byte(addr, result);

                    break :blk 6;
                },
                .ROR_ABS_X => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.X;
                    const operand = self.read_byte(addr);
                    const result = self._ror(operand);
                    self.write_byte(addr, result);

                    break :blk 7;
                },

                .RTI_IMPL => blk: {
                    self.status = self.pop_byte();
                    self.PC = self.pop_word();

                    break :blk 6;
                },

                .RTS_IMPL => blk: {
                    const return_addr = self.pop_word();
                    self.PC = return_addr +% 1;

                    break :blk 6;
                },

                .SBC_IM => blk: {
                    const operand = self.fetch_byte();
                    self._sbc(operand);

                    break :blk 2;
                },
                .SBC_ZP => blk: {
                    const addr = self.fetch_byte();
                    const operand = self.read_byte(addr);
                    self._sbc(operand);
                    break :blk 3;
                },
                .SBC_ZP_X => blk: {
                    const base = self.fetch_byte();
                    const addr = base +% self.X;
                    const operand = self.read_byte(addr);
                    self._sbc(operand);

                    break :blk 4;
                },
                .SBC_ABS => blk: {
                    const addr = self.fetch_word();
                    const operand = self.read_byte(addr);
                    self._sbc(operand);

                    break :blk 4;
                },
                .SBC_ABS_X => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.X;
                    const operand = self.read_byte(addr);
                    self._sbc(operand);

                    const extra: u8 = if (page_crossed(base, addr)) 1 else 0;
                    break :blk 4 + extra;
                },
                .SBC_ABS_Y => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.Y;
                    const operand = self.read_byte(addr);
                    self._sbc(operand);

                    const extra: u8 = if (page_crossed(base, addr)) 1 else 0;
                    break :blk 4 + extra;
                },
                .SBC_IND_X => blk: {
                    const base = self.fetch_byte();
                    const addr = base +% self.X;
                    const target = self.read_word_zp(addr);
                    const operand = self.read_byte(target);
                    self._sbc(operand);

                    break :blk 6;
                },
                .SBC_IND_Y => blk: {
                    const operand_addr = self.fetch_byte();
                    const base = self.read_word_zp(operand_addr);
                    const target = base +% self.Y;
                    const operand = self.read_byte(target);
                    self._sbc(operand);

                    const extra: u8 = if (page_crossed(base, target)) 1 else 0;
                    break :blk 5 + extra;
                },

                .SEC_IMPL => blk: {
                    self.set_flag(.CARRY, true);
                    break :blk 2;
                },
                .SED_IMPL => blk: {
                    self.set_flag(.DECIMAL, true);
                    break :blk 2;
                },
                .SEI_IMPL => blk: {
                    self.set_flag(.INTERRUPT_DISABLE, true);
                    break :blk 2;
                },

                .STA_ZP => blk: {
                    const addr = self.fetch_byte();
                    self.write_byte(addr, self.A);

                    break :blk 3;
                },
                .STA_ZP_X => blk: {
                    const base = self.fetch_byte();
                    const addr = base +% self.X;
                    self.write_byte(addr, self.A);

                    break :blk 4;
                },
                .STA_ABS => blk: {
                    const addr = self.fetch_word();
                    self.write_byte(addr, self.A);

                    break :blk 4;
                },
                .STA_ABS_X => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.X;
                    self.write_byte(addr, self.A);

                    break :blk 5;
                },
                .STA_ABS_Y => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.Y;
                    self.write_byte(addr, self.A);

                    break :blk 5;
                },
                .STA_IND_X => blk: {
                    const base = self.fetch_byte();
                    const addr = base +% self.X;
                    const target = self.read_word_zp(addr);
                    self.write_byte(target, self.A);

                    break :blk 6;
                },
                .STA_IND_Y => blk: {
                    const operand_addr = self.fetch_byte();
                    const base = self.read_word_zp(operand_addr);
                    const target = base +% self.Y;
                    self.write_byte(target, self.A);

                    break :blk 6;
                },

                .STX_ZP => blk: {
                    const addr = self.fetch_byte();
                    self.write_byte(addr, self.X);

                    break :blk 3;
                },
                .STX_ZP_Y => blk: {
                    const base = self.fetch_byte();
                    const addr = base +% self.Y;
                    self.write_byte(addr, self.X);

                    break :blk 4;
                },
                .STX_ABS => blk: {
                    const addr = self.fetch_word();
                    self.write_byte(addr, self.X);

                    break :blk 4;
                },
                .STY_ZP => blk: {
                    const addr = self.fetch_byte();
                    self.write_byte(addr, self.Y);

                    break :blk 3;
                },
                .STY_ZP_X => blk: {
                    const base = self.fetch_byte();
                    const addr = base +% self.X;
                    self.write_byte(addr, self.Y);

                    break :blk 4;
                },
                .STY_ABS => blk: {
                    const addr = self.fetch_word();
                    self.write_byte(addr, self.Y);

                    break :blk 4;
                },

                .TAX_IMPL => blk: {
                    self.X = self.A;
                    self.set_flag(.ZERO, self.X == 0);
                    self.set_flag(.NEGATIVE, (self.X & (1 << 7)) != 0);
                    break :blk 2;
                },
                .TAY_IMPL => blk: {
                    self.Y = self.A;
                    self.set_flag(.ZERO, self.Y == 0);
                    self.set_flag(.NEGATIVE, (self.Y & (1 << 7)) != 0);
                    break :blk 2;
                },
                .TSX_IMPL => blk: {
                    self.X = self.SP;
                    self.set_flag(.ZERO, self.X == 0);
                    self.set_flag(.NEGATIVE, (self.X & (1 << 7)) != 0);
                    break :blk 2;
                },
                .TXA_IMPL => blk: {
                    self.A = self.X;
                    self.set_flag(.ZERO, self.A == 0);
                    self.set_flag(.NEGATIVE, (self.A & (1 << 7)) != 0);
                    break :blk 2;
                },
                .TXS_IMPL => blk: {
                    self.SP = self.X;
                    break :blk 2;
                },
                .TYA_IMPL => blk: {
                    self.A = self.Y;
                    self.set_flag(.ZERO, self.A == 0);
                    self.set_flag(.NEGATIVE, (self.A & (1 << 7)) != 0);
                    break :blk 2;
                },
            };
        }

        /// Returns number of cycles it took to execute an instruction
        pub fn step(self: *Self) u8 {
            const op = self.fetch_byte();

            return self.execute(@enumFromInt(op));
        }

        pub fn print_state(self: *const Self) void {
            log.info("--- CPU State ---", .{});
            log.info("CPU PC register: 0x{X}", .{self.PC});
            log.info("CPU A register: 0x{X}", .{self.A});
            log.info("CPU X register: 0x{X}", .{self.X});
            log.info("CPU Y register: 0x{X}", .{self.Y});
            log.info("CPU SP register: 0x{X}", .{self.SP});
            log.info("CPU status register: 0b{b}", .{self.status});
            log.info("Last executed OP: {}", .{self.last_op});
        }

        pub fn print_stack(self: *const Self) void {
            log.info("--- Stack Trace ---", .{});

            if (self.SP == Bus.SP_RESET) {
                log.info("[Stack Empty]", .{});
                return;
            }

            var addr: u16 = @as(u16, self.SP + 1) + 0x0100;
            const end_addr: u16 = Bus.SP_RESET + 0x0100;

            while (addr <= end_addr) : (addr +%= 1) {
                const value = self.read_byte(addr);
                log.info("Addr: 0x{X:04} -> Value: 0x{X:02}", .{
                    addr,
                    value,
                });
            }
        }

        inline fn _ld(self: *Self, reg: *u8, target: u16) void {
            reg.* = self.read_byte(target);
            self.set_flag(.ZERO, reg.* == 0);
            self.set_flag(.NEGATIVE, (reg.* & (1 << 7)) != 0);
        }

        inline fn _adc(self: *Self, operand: u8) void {
            if (comptime options.decimal_mode) {
                if (self.get_flag(.DECIMAL) == 1) {
                    self._adc_decimal(operand);
                    return;
                }
            }

            const sum: u16 = @as(u16, self.A) + @as(u16, operand) + self.get_flag(.CARRY);
            self.set_flag(.CARRY, sum > 0xFF);
            const overflow = ((self.A ^ sum) & (operand ^ sum) & 1 << 7) != 0;
            self.set_flag(.OVERFLOW, overflow);

            self.A = @truncate(sum);
            self.set_flag(.ZERO, self.A == 0);
            self.set_flag(.NEGATIVE, (self.A & 1 << 7) != 0);
        }

        inline fn _adc_decimal(self: *Self, operand: u8) void {
            const carry_in = self.get_flag(.CARRY);
            const a_lo: u4 = @truncate(self.A);
            const op_lo: u4 = @truncate(operand);

            var lo = @as(u8, a_lo) + op_lo + carry_in;
            var lo_carry: u8 = 0;
            if (lo > 9) {
                lo += 6;
                lo_carry = 1;
            }

            const a_hi: u4 = @truncate(self.A >> 4);
            const op_hi: u4 = @truncate(operand >> 4);
            var hi = @as(u8, a_hi) + op_hi + lo_carry;

            var hi_carry: u8 = 0;
            if (hi > 9) {
                hi += 6;
                hi_carry = 1;
            }

            const bin_sum: u8 = @truncate(@as(u16, self.A) + operand + carry_in);
            const overflow = ((self.A ^ bin_sum) & (operand ^ bin_sum) & 0x80) != 0;
            self.set_flag(.OVERFLOW, overflow);

            const result: u8 = ((hi & 0x0F) << 4) | (lo & 0x0F);
            self.A = result;

            self.set_flag(.CARRY, hi_carry == 1);
            self.set_flag(.ZERO, self.A == 0);
            self.set_flag(.NEGATIVE, (self.A & 1 << 7) != 0);
        }

        inline fn _and(self: *Self, operand: u8) void {
            self.A &= operand;
            self.set_flag(.ZERO, self.A == 0);
            self.set_flag(.NEGATIVE, (self.A & (1 << 7)) != 0);
        }

        inline fn _asl(self: *Self, operand: u8) u8 {
            self.set_flag(.CARRY, (operand & (1 << 7)) != 0);

            const result = operand << 1;

            self.set_flag(.ZERO, result == 0);
            self.set_flag(.NEGATIVE, (result & (1 << 7)) != 0);

            return result;
        }

        inline fn _bnc(self: *Self, condition: bool) u8 {
            const offset: i8 = @bitCast(self.fetch_byte());

            if (condition) {
                const old_PC = self.PC;
                // Handle negative offsets
                self.PC = @bitCast(@as(i16, @bitCast(old_PC)) +% offset);

                const extra: u8 = if (page_crossed(old_PC, self.PC)) 1 else 0;
                return 1 + extra;
            }

            return 0;
        }

        inline fn _bit(self: *Self, operand: u8) void {
            self.set_flag(.ZERO, (self.A & operand) == 0);

            self.set_flag(.NEGATIVE, (operand & (1 << 7)) != 0);
            self.set_flag(.OVERFLOW, (operand & (1 << 6)) != 0);
        }

        inline fn _cmp(self: *Self, reg_val: u8, operand: u8) void {
            self.set_flag(.CARRY, reg_val >= operand);
            const result = reg_val -% operand;
            self.set_flag(.ZERO, result == 0);
            self.set_flag(.NEGATIVE, (result & (1 << 7)) != 0);
        }

        inline fn _dec(self: *Self, operand: u8) u8 {
            const result = operand -% 1;

            self.set_flag(.ZERO, (result == 0));
            self.set_flag(.NEGATIVE, (result & (1 << 7)) != 0);

            return result;
        }

        inline fn _eor(self: *Self, operand: u8) void {
            self.A ^= operand;
            self.set_flag(.ZERO, self.A == 0);
            self.set_flag(.NEGATIVE, (self.A & (1 << 7)) != 0);
        }

        inline fn _inc(self: *Self, operand: u8) u8 {
            const result = operand +% 1;

            self.set_flag(.ZERO, (result == 0));
            self.set_flag(.NEGATIVE, (result & (1 << 7)) != 0);

            return result;
        }

        inline fn _lsr(self: *Self, operand: u8) u8 {
            self.set_flag(.CARRY, (operand & 1) != 0);

            const result = operand >> 1;

            self.set_flag(.ZERO, result == 0);
            self.set_flag(.NEGATIVE, false);

            return result;
        }

        inline fn _ora(self: *Self, operand: u8) void {
            self.A |= operand;
            self.set_flag(.ZERO, self.A == 0);
            self.set_flag(.NEGATIVE, (self.A & (1 << 7)) != 0);
        }

        inline fn _rol(self: *Self, operand: u8) u8 {
            const old_carry: u8 = self.get_flag(.CARRY);

            self.set_flag(.CARRY, (operand & (1 << 7)) != 0);

            const result = (operand << 1) | old_carry;

            self.set_flag(.ZERO, result == 0);
            self.set_flag(.NEGATIVE, (result & (1 << 7)) != 0);

            return result;
        }

        inline fn _ror(self: *Self, operand: u8) u8 {
            const old_carry: u8 = self.get_flag(.CARRY);

            self.set_flag(.CARRY, (operand & 1) != 0);

            const result = (operand >> 1) | (old_carry << 7);

            self.set_flag(.ZERO, result == 0);
            self.set_flag(.NEGATIVE, (result & (1 << 7)) != 0);

            return result;
        }

        inline fn _sbc(self: *Self, operand: u8) void {
            if (comptime options.decimal_mode) {
                if (self.get_flag(.DECIMAL) == 1) {
                    self._sbc_decimal(operand);
                    return;
                }
            }

            self._adc(~operand);
        }

        inline fn _sbc_decimal(self: *Self, operand: u8) void {
            const carry_in = self.get_flag(.CARRY);
            const a_lo: u4 = @truncate(self.A);
            const op_lo: u4 = @truncate(operand);

            var lo: i16 = @as(i16, a_lo) - @as(i16, op_lo) - (1 - @as(i16, carry_in));
            var lo_borrow: i16 = 0;
            if (lo < 0) {
                lo -= 6;
                lo_borrow = 1;
            }

            const a_hi: u4 = @truncate(self.A >> 4);
            const op_hi: u4 = @truncate(operand >> 4);
            var hi: i16 = @as(i16, a_hi) - @as(i16, op_hi) - lo_borrow;

            if (hi < 0) {
                hi -= 6;
            }

            const bin_sum: u16 = @as(u16, self.A) +% ~operand +% carry_in;
            const bin_result: u8 = @truncate(bin_sum);

            const overflow = ((self.A ^ bin_result) & (~operand ^ bin_result) & 0x80) != 0;
            self.set_flag(.OVERFLOW, overflow);

            const lo_digit: u8 = @intCast(@mod(lo, 16));
            const hi_digit: u8 = @intCast(@mod(hi, 16));
            self.A = (hi_digit << 4) | lo_digit;

            self.set_flag(.CARRY, bin_sum > 0xFF);
            self.set_flag(.ZERO, self.A == 0);
            self.set_flag(.NEGATIVE, (self.A & 0x80) != 0);
        }
    };
}

inline fn page_crossed(base: u16, final: u16) bool {
    return (base & 0xFF00) != (final & 0xFF00);
}
