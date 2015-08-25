SRC := $(shell find src -name "*.d") \
	$(shell find libdparse/src -name "*.d") \
	$(shell find libdparse/experimental_allocator/src -name "*.d")
INCLUDE_PATHS := -Ilibdparse/src -Isrc -Ilibdparse/experimental_allocator/src
DMD_COMMON_FLAGS := -dip25 -w $(INCLUDE_PATHS)
DMD_DEBUG_FLAGS := -g -debug $(DMD_COMMON_FLAGS)
DMD_FLAGS := -O -inline $(DMD_COMMON_FLAGS)
DMD_TEST_FLAGS := -unittest -g $(DMD_COMMON_FLAGS)
LDC_FLAGS := -g -w -oq $(INCLUDE_PATHS)
GDC_FLAGS := -g -w -oq $(INCLUDE_PATHS)

.PHONY: dmd ldc gdc test

dmd: bin/dfmt

ldc: $(SRC)
	ldc2 $(LDC_FLAGS) $^ -ofbin/dfmt
	-rm -f *.o

gdc: $(SRC)
	gdc $(GDC_FLAGS) $^ -obin/dfmt

test: bin/dfmt
	cd tests && ./test.sh

bin/dfmt-test: $(SRC)
	dmd $(DMD_TEST_FLAGS) $^ -of$@

bin/dfmt: $(SRC)
	dmd $(DMD_FLAGS) $^ -of$@

debug: $(SRC)
	dmd $(DMD_DEBUG_FLAGS) $^ -ofbin/dfmt
