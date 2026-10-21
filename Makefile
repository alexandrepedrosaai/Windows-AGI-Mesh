CC ?= clang
CFLAGS ?= -O3 -Wall -Wextra
TARGET ?= aarch64-linux-gnu

all: majorana_phase_shift_aarch64.o

majorana_phase_shift_aarch64.o: majorana_phase_shift_aarch64.S
	$(CC) --target=$(TARGET) $(CFLAGS) -c $< -o $@

clean:
	rm -f majorana_phase_shift_aarch64.o
