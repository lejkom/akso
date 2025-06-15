.PHONY: test freverse debug

debug:
	nasm -f elf64 -w+all -w+error -w-unknown-warning -w-reloc-rel -g freverse.asm -o freverse_debug.o
	ld --fatal-warnings -o freverse_debug freverse_debug.o

freverse:
	nasm -f elf64 -w+all -w+error -w-unknown-warning -w-reloc-rel -o freverse.o freverse.asm
	ld --fatal-warnings -o freverse freverse.o


test:
	nasm -f elf64 -w+all -w+error -w-unknown-warning -w-reloc-rel -o test.o test.asm
	ld --fatal-warnings -o test test.o
