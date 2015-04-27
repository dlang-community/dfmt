SRC := $(shell find src -name "*.d") $(shell find libdparse/src -name "*.d")
INCLUDE_PATHS := -Ilibdparse/src -Isrc
DMD_COMMON_FLAGS := -dip25 -w $(INCLUDE_PATHS)
DMD_FLAGS := -O -inline $(DMD_COMMON_FLAGS)
DMD_TEST_FLAGS := -unittest -g $(DMD_COMMON_FLAGS)
LDC_FLAGS := -g -w -oq $(INCLUDE_PATHS)

.PHONY: dmd ldc test

dmd: bin/dfmt

ldc: $(SRC)
	ldc2 $(LDC_FLAGS) $(SRC) -ofbin/dfmt
	-rm -f *.o

test:
	dmd $(DMD_TEST_FLAGS) $(SRC) -ofbin/dfmt
	cd tests && ./test.sh

bin/dfmt: $(SRC)
	dmd $(DMD_FLAGS) $(SRC) -ofbin/dfmt
