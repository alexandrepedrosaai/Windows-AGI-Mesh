CC ?= cc
AARCH64_CC ?= aarch64-linux-gnu-gcc
CFLAGS ?= -O3 -Wall -Wextra
TARGET ?= aarch64-linux-gnu

all: majorana_phase_shift_aarch64.o

majorana_phase_shift_aarch64.o: majorana_phase_shift_aarch64.S
	@if [ "$(TARGET)" = "aarch64-linux-gnu" ]; then \
		if ! command -v "$(AARCH64_CC)" >/dev/null 2>&1; then \
			echo "Missing ARM64 cross-compiler: $(AARCH64_CC)" >&2; \
			exit 1; \
		fi; \
		"$(AARCH64_CC)" $(CFLAGS) -c "$<" -o "$@"; \
	else \
		"$(CC)" $(CFLAGS) -c "$<" -o "$@"; \
	fi

clean:
	rm -f majorana_phase_shift_aarch64.o
