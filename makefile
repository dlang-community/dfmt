SRC := $(shell find src -name "*.d") \
	$(shell find libdparse/src -name "*.d")
INCLUDE_PATHS := -Ilibdparse/src -Isrc
DMD_COMMON_FLAGS := -dip25 -w $(INCLUDE_PATHS) -Jviews
DMD_DEBUG_FLAGS := -debug -g $(DMD_COMMON_FLAGS)
DMD_FLAGS := -O -inline $(DMD_COMMON_FLAGS)
DMD_TEST_FLAGS := -unittest -g $(DMD_COMMON_FLAGS)
LDC_FLAGS := -g -w -oq $(INCLUDE_PATHS)
GDC_FLAGS := -g -w -oq $(INCLUDE_PATHS)
DC ?= dmd
LDC ?= ldc2
GDC ?= gdc

.PHONY: dmd ldc gdc test

dmd: bin/dfmt

views/VERSION : .git/refs/tags .git/HEAD
	mkdir -p $(dir $@)
	git describe --tags > $@

ldc: $(SRC)
	$(LDC) $(LDC_FLAGS) $^ -ofbin/dfmt
	-rm -f *.o

gdc: $(SRC)
	$(GDC) $(GDC_FLAGS) $^ -obin/dfmt

test: debug
	cd tests && ./test.sh

bin/dfmt-test: $(SRC)
	$(DC) $(DMD_TEST_FLAGS) $^ -of$@

bin/dfmt: views/VERSION $(SRC)
	$(DC) $(DMD_FLAGS) $(filter %.d,$^) -of$@

debug: views/VERSION $(SRC)
	$(DC) $(DMD_DEBUG_FLAGS) $(filter %.d,$^) -ofbin/dfmt

