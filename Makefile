
# ----------------------------------------------------------------------
# adjust the following to the location of your Lua include file

INCFLAGS= -I../lua/include

# ----------------------------------------------------------------------

CC= gcc
AR= ar

CFLAGS= -Os -fPIC $(INCFLAGS) 
LDFLAGS= -fPIC

OBJS= l5.o

l5.so:  l5.c
	$(CC) -c $(CFLAGS) l5.c
	$(CC) -shared $(LDFLAGS) -o l5.so $(OBJS)
	strip l5.so

clean:
	rm -f *.o *.a *.so

.PHONY: clean


