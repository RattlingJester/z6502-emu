pub const root = @This();

const opcodes = @import("opcodes.zig");

pub const RomBuilder = @import("builder.zig").RomBuilder;
pub const Op = opcodes.Op;

const std = @import("std");
const log = std.log.scoped(.emulator);

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

pub fn CPU(comptime Bus: type) type {
    return struct {
        const Self = @This();

        PC: u16 = Bus.RESET_VECTOR,

        A: u8 = 0,
        X: u8 = 0,
        Y: u8 = 0,

        SP: u8 = Bus.STACK_START,
        status: u8 = 0b00110100,

        bus: *Bus,

        pub fn init(bus: *Bus) Self {
            return .{ .bus = bus };
        }

        pub fn reset(self: *Self) void {
            self.PC = self.read_word(Bus.RESET_VECTOR);
            self.A = 0;
            self.X = 0;
            self.Y = 0;

            self.SP = Bus.STACK_START;
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
            return self.bus.read(addr);
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
            self.bus.write(addr, value);
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
            self.push_byte(@truncate(value & 0xFF));
            self.push_byte(@truncate(value >> 8));
        }

        pub fn pop_word(self: *Self) u16 {
            const hi: u16 = self.pop_byte();
            const lo: u16 = self.pop_byte();

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

                    const extra: u8 = if (page_crossed(addr, addr)) 1 else 0;
                    break :blk 4 + extra;
                },
                .ADC_ABS_Y => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.Y;
                    const operand = self.read_byte(addr);

                    self._adc(operand);

                    const extra: u8 = if (page_crossed(addr, addr)) 1 else 0;
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

                    break :blk 6 + extra;
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

                    const extra: u8 = if (page_crossed(addr, addr)) 1 else 0;
                    break :blk 4 + extra;
                },
                .AND_ABS_Y => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.Y;
                    const operand = self.read_byte(addr);
                    self._and(operand);

                    const extra: u8 = if (page_crossed(addr, addr)) 1 else 0;
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

                    const extra: u8 = if (page_crossed(base, self.PC)) 1 else 0;
                    break :blk 4 + extra;
                },

                .CMP_ABS_Y => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.Y;
                    const operand = self.read_byte(addr);
                    self._cmp(self.A, operand);

                    const extra: u8 = if (page_crossed(base, self.PC)) 1 else 0;
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

                    const extra: u8 = if (page_crossed(base, self.PC)) 1 else 0;
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

                .BIT_ZP => blk: {
                    break :blk undefined;
                },
                .BIT_ABS => blk: {
                    break :blk undefined;
                },

                .BRK_IMPL => blk: {
                    self.push_word(self.PC);
                    self.push_byte(self.status);

                    self.PC = Bus.IRQ_VECTOR;
                    self.set_flag(.BREAK, true);

                    break :blk 7;
                },

                .LDA_IM => blk: {
                    self.A = self.fetch_byte();

                    self.set_flag(.ZERO, self.A == 0);
                    self.set_flag(.NEGATIVE, (self.A & 1 << 7) != 0);

                    break :blk 2;
                },
                .LDA_ZP => blk: {
                    const target = self.fetch_byte();
                    self._lda(target);

                    break :blk 3;
                },
                .LDA_ZP_X => blk: {
                    const operand = self.fetch_byte();
                    const target: u8 = operand +% self.X;
                    self._lda(target);

                    break :blk 4;
                },
                .LDA_ABS => blk: {
                    const operand = self.fetch_word();
                    self._lda(operand);

                    break :blk 4;
                },
                .LDA_ABS_X => blk: {
                    const operand = self.fetch_word();
                    const addr = operand +% self.X;
                    self._lda(addr);

                    const extra: u8 = if (page_crossed(operand, addr)) 1 else 0;
                    break :blk 4 + extra;
                },
                .LDA_ABS_Y => blk: {
                    const operand = self.fetch_word();
                    const addr = operand +% self.Y;
                    self._lda(addr);

                    const extra: u8 = if (page_crossed(operand, addr)) 1 else 0;
                    break :blk 4 + extra;
                },
                .LDA_IND_X => blk: {
                    const operand = self.fetch_byte();
                    const addr = operand +% self.X;
                    const target = self.read_word_zp(addr);
                    self._lda(target);

                    break :blk 6;
                },
                .LDA_IND_Y => blk: {
                    const operand = self.fetch_byte();
                    const addr = self.read_word_zp(operand);
                    const target = addr +% self.Y;
                    self._lda(target);

                    const extra: u8 = if (page_crossed(addr, target)) 1 else 0;
                    break :blk 5 + extra;
                },

                .JSR_ABS => blk: {
                    const target = self.fetch_word();
                    self.push_word(self.PC -% 1);
                    self.PC = target;

                    break :blk 6;
                },
                .RTS_IMPL => blk: {
                    const return_addr = self.pop_word();
                    self.PC = return_addr +% 1;

                    break :blk 6;
                },

                else => {
                    log.err("Instruction {} (0x{X}) is not handled", .{ op, op });
                    self.print_state();
                    unreachable;
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
        }

        pub fn print_stack(self: *const Self) void {
            log.info("--- Stack Trace ---", .{});

            if (self.SP == Bus.STACK_START) {
                log.info("[Stack Empty]", .{});
                return;
            }

            var addr: u16 = @as(u16, self.SP + 1) + 0x0100;
            const end_addr: u16 = Bus.STACK_START + 0x0100;

            while (addr <= end_addr) : (addr +%= 1) {
                const value = self.read_byte(addr);
                log.info("Addr: 0x{X:04} -> Value: 0x{X:02}", .{
                    addr,
                    value,
                });
            }
        }

        inline fn _lda(self: *Self, target: u16) void {
            self.A = self.read_byte(target);
            self.set_flag(.ZERO, self.A == 0);
            self.set_flag(.NEGATIVE, (self.A & 1 << 7) != 0);
        }

        inline fn _adc(self: *Self, operand: u8) void {
            const sum = self.A + operand + self.get_flag(.CARRY);
            self.set_flag(.CARRY, sum > 0xFF);
            const overflow = ((self.A ^ sum) & (operand ^ sum) & 1 << 7) != 0;
            self.set_flag(.OVERFLOW, overflow);

            self.A = sum;
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

        // Returns cycle count to add
        inline fn _bnc(self: *Self, condition: bool) u8 {
            const offset = self.fetch_byte();

            if (condition) {
                const old_PC = self.PC;
                self.PC = old_PC +% offset;

                const extra: u8 = if (page_crossed(old_PC, self.PC)) 1 else 0;

                return 3 + extra;
            }

            return 2;
        }

        inline fn _cmp(self: *Self, reg_val: u8, operand: u8) void {
            self.set_flag(.CARRY, reg_val >= operand);
            const result = reg_val -% operand;
            self.set_flag(.ZERO, result == 0);
            self.set_flag(.NEGATIVE, (result & (1 << 7)) != 0);
        }
    };
}

inline fn page_crossed(base: u16, final: u16) bool {
    return (base & 0xFF00) != (final & 0xFF00);
}
