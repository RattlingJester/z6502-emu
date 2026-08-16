#include "instructions.h"

#include <cstdint>
#include <cstdio>
#include <cstring>

constexpr size_t MAX_MEM = 1024 * 64;

struct CPU {
	uint16_t PC = 0xFFFC;

	uint8_t A = 0;
	uint8_t X = 0;
	uint8_t Y = 0;

	uint8_t SP = 0xFD;
	uint8_t status = 0b00110100;

	uint8_t memory[MAX_MEM] = {};

	void reset() {
		PC = 0xFFFC;
		A = 0;
		X = 0;
		Y = 0;

		SP = 0xFD;
		status = 0b00110100;
	}

	uint8_t read_mem(uint16_t addr) {
		PC++;
		return memory[addr];
	}

	void update_status() {
		if (A == 0) {
			status |= 1 << 1;
		}

		if (A & 1 << 7) {
			status |= 1 << 7;
		}
	}

	void execute(Instruction instr) {
		switch (instr) {
		case Instruction::LDA_IM: {
			uint8_t op = read_mem(PC);
			A = op;
			update_status();

		} break;

		default: {
			printf("Instruction 0x%02X is not handled\n", instr);
			return;
		} break;
		}
	}

	void cycle() {
		uint8_t instr = read_mem(PC);

		execute((Instruction)instr);
	}
};

int main() {
	CPU cpu = {};

	cpu.memory[cpu.PC] = 0xA9;
	cpu.memory[cpu.PC + 1] = 0x10;

	cpu.cycle();

	// while (true) {
	// 	cpu.cycle();
	// }
}
