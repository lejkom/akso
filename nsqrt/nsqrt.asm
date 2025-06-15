global nsqrt


%macro push_registers 0
	push rbx
    push r12
    push r13
    push r14
    push r15
%endmacro	
%macro pop_registers 0
    pop r15
    pop r14
    pop r13
    pop r12
	pop rbx
%endmacro


; void nsqrt(uint64_t *Q, uint64_t *X, unsigned n)
; argumenty:
; rdi - Q
; rsi - X
; rdx - n
nsqrt:

	push_registers
	
	mov rbx, rdx	; dla ułatwienia obliczeń, rbx trzyma n/32
	shr rbx, 5
	
	mov r12, rbx	
	shr r12, 1		; r12 = n/64 - licznik po qwordach w Q
	
.zeruj_Q:
	dec r12
	mov QWORD [rdi + r12 * 8], 0	; Q[r12] = 0
	test r12, r12
	jnz .zeruj_Q	; jeśli r12 > 0, to iterujemy dalej
	
	
	xor r8d, r8d	; r8 - wskazuje, który bit wyniku będziemy liczyć
					; w tej iteracji, r8 będzie przechodzić od 1 do n
	
	
	
.glowna_petla:

	
	inc r8


	; zazwyczaj dodajemy 4^(n-j) do 2^y * Q, mniej liczenia (do napisania)
	; a dla j = n trzeba osobno wyifować
	
	cmp r8, rdx
	ja .koniec	; jeśli j > n, to kończymy
	jb .dodaj_4	; jeśli j < n, to możemy dodać 4^(n-j) do Q
	
	; tutaj j = n, więc po prostu bezpośrednio odejmujemy 1 od X
	; teraz 4^(n-j) = 1, 2^(n-j+1) = 2
	mov r12, rbx	; r12 = n/32, r12 określa, do jakiej wartości się iterujemy
	
	xor r11d, r11d	; r11 = 0, to będzie licznik pętli
	
	stc		; będziemy robić sbb, więc ustawienie cf jest równoważne odjęciu 1
	lahf
	
.petla_odejmij_1:
	
	sahf
	sbb QWORD [rsi + r11 * 8], 0	; X[r11] -= cf
	jnc .przed_petla_porownaj_Q		; jeśli cf == 0, to możemy skończyć
	lahf
	inc r11	
	cmp r11, r12		
	jb .petla_odejmij_1	; jeśli r11 < r12, to idziemy dalej
	
	; przeszliśmy całą pętlę i ciągle mamy cf = 1, więc cały X musiał być = 0,
	; więc nie możemy odjąć, czyli od razu ustawiamy q_j na 0 i kończymy
	btr QWORD [rdi], 0
	jmp .koniec
	

	; dodajemy 4^(n-j) do Q, żeby uprościć obliczenia, czyli ustawiamy
	; bit n-j-1 na 1, bo będziemy potem symulować przesunięcie Q o n-j+1
.dodaj_4:

	; r9 będzie trzymać przesunięcie w obrębie qworda, a r10 liczbę qwordów
	lea r9, [rdx - 1]			; r9 = n - 1
	sub r9, r8					; r9 = n - j - 1
	mov r10, r9					; r10 = n - j - 1
	and r9, 63					; r9 %= 64
	shr r10, 6					; r10 /= 64
	bts QWORD [rdi + r10 * 8], r9 ; ustawia bit w Q na 1


	
.przed_petla_porownaj_Q:	

	; teraz sprawdzamy, czy da się odjąć 2^(n-j+1) * Q_(j-1) + 4^(n - j) od X

	lea rcx, [rdx + 1]			; rcx = n + 1
	sub rcx, r8					; rcx = n - j + 1
	mov r10, rcx 				; r10 = n - j + 1
	lea r11, [r10 + rdx - 1]	; r11 = 2n - j
	and rcx, 63					; rcx %= 64
	shr r10, 6					; r10 /= 64
	shr r11, 6					; r11 /= 64
	
	; rcx określa, o ile w obrębie qworda jest przesunięte całe Q
	; r10 określa, od którego qworda X zaczyna się przesunięte Q
	; r11 okresla, na którym qwordzie X kończy się przesunięte Q
	
	
	; r14 będzie licznikiem pętli sprawdzającej, czy możemy odjąć przesunięte Q
	; i będzie przechodzić od najstarszych qwordów X
	mov r14, rbx		; r14 = n/32
	
	
	; r15 idzie po qwordach z nieprzesuniętego Q, żeby wiedzieć, do którego
	; qworda w nieprzesuniętym Q się odwołać, żeby zasymulować przesunięcie
	mov r15, rbx		; r15 = n/32
	shr r15, 1			; r15 /= 2
	dec r15
	

	; plan jest taki, że sprawdzamy po kolei od najstarszych qwordów,
	; czy da się odjąć odpowiedni qword z 2^(n-j+1) * Q_(j-1) + 4^(n - j)
	; r14 mówi, którego qworda z X obecnie porównujemy i do tego będziemy sobie
	; w rax trzymać fragment przesuniętego Q odpowiadający obecnemu qwordowi X
	
	
.petla_porownaj_Q:
	
	dec r14
	
	cmp r14, r11		; jeśli jesteśmy na starszych bitach niż przesunięte Q
	ja .czy_nie_zero_X	; to sprawdzamy, czy w tym qwordzie jest wartość > 0
	je .poczatek_Q		; jeśli są równe, to dołożymy na początek Q zera
	
	cmp r14, r10		; jeśli jesteśmy na młodszych bitach, to na pewno można
	jb .ustaw_jeden		; będzie odjąć, bo to znaczy, że wszystkie starsze są =
	je .koniec_Q		; jeśli są równe, to dołożymy na koniec Q zera
	
	; tutaj jestesmy w środku Q, r15 wskazuje na starszego qworda w Q
	; chcemy ustawić w rax odpowiadający X[r14] qword z przesuniętego Q
	mov rax, [rdi + r15 * 8]	; rax = Q[r15]
	dec r15
	mov r12, [rdi + r15 * 8]	; r12 = Q[r15]
	shld rax, r12, cl			; rax zostaje przesunięte o cl bitów w lewo,
								; a od prawej wstawiamy cl najstarszych bitów
.porownaj_Q:

	cmp QWORD [rsi + r14 * 8], rax	; porównujemy X[r14] z przesuniętym Q
	ja .ustaw_jeden					; jeśli X[r14] większe, to można odjąć
	jb .ustaw_zero					; jeśli X[r14] mniejsze, to nie można odjąć
	jmp .petla_porownaj_Q			; jeśli równe, to sprawdzamy dalej
	
	
.poczatek_Q:
	mov rax, [rdi + r15 * 8]	; rax = Q[r15] (najstarszy qword)
	test cl, cl
	jnz .bez_zmniejszania
	dec r15
.bez_zmniejszania:
	not cl		; cl = 63 - cl
	inc cl		; cl = 64 - cl
	shr rax, cl
	dec cl		; cl = 63 - cl
	not cl		; przywrócenie oryginalnej wartości
	jmp .porownaj_Q
	
.koniec_Q:
	mov rax, [rdi + r15 * 8]		; rax = Q[r15] (najmłodszy qword)
	shl rax, cl
	cmp QWORD [rsi + r14 * 8], rax	; porównujemy X[r14] z przesuniętym Q
	jae .ustaw_jeden				; jeśli X[r14] >=, to możemy odjąć
	jb .ustaw_zero					; jeśli X[r14] <, to nie możemy odjąć
	
	
	
	; jeśli w X[r14] jest dodatnia wartość, to możemy odjąć przesunięte Q
.czy_nie_zero_X:

	cmp QWORD [rsi + r14 * 8], 0	; jeśli X[r14] == 0, 
	jz .petla_porownaj_Q			; to ciągle nie wiemy, czy można odjąć
	; niezerowa wartość, czyli idziemy do ustaw_jeden. bo da się odjąć



	; odejmujemy przesunięte Q od X i ustawiamy bit wyniku na 1
	; idziemy od najmłodszych bajtów Q, odejmując po kolei słowa
.ustaw_jeden:
	
	cmp r8, rdx
	jb .przed_petla_jeden	; jeśli j < n, to odejmujemy normalnie
	; jeśli j = n, to po prostu ustawiamy q_n na 1 i koniec
	bts QWORD [rdi], 0
	jmp .koniec
	
	
.przed_petla_jeden:
	
	; korzystamy z wcześniej wyliczonych wartości rcx, r10, r11
	
	; r12 wskazuje, na którym qwordzie X jesteśmy i idzie od 0 do r13 - 1
	xor r12d, r12d		; r12 = 0
	mov r13, rbx
	;shr r13, 5			; r13 = n/32
	
	; r14 wskazuje, na którym qwordzie Q jesteśmy i idzie od 0
	xor r14d, r14d		; r14 = 0
	
	clc
	lahf
	
.petla_jeden:
	
	cmp r12, r10		; jeśli jesteśmy przed Q, to idziemy do kolejnego powt.
	jb .kolejne_powt
	je .najmlodsze_Q
	cmp r12, r11		; jeśli jesteśmy za Q, to chcemy kończyć pętlę
	ja .koncowka_X
	je .najstarsze_Q

	; tak jak przy porównywaniu, chcemy odjąć od X odpowiednie qwordy z Q
	mov r9, [rdi + r14 * 8 - 8]		; r9 = Q[r14 - 1]
	mov r15, [rdi + r14 * 8]		; r15 = Q[r14]
	shld r15, r9, cl		; r15 zostaje przesunięte o cl bitów w lewo,
							; a od prawej wstawiamy cl najstarszych bitów z r9
	
	
.odejmij_Q:	
	sahf
	sbb [rsi + r12 * 8], r15	; odejmujemy od X[r12] przesunięte Q
	lahf
	inc r14
	jmp .kolejne_powt			; i kontynuujemy


.najmlodsze_Q:
	mov r15, [rdi + r14 * 8]	; r15 = Q[r14]
	shl r15, cl		; r15 << cl, żeby wyrównać do X
	jmp .odejmij_Q

.najstarsze_Q:
	test rcx, rcx		; jeśli rcx = 0, to nie możemy zmniejszać r14, bo wtedy
	jz .bez_obnizania	; dwa razy odejmiemy drugiego najstarszego qworda
	dec r14
.bez_obnizania:
	mov r15, [rdi + r14 * 8]	; r15 = Q[r14]
	not cl		; cl = 63 - cl
	inc cl		; cl = 64 - cl
	shr r15, cl
	dec cl		; cl = 63 - cl
	not cl		; przywrócenie oryginalnej wartości
	jmp .odejmij_Q
	
	
.koncowka_X:

	test ah, 1				; sprawdza bit 0 z ah, czyli bit carry
	jz .koniec_ustaw_jeden	; jeśli mamy cf = 0, to już ustawiamy q_j na 1
	
	; jeśli cf = 1, to znaczy, że jeszcze mamy jakieś carry
	; z poprzedniego qworda do odjęcia
	sahf
	sbb QWORD [rsi + r12 * 8], 0	; odejmujemy carry i idziemy dalej
	lahf
	; idziemy do kolejnego powtórzenia


.kolejne_powt:
	inc r12
	cmp r12, r13	
	jb .petla_jeden
	; jeśli r12 = r13, to kończymy pętlę



.koniec_ustaw_jeden:
	
	mov cl, 1	; w cl trzymamy, czy obecnie ustawiamy 1, czy 0, zeby wiedzieć,
				; dokąd wrócić po ustawieniu r9 i r10
.ustaw_r9_r10:
	lea r9, [rdx - 1]			; r9 = n - 1
	sub r9, r8					; r9 = n - j - 1
	mov r10, r9					; r10 = n - j - 1
	and r9, 63					; r9 %= 64
	shr r10, 6					; r10 /= 64
	test cl, cl
	jz .wroc_do_zera
	
	btr QWORD [rdi + r10 * 8], r9 ; ustawia 2(n-j)-ty bit w przesuniętym Q na 0
	
	cmp r9, 63
	jb .bez_dodawania	; jeśli r9 < 63, to dodanie 1 nic nie zmieni
	inc r10				; jeśli r9 = 63, to dodanie 1 zwiększa r10 o 1
.bez_dodawania:
	inc r9
	and r9, 63

	; teraz r9 = (n - j) % 64, r10 = (n - j) / 64

	bts QWORD [rdi + r10 * 8], r9 ; ustawia (n-j)-ty bit w Q na 1
	
	jmp .glowna_petla
	


	; ustawiamy bit wyniku na 0 i odejmujemy 4^(n-j) od Q
.ustaw_zero:
	
	cmp r8, rdx		; jeśli j = n, to już nie resetujemy bitu w Q
	jae .koniec		; po dodaniu 4^(n-j), więc po prostu kończymy
	
	mov cl, 0			; ustawia cl na 0, żeby pamiętać, że ustawiamy 0
	jmp .ustaw_r9_r10	; przy ustaw_r9_r10

.wroc_do_zera:
	btr QWORD [rdi + r10 * 8], r9 ; ustawia 2(n-j)-ty bit w przesuniętym Q na 0
	
	jmp .glowna_petla
	

.koniec:

	pop_registers
	ret