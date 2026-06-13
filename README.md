# odin_gc

An experiment with Boehm-Demers-Weiser's garbage collection in Odin.
Please note this is *not* production-ready code; current state is "sometimes works".

## The garbage collector

On Linux, it is usually directly available or installable via systems' package manager under name "gc" or similar.
The appropriate library is ``/usr/lib/libgc.so``.

On Windows, you will probably need to install it yourself; no idea how's it on the Mac (Homebrew, possibly?)

Sources of the GC are at https://github.com/bdwgc.

## Current status

Single-threaded operation probably works. Use something like

```
my_gc := gc_allocator()
context.allocator = my_gc
```

in your main() before any allocations, and it should, hopefully, do its magic from now on. All other code can be unchanged;
explicit freeing is a safe no-op.

Multithreaded operation currently does not work, at least not reliably. The problem is that Boehm's gc need to track threads
to be able to properly track allocations and do the well known and dreaded start/stop thing, and without hooking into thread creation,
something very stupid probably starts to happen.

## Co-operation with other allocations

Boehm's GC can coexist with other malloc methods although it's risky: you must ensure that the GC-supported allocations and other allocations
are completely separate; in no case, a pointer to the GC-allocated heap gets onto the unmanaged heap, and probably not even the other way around;
otherwise everything gets completely mangled together.

# Plan

## Multithreading

To make multithreaded operation work, the GC must know about all threads created and destroyed (with exception of library ones that do strictly their own allocations) and must stop them when it rearranges the application's memory. So far, my only idea is to make a clone of the core:thread package that calls GC-aware versions of the thread primitives (on Linux, it's GC_pthread_create() instead of pthread_create(), etc.) This should work but it's clumsy. We'll see if there is another possibility.
