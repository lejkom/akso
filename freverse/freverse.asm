global _start	

%macro check_error_close 0
	cmp rax, 0
	jl .exit_error_close	; jeśli wynik < 0, to zamykamy plik i robimy exit(1)
%endmacro



section .rodata
	
	LOG_16		equ 4	; log2(16)
	MOD_16		equ 15	; maska bitowa do mod 16

	; kody poleceń do syscalli
	SYS_OPEN	equ 2	; int open(const char* filename, int flags, mode_t mode)
	SYS_CLOSE	equ 3	; int close(int fd)
	SYS_FSTAT	equ 5	; int fstat(int fd, struct stat* buf)
	SYS_MMAP	equ 9	; void* mmap(void addr, size_t length, int prot,
						;				int flags, int fd, off_t offset)
	SYS_MUNMAP	equ 11	; int munmap(void* addr, size_t len)
	SYS_EXIT	equ 60	; void exit(int status)

	; flagi do poleceń
	O_RDWR		equ 0x2	; do sys_open, pozwala na czytanie i zapisywanie
	PROT_READ	equ 0x1	; do mmap, pozwala na czytanie pliku
	PROT_WRITE	equ 0x2	; do mmap, pozwala na zapisywanie do pliku
	MAP_SHARED	equ 0x1	; do mmap, będzie przenosić zmiany do pliku
	
	ST_SIZE_POS	equ 48	; struct stat ma st_size na offsecie 48 bajtów



section .text

_start:

	; najpierw sprawdzamy, czy mamy dokładnie dwa parametry
	cmp QWORD [rsp], 2	; jeden to program, a drugi to parametr (nazwa pliku)
	jne .exit_error		; jeśli argc != 2, to kończymy z kodem 1
	
	
	; open
	mov rdi, [rsp + 16]		; rdi = filename
	mov rsi, O_RDWR
	xor rdx, rdx
	mov rax, SYS_OPEN
	syscall					; open(filename, O_RDWR, 0)
	cmp rax, 0
	jl .exit_error			; jeśli wynik jest ujemny, to wystąpił błąd
	mov r12, rax			; r12 = fd, file descriptor zwrócony przez open
	
	
	; fstat
	mov rdi, r12			; rdi = fd
	lea rsi, [rsp - 128]	; rsi = rsp - 128 (początek redzone)
	mov rax, SYS_FSTAT
	syscall 				; fstat(fd, rsp - 128)
	check_error_close
	mov r13, [rsp - 128 + ST_SIZE_POS]	; r13 = st_size (rozmiar naszego pliku)
	cmp r13, 2
	jb .exit_success		; jeśli rozmiar pliku < 2, to kończymy bez błędu
	
	
	; mmap
	xor rdi, rdi			; rdi = null	(addr)
	mov rsi, r13			; rsi = st_size	(length)
	mov rdx, PROT_READ | PROT_WRITE	;		(prot)
	mov r10, MAP_SHARED		; 				(flags)
	mov r8, r12				; r8 = fd		(fd)
	xor r9, r9				; r9 = 0 		(offset)
	mov rax, SYS_MMAP
	syscall					; mmap z parametrami ustawionymi powyżej
	check_error_close
	mov rdi, rax				; rdi już trzyma adres do munmap
	mov r14, rax				; r14 to wskaźnik na początek zmapowanej pamięci
	lea r15, [rax + r13 - 8]	; r15 to wskaźnik na ostatnie zmapowane 8 bajtów
	
	; odwracanie
	; będziemy szli dwoma wskaźnikami, r14 i r15, od odpowiednio początku
	; i końca pliku, w każdym powtórzeniu odwracając w sumie 16 bajtów
	mov rcx, r13
	shr rcx, LOG_16			; rcx = st_size / 16, czyli liczba powtórzeń pętli
	test rcx, rcx
	jz .before_byte_by_byte	; sprawdzamy, czy jest co najmniej 16 bajtów w pliku
	
.loop_reversing:
	movbe rax, [r14]		; rax = odwrócone kolejnością bajty z [r14]
	movbe rdx, [r15]		; rdx = odwrócone kolejnością bajty z [r15]
	mov QWORD [r14], rdx	; pod adresem r14 zapisujemy odwrócone bajty z [r15]
	mov QWORD [r15], rax	; pod adresem r15 zapisujemy odwrócone bajty z [r14]
	add r14, 8				; r14 += 8, następne 8 bajtów
	sub r15, 8				; r15 -= 8, poprzednie 8 bajtów
	dec rcx
	test rcx, rcx
	jnz .loop_reversing	; jeśli rcx != 0, to wykonujemy kolejne powtórzenie
	
	; teraz zostało nam potencjalnie parę bajtów, które są bliżej siebie niż 16
	; będziemy je odwracać bajt po bajcie
.before_byte_by_byte:
	mov rcx, r13
	and rcx, MOD_16			; rcx = st_size % 16
	shr rcx, 1				; rcx /= 2, bo w jednej iteracji odwracamy 2 bajty
	add r15, 7				; r15 wskazywał na końcowe 8 bajtów do zamienienia,
							; ale my chcemy iść od ostatniego bajtu, więc +7
	cmp r15, r14
	jb .munmap				; jeśli r15 < r14, to nie ma czego zamieniać
	
.loop_byte_by_byte:
	mov al, [r14]			; al = bajt pod adresem r14
	mov dl, [r15]			; dl = bajt pod adresem r15
	mov BYTE [r14], dl		; pod adresem r14 zapisujemy bajt z r15 
	mov BYTE [r15], al		; pod adresem r15 zapisujemy bajt z r14
	inc r14					; r14++, następny bajt
	dec r15					; r15--, poprzedni bajt
	dec rcx
	test rcx, rcx
	jnz .loop_byte_by_byte	; jeśli rcx != 0, to wykonujemy kolejne powtórzenie
	
	
	; munmap
.munmap:
	; rdi ustawiliśmy już wcześniej, przed odwracaniem
	mov rsi, r13		; rsi = st_size
	mov rax, SYS_MUNMAP
	syscall				; munmap(addr, st_size)
	check_error_close
	
	
	; close i exit
.exit_success:
	mov rdi, r12
	mov rax, SYS_CLOSE
	syscall				; close(fd)
	xor rdi, rdi
	mov rax, SYS_EXIT
	syscall				; exit(0)
	
.exit_error_close:
	mov rdi, r12
	mov rax, SYS_CLOSE
	syscall				; close(fd)
.exit_error:
	mov rdi, 1
	mov rax, SYS_EXIT
	syscall				; exit(1)