
# ----------------------------------------------------------------------
# adjust the following to the location of your Lua directory
# or include files and executable

LUADIR= ../lua
LUAINC= -I$(LUADIR)/include
LUAEXE= $(LUADIR)/bin/lua


# ----------------------------------------------------------------------

CC= gcc
AR= ar

CFLAGS= -Os -fPIC $(LUAINC) 
LDFLAGS= -fPIC

OBJS= l5.o

l5.so:  l5.c
	$(CC) -c $(CFLAGS) l5.c
	$(CC) -shared $(LDFLAGS) -o l5.so $(OBJS)
	strip l5.so

test: l5.so
	$(LUAEXE) ./test.lua

clean:
	rm -f *.o *.a *.so

.PHONY: clean test


