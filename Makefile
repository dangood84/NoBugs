# Free Pascal only. Lazarus is not part of this build.
FPC ?= fpc
CC ?= clang
UNAME := $(shell uname)

FPCFLAGS := -Mobjfpc -Sh -O2 -gl -Fusrc -FUlib -FEbin

.PHONY: all test preview app run clean

all: bin/nobugs

ifeq ($(UNAME),Darwin)
lib/launch.o: src/launch.c
	mkdir -p lib
	$(CC) -c -mmacosx-version-min=11.0 src/launch.c -o lib/launch.o

bin/nobugs: lib/launch.o src/*.pas
	mkdir -p bin lib
	$(FPC) $(FPCFLAGS) src/nobugs.pas
else
bin/nobugs: src/*.pas
	mkdir -p bin lib
	$(FPC) $(FPCFLAGS) src/nobugs.pas
endif

test: bin/nobugs
	./bin/nobugs --self-test

preview: bin/nobugs
	./bin/nobugs --preview bin/preview.bmp

app: bin/nobugs resources/Info.plist
	mkdir -p "No Bugs.app/Contents/MacOS" "No Bugs.app/Contents/Resources"
	cp bin/nobugs "No Bugs.app/Contents/MacOS/nobugs"
	cp resources/Info.plist "No Bugs.app/Contents/Info.plist"
	printf 'APPL????' > "No Bugs.app/Contents/PkgInfo"

run: bin/nobugs
	./bin/nobugs

clean:
	rm -rf bin lib *.o *.ppu "No Bugs.app"
