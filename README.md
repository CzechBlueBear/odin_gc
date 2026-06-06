# odin_gc
An experiment with Boehm-Demers-Weise's garbage collection in Odin.

## Current status

Single-threaded operation probably works. Use something like

```
my_gc := gc_allocator()
context.allocator = my_gc
```

in your main() before any allocations, and it should, hopefully, do its magic from now on. All other code can be unchanged;
explicit freeing is a safe no-op.

Multithreaded operation possibly works on Linux but probably not anywhere else. The problem is that Boehm's gc need to track threads
to be able to properly track allocations and do the well known and dreaded start/stop thing, and without hooking into thread creation,
something very stupid probably starts to happen.

## Co-operation with other allocations

Boehm's GC can coexist with other malloc methods although it's risky: you must ensure that the GC-supported allocations and other allocations
are completely separate; in no case, a pointer to the GC-allocated heap gets onto the unmanaged heap, and probably not even the other way around;
otherwise everything gets completely mangled together.
