SRC := $(shell find src -name "*.d") \
	$(shell find libdparse/src -name "*.d") \
	$(shell find libdparse/experimental_allocator/src -name "*.d")
INCLUDE_PATHS := -Ilibdparse/src -Isrc -Ilibdparse/experimental_allocator/src
DMD_COMMON_FLAGS := -dip25 -w $(INCLUDE_PATHS)
DMD_DEBUG_FLAGS := -g $(DMD_COMMON_FLAGS)
DMD_FLAGS := -O -inline $(DMD_COMMON_FLAGS)
DMD_TEST_FLAGS := -unittest -g $(DMD_COMMON_FLAGS)
LDC_FLAGS := -g -w -oq $(INCLUDE_PATHS)
GDC_FLAGS := -g -w -oq $(INCLUDE_PATHS)
DC ?= dmd
LDC ?= ldc2
GDC ?= gdc

.PHONY: dmd ldc gdc test

dmd: bin/dfmt

ldc: $(SRC)
	$(LDC) $(LDC_FLAGS) $^ -ofbin/dfmt
	-rm -f *.o

gdc: $(SRC)
	$(GDC) $(GDC_FLAGS) $^ -obin/dfmt

test: bin/dfmt
	cd tests && ./test.sh

bin/dfmt-test: $(SRC)
	$(DC) $(DMD_TEST_FLAGS) $^ -of$@

bin/dfmt: $(SRC)
	$(DC) $(DMD_FLAGS) $^ -of$@

debug: $(SRC)
	$(DC) $(DMD_DEBUG_FLAGS) $^ -ofbin/dfmt
