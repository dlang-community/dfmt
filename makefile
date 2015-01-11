SRC := $(shell find src -name "*.d") $(shell find libdparse/src -name "*.d")
COMPILER := dmd
INCLUDE_PATHS := -Ilibdparse/src
FLAGS := -g -w $(INCLUDE_PATHS)

all: $(SRC)
	$(COMPILER) $(FLAGS) $(SRC) -ofbin/dfmt

