$(shell mkdir -p out)

all: msbasic.bin

msbasic.o :
	ca65 -D kb9 asm/msbasic.s -o ./out/msbasic.o
	ca65 mon.s -o ./out/mon.o

msbasic.bin: msbasic.o
	ld65 -C ./kim.cfg ./out/msbasic.o ./out/mon.o -o ./out/msbasic.bin -Ln ./out/msbasic.lbl -m ./out/msbasic.map
