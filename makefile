SRC := $(shell find src -name "*.d") \
	$(shell find libdparse/src -name "*.d") \
	$(shell find stdx-allocator/source -name "*.d")
INCLUDE_PATHS := -Ilibdparse/src -Istdx-allocator/source -Isrc -Jbin
DMD_COMMON_FLAGS := -dip25 -w $(INCLUDE_PATHS)
DMD_DEBUG_FLAGS := -debug -g $(DMD_COMMON_FLAGS)
DMD_FLAGS := -O -inline $(DMD_COMMON_FLAGS)
DMD_TEST_FLAGS := -unittest -g $(DMD_COMMON_FLAGS)
LDC_FLAGS := -g -w -oq $(INCLUDE_PATHS)
GDC_FLAGS := -g -w -oq $(INCLUDE_PATHS)
override DMD_FLAGS += $(DFLAGS)
override LDC_FLAGS += $(DFLAGS)
override GDC_FLAGS += $(DFLAGS)
DC ?= dmd
LDC ?= ldc2
GDC ?= gdc

.PHONY: dmd ldc gdc test

dmd: bin/dfmt

githash:
	mkdir -p bin
	git describe --tags > bin/githash.txt

ldc: githash
	$(LDC) $(SRC) $(LDC_FLAGS) -ofbin/dfmt
	-rm -f *.o

gdc:githash
	$(GDC) $(SRC) $(GDC_FLAGS) -obin/dfmt

test: debug
	cd tests && ./test.d

bin/dfmt-test: githash $(SRC)
	$(DC) $(DMD_TEST_FLAGS) $^ -of$@

bin/dfmt: githash $(SRC)
	$(DC) $(DMD_FLAGS) $(filter %.d,$^) -of$@

debug: githash $(SRC)
	$(DC) $(DMD_DEBUG_FLAGS) $(filter %.d,$^) -ofbin/dfmt

pkg: dmd
	$(MAKE) -f makd/Makd.mak pkg

clean:
	$(RM) bin/dfmt

release:
	./release.sh
	githash
