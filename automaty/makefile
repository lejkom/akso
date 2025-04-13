CFLAGS = -Wall -Wextra -Wno-implicit-fallthrough -std=gnu17 -fPIC -O2 -g
LINKFLAGS = -shared -Wl,--wrap=malloc -Wl,--wrap=calloc -Wl,--wrap=realloc -Wl,--wrap=reallocarray -Wl,--wrap=free -Wl,--wrap=strdup -Wl,--wrap=strndup

ma.o: ma.c ma.h
	gcc -o ma.o -c ma.c $(CFLAGS)

memory_tests.o: memory_tests.c memory_tests.h
	gcc -o memory_tests.o -c memory_tests.c $(CFLAGS)

libma.so: ma.o memory_tests.o
	gcc -o libma.so ma.o memory_tests.o $(LINKFLAGS)

.PHONY: clean
clean:
	rm -f *.o
	rm -f *.so
