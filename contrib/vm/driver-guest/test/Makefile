.PHONY = run clean

SRCS := $(wildcard *.c)
OBJS := $(SRCS:%.c=%.o)

LINKERFLAGS = -lm

%.o: %.c
	$(CC) -c $<

%: %.o
	$(CC) $< -o $@

run: test
	./test

clean:
	rm -rvf *.o test test2 
