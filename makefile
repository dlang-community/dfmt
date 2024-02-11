PREFIX = /usr/local

SRC := $(shell find src -name "*.d") \
	$(shell find libdparse/src -name "*.d") \
	$(shell find stdx-allocator/source -name "*.d")
IMPORTS := -Ilibdparse/src -Istdx-allocator/source -Isrc -Jbin

DC ?= dmd
LDC ?= ldc2
GDC ?= gdc

DMD_COMMON_FLAGS := -w $(IMPORTS)
DMD_DEBUG_FLAGS := -debug -g $(DMD_COMMON_FLAGS)
DMD_FLAGS := -O -inline $(DMD_COMMON_FLAGS)
DMD_TEST_FLAGS := -unittest -g $(DMD_COMMON_FLAGS)
LDC_FLAGS := -g -w -oq $(IMPORTS)
GDC_FLAGS := -g -w -oq $(IMPORTS)
override DMD_FLAGS += $(DFLAGS)
override LDC_FLAGS += $(DFLAGS)
override GDC_FLAGS += $(DFLAGS)

.PHONY: all clean install debug dmd ldc gdc pkg release test

all: bin/dfmt

bin/githash.txt:
	mkdir -p bin
	git describe --tags > bin/githash.txt

dmd: bin/dfmt

ldc: bin/githash.txt
	$(LDC) $(SRC) $(LDC_FLAGS) -ofbin/dfmt
	-rm -f *.o

gdc: bin/githash.txt
	$(GDC) $(SRC) $(GDC_FLAGS) -obin/dfmt

test: debug
	cd tests && ./test.d

bin/dfmt-test: bin/githash.txt $(SRC)
	$(DC) $(DMD_TEST_FLAGS) $^ -of$@

bin/dfmt: bin/githash.txt $(SRC)
	$(DC) $(DMD_FLAGS) $(filter %.d,$^) -of$@

debug: bin/githash.txt $(SRC)
	$(DC) $(DMD_DEBUG_FLAGS) $(filter %.d,$^) -ofbin/dfmt

pkg: dmd
	$(MAKE) -f makd/Makd.mak pkg

clean:
	$(RM) bin/dfmt bin/dfmt-test bin/githash.txt

install:
	chmod +x bin/dfmt
	mkdir -p $(DESTDIR)$(PREFIX)/bin
	cp -f bin/dfmt $(DESTDIR)$(PREFIX)/bin/dfmt

release:
	./release.sh
	$(MAKE) bin/githash.txt
