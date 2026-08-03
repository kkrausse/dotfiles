/* gw-focus.m --- give an Emacs NS xwidget the keyboard  -*- objc -*-

Copyright (C) 2026 Kevin Krausse
SPDX-License-Identifier: GPL-3.0-or-later

Emacs's NS port has no way to hand an xwidget the keyboard, and it is not a
gap that can be closed from Lisp or JavaScript.  Checked against Emacs 30.2:

  - src/nsxwidget.h exports 18 nsxwidget_* functions and none of them touch
    responders.
  - src/nsxwidget.m contains exactly two `makeFirstResponder:' calls and both
    hand focus TO Emacs: the isearch branch of -keyDown:, and the "C-g" branch
    of -userContentController:didReceiveScriptMessage:.
  - `xwidget-perform-lispy-event' has its whole body inside `#ifdef USE_GTK',
    so on a --with-ns build it is a no-op and `xwidget-webkit-edit-mode' does
    nothing at all.

The only thing that gives a WKWebView first responder is WKWebView's own
-mouseDown:.  Which is why clicking works and no command can.

So make the one call the port never makes.  A dynamic module runs in Emacs's
own process on Emacs's main thread, so it can talk to AppKit directly: find
Emacs's XwWebView instances in the view hierarchy and ask the window to make
one first responder.  No synthesized events, no Accessibility, no private
API.  This lands in exactly the state a mouse click lands in -- a state the
existing C code already knows how to leave, since the page can post "C-g" to
hand first responder back.

Keys reach the terminal only when BOTH the XwWebView is first responder AND
the page's `document.activeElement' is an INPUT or TEXTAREA (that is what
nsxwidget.m's injected `xwHasFocus()' tests before calling `[super
keyDown:]').  This module does the first half; `window.gw.focus()' in the page
does the second.

Build:  make      (or see `ghostty-web-term-build-focus-module')  */

#include <string.h>
#include <stdlib.h>
#include <emacs-module.h>
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

int plugin_is_GPL_compatible;

/* Collect every instance of CLS under VIEW into OUT.  */
static void
gw_collect (NSView *view, Class cls, NSMutableArray *out)
{
  if (view == nil)
    return;
  if ([view isKindOfClass:cls])
    [out addObject:view];
  for (NSView *sub in view.subviews)
    gw_collect (sub, cls, out);
}

/* Every xwidget web view Emacs currently has on screen.

   XwWebView is Emacs's own class; _OBJC_CLASS_$_XwWebView is an exported
   symbol in the binary, so the runtime resolves it in process.  If a build
   ever stops having it, this returns nothing and every entry point below
   fails soft rather than crashing Emacs.  */
static NSArray *
gw_webviews (void)
{
  NSMutableArray *out = [NSMutableArray array];
  Class cls = NSClassFromString (@"XwWebView");
  if (cls == nil)
    return out;
  for (NSWindow *win in [NSApp windows])
    gw_collect (win.contentView, cls, out);
  return out;
}

static emacs_value
gw_intern (emacs_env *env, const char *name)
{
  return env->intern (env, name);
}

static emacs_value
gw_string (emacs_env *env, NSString *s)
{
  const char *utf8 = s ? [s UTF8String] : "";
  return env->make_string (env, utf8, (ptrdiff_t) strlen (utf8));
}

/* Read a Lisp string argument into a malloc'd C string, or NULL for nil.  */
static char *
gw_arg_string (emacs_env *env, emacs_value v)
{
  if (!env->is_not_nil (env, v))
    return NULL;
  ptrdiff_t len = 0;
  if (!env->copy_string_contents (env, v, NULL, &len))
    return NULL;
  char *buf = malloc ((size_t) len);
  if (buf == NULL)
    return NULL;
  if (!env->copy_string_contents (env, v, buf, &len))
    {
      free (buf);
      return NULL;
    }
  return buf;
}

/* (gw-focus-count) => number of xwidget web views on screen.  */
static emacs_value
Fgw_count (emacs_env *env, ptrdiff_t nargs, emacs_value *args, void *data)
{
  return env->make_integer (env, (intmax_t) [gw_webviews () count]);
}

/* (gw-focus-state) => a string describing each web view and who holds the
   keyboard.  Deliberately excludes URLs: those carry the PTY server's session
   token, and this string is meant to be safe to print in the echo area or a
   bug report.  */
static emacs_value
Fgw_state (emacs_env *env, ptrdiff_t nargs, emacs_value *args, void *data)
{
  NSMutableString *s = [NSMutableString string];
  NSArray *views = gw_webviews ();
  [s appendFormat:@"webviews=%lu", (unsigned long) views.count];
  NSInteger i = 0;
  for (NSView *v in views)
    {
      NSWindow *win = v.window;
      BOOL isFR = (win != nil && win.firstResponder == v);
      [s appendFormat:@" [%ld responder=%@ window=%@]",
	 (long) i++,
	 isFR ? @"self" : NSStringFromClass ([win.firstResponder class]),
	 win == nil ? @"none" : (win.isKeyWindow ? @"key" : @"other")];
    }
  NSWindow *key = [NSApp keyWindow];
  [s appendFormat:@" key-window-responder=%@",
     key ? NSStringFromClass ([key.firstResponder class]) : @"no-key-window"];
  return gw_string (env, s);
}

/* (gw-focus-take &optional MATCH) => t when a web view took the keyboard.

   MATCH is a substring of the page's URL, which is how one terminal is told
   from another: each carries its own port and client id.  With MATCH nil this
   acts only when there is exactly one web view, so it can never grab the
   keyboard for a page the caller did not mean.  */
static emacs_value
Fgw_take (emacs_env *env, ptrdiff_t nargs, emacs_value *args, void *data)
{
  char *match = (nargs > 0) ? gw_arg_string (env, args[0]) : NULL;
  NSArray *views = gw_webviews ();
  NSView *target = nil;

  if (match == NULL)
    {
      if (views.count == 1)
	target = views[0];
    }
  else
    {
      NSString *needle = [NSString stringWithUTF8String:match];
      for (NSView *v in views)
	{
	  NSString *url = [[(WKWebView *) v URL] absoluteString];
	  if (url != nil && needle != nil
	      && [url rangeOfString:needle].location != NSNotFound)
	    {
	      target = v;
	      break;
	    }
	}
    }
  free (match);

  if (target == nil || target.window == nil)
    return gw_intern (env, "nil");

  /* The one call the NS port never makes.  Same transition -mouseDown: causes.  */
  BOOL ok = [target.window makeFirstResponder:target];
  return gw_intern (env, ok ? "t" : "nil");
}

/* (gw-focus-release) => hand the keyboard back to Emacs.

   The page can do this itself by posting "C-g" to nsxwidget.m's script message
   handler, but only while it still has the keyboard.  This works from Emacs's
   side either way.

   The window comes from a web view that currently holds first responder rather
   than from `keyWindow': keyWindow is nil whenever Emacs is not the active
   application, and the responder state is worth fixing even then.  */
static emacs_value
Fgw_release (emacs_env *env, ptrdiff_t nargs, emacs_value *args, void *data)
{
  NSWindow *win = nil;
  for (NSView *v in gw_webviews ())
    if (v.window != nil && v.window.firstResponder == v)
      {
	win = v.window;
	break;
      }
  if (win == nil)
    win = [NSApp keyWindow];
  if (win == nil)
    return gw_intern (env, "nil");

  /* Target the EmacsView, the way nsxwidget.m's own C-g branch does
     (`makeFirstResponder:self.xw->xv->emacswindow').  Handing first responder
     to the window's content view instead is NOT equivalent: that is a plain
     NSView with no -keyDown: of its own, so keystrokes would land on a
     responder that ignores them and the keyboard would belong to neither Emacs
     nor the page.  Measured, not theorized.  */
  Class emacsView = NSClassFromString (@"EmacsView");
  NSMutableArray *found = [NSMutableArray array];
  if (emacsView != nil)
    gw_collect (win.contentView, emacsView, found);
  if (found.count == 0)
    return gw_intern (env, "nil");

  BOOL ok = [win makeFirstResponder:found[0]];
  return gw_intern (env, ok ? "t" : "nil");
}

static void
gw_defun (emacs_env *env, const char *name, ptrdiff_t min, ptrdiff_t max,
	  emacs_value (*fn) (emacs_env *, ptrdiff_t, emacs_value *, void *),
	  const char *doc)
{
  emacs_value func = env->make_function (env, min, max, fn, doc, NULL);
  emacs_value args[2] = { gw_intern (env, name), func };
  env->funcall (env, gw_intern (env, "fset"), 2, args);
}

int
emacs_module_init (struct emacs_runtime *rt)
{
  if ((size_t) rt->size < sizeof (*rt))
    return 1;                   /* Emacs is older than this module.  */
  emacs_env *env = rt->get_environment (rt);
  if ((size_t) env->size < sizeof (*env))
    return 2;

  gw_defun (env, "gw-focus-count", 0, 0, Fgw_count,
	    "Return the number of xwidget web views currently on screen.\n"
	    "\n(fn)");
  gw_defun (env, "gw-focus-state", 0, 0, Fgw_state,
	    "Describe each xwidget web view and which view holds the keyboard.\n"
	    "Never includes page URLs: those carry the PTY session token.\n"
	    "\n(fn)");
  gw_defun (env, "gw-focus-take", 0, 1, Fgw_take,
	    "Give the keyboard to the xwidget web view whose URL contains MATCH.\n"
	    "With MATCH nil, act only when exactly one web view exists.\n"
	    "Return non-nil when the transfer happened.\n"
	    "\n(fn &optional MATCH)");
  gw_defun (env, "gw-focus-release", 0, 0, Fgw_release,
	    "Give the keyboard back to Emacs's own view.\n"
	    "\n(fn)");

  emacs_value feature = gw_intern (env, "gw-focus");
  env->funcall (env, gw_intern (env, "provide"), 1, &feature);
  return 0;
}
