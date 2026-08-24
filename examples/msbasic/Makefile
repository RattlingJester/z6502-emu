$(shell mkdir -p out)

all: msbasic.bin

msbasic.o :
	ca65 --listing ./out/msbasic.lst -D applesoft asm/msbasic.s -o ./out/msbasic.o

msbasic.bin: msbasic.o
	ld65 -C apple1.cfg ./out/msbasic.o -o ./out/msbasic.bin -Ln ./out/msbasic.lbl
