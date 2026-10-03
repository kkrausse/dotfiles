# Builds gw-focus.dylib -- the AppKit call Emacs's NS xwidget port is missing.
#
# `ghostty-web-term-build-focus-module' runs the same compiler invocation from
# Emacs, so this file is for building by hand.
#
# EMACS_INCLUDE must hold emacs-module.h.  The default asks Emacs itself, which
# is right for any prefix (Homebrew, /usr/local, a self-built tree).

EMACS ?= emacs
EMACS_INCLUDE ?= $(shell $(EMACS) -Q --batch --eval \
  '(princ (expand-file-name "include" (expand-file-name "../../../.." data-directory)))')

CC      ?= clang
CFLAGS  ?= -bundle -fobjc-arc -O2 -Wall
LDFLAGS ?= -framework AppKit -framework WebKit

all: gw-focus.dylib

gw-focus.dylib: gw-focus.m
	@test -f "$(EMACS_INCLUDE)/emacs-module.h" \
	  || { echo "emacs-module.h not found in $(EMACS_INCLUDE); set EMACS_INCLUDE=..." >&2; exit 1; }
	$(CC) $(CFLAGS) -I "$(EMACS_INCLUDE)" $(LDFLAGS) -o $@ $<

clean:
	rm -f gw-focus.dylib

.PHONY: all clean
