#+feature dynamic-literals
package gc

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:sync"

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

gc_allocator_lock: sync.Mutex

@(require_results)
gc_allocator :: proc() -> runtime.Allocator {
	return runtime.Allocator {
		procedure = gc_allocator_proc,
		data = nil,
	}
}

@(no_sanitize_address)
gc_allocator_proc :: proc(
	allocator_data: rawptr, mode: runtime.Allocator_Mode,
    size, alignment: int,
    old_memory: rawptr, old_size: int, loc := #caller_location) -> ([]byte, runtime.Allocator_Error)
{
	// FIXME: this is a dangerous hack that works only by a lucky chance!
	// When GC is called for the first time, the GC code detects it is not
	// properly initialized, and calls GC_Init() to salvage the situation.
	// But if another thread attempts to do an allocation at the same moment,
	// before GC_Init() returns, the whole app crashes.
	// This lock prevents this, but also slows down all concurrent allocations.
	// The proper solution would be to call GC_Init() exactly once, at the start,
	// but I don't know how. Tried to put it into @init section, does not work.
	// -- bluebear
	sync.mutex_lock(&gc_allocator_lock)
	defer sync.mutex_unlock(&gc_allocator_lock)

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
	return nil, nil
}

// tests --------------------------------------------------------------------

import "core:testing"

@(test)
test_churn_small_blocks :: proc(t: ^testing.T) {

	my_gc := gc_allocator()
	context.allocator = my_gc

	ITERATIONS_CNT :: 10_000_000

	// churn a lot of small allocations; the heap usage should stabilize after a while
	i: int = 0
	for i = 0; i < ITERATIONS_CNT; i += 1 {
		ptr := make([]u8, 16)
		if i % 100_000 == 0 {
			fmt.printf("Heap size = %d\n", GC_get_heap_size());
		}
	}
}

@(test)
test_dynamic_array :: proc(t: ^testing.T) {

	my_gc := gc_allocator()
	context.allocator = my_gc

	some_dynamic_array := [dynamic]int{1, 4, 9}
	defer delete(some_dynamic_array)

	testing.expect(t, len(some_dynamic_array) == 3)
	testing.expect(t, some_dynamic_array[0] == 1)

	for value in some_dynamic_array {
		fmt.println(value)
	}
}

@(test)
test_dynamic_map :: proc(t: ^testing.T) {

	my_gc := gc_allocator()
	context.allocator = my_gc

	some_map := map[string]int{"A" = 1, "C" = 9, "B" = 4}
	defer delete(some_map)

	for key in some_map {
		fmt.println(key)
	}
}
