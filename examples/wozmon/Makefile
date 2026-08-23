$(shell mkdir -p out)

all: wozmon.bin

wozmon.o :
	ca65 --listing ./out/wozmon.lst  wozmon.s -o ./out/wozmon.o

wozmon.bin: wozmon.o
	cl65 -C apple1.cfg ./out/wozmon.o -o ./out/wozmon.bin
