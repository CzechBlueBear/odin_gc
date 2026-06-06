package gc

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:strings"

// A simple interface to the Boehms-Demers-Weiser garbage collector.
//
// For Linux, this is present as the libgc.so library, typically installed using the system package manager
// as the "gc" package.
//
// Please see https://hboehm.info/gc for detailed discussion about the implementation and properties.

foreign import gc "system:gc"

foreign gc {
	GC_init :: proc "c" () ---
	GC_malloc :: proc "c" (block_size: uint) -> rawptr ---
	GC_realloc :: proc "c" (block: rawptr, block_size: uint) -> rawptr ---
	GC_get_heap_size :: proc "c" () -> uint ---
}

//@(init)
//init_gc :: proc "contextless" () {
	// FIXME: if this is uncommented, the garbage collection stops working, not sure why
	// this should not be necessary on Linux, but what about other OSs?
	//gc_init()
//}

@(require_results)
gc_allocator :: proc() -> runtime.Allocator {
	return runtime.Allocator{
		procedure = gc_allocator_proc,
		data = nil,
	}
}

gc_allocator_proc :: proc(
	allocator_data: rawptr, mode: runtime.Allocator_Mode,
    size, alignment: int,
    old_memory: rawptr, old_size: int, loc := #caller_location) -> ([]byte, runtime.Allocator_Error)
{
	switch mode {
		case .Alloc, .Alloc_Non_Zeroed:
			if size < 0 {
				return nil, .Invalid_Argument
			}
			new_block := GC_malloc(uint(size))
			if new_block == nil {
				return nil, .Out_Of_Memory
			}
			return mem.byte_slice(new_block, size), nil

		case .Free:
			return nil, nil

		case .Free_All:
			return nil, .Mode_Not_Implemented

		case .Resize, .Resize_Non_Zeroed:
			if size < 0 {
				return nil, .Invalid_Argument
			}
			new_block := GC_realloc(old_memory, uint(size))
			if new_block == nil {
				return nil, .Out_Of_Memory
			}
			return mem.byte_slice(new_block, size), nil

		case .Query_Features:
			set := (^runtime.Allocator_Mode_Set)(old_memory)
			if set != nil {
				set^ = {.Alloc, .Alloc_Non_Zeroed, .Free, .Resize, .Resize_Non_Zeroed, .Query_Features}
			}
			return nil, nil

		case .Query_Info:
			return nil, .Mode_Not_Implemented
	}
	panic("invalid allocator mode")
}

import "core:testing"

@(test)
test1 :: proc(t: ^testing.T) {

	my_gc := gc_allocator()
	context.allocator = my_gc

	ITERATIONS_CNT :: 10_000_000

	// churn a lot of small allocations; the heap usage should stabilize after a while
	i: int = 0
	for i = 0; i < ITERATIONS_CNT; i += 1 {
		ptr := make([]u8, 16)
		if i % 100_000 == 0 {
			fmt.printf("Heap size = %d\r", GC_get_heap_size());
		}
	}
}
