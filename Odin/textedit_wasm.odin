#+build js
package main

import "base:runtime"

wasm_arg_0: []u8
wasm_arg_1: []u8

wasm_arg_buffer :: proc(slot, size: int) -> rawptr {
	ensure_initialized()

	byte_count := size
	if byte_count < 1 {
		byte_count = 1
	}

	buffer := &wasm_arg_0
	if slot != 0 {
		buffer = &wasm_arg_1
	}

	if buffer^ != nil && len(buffer^) != byte_count {
		delete(buffer^)
		buffer^ = nil
	}
	if buffer^ == nil {
		buffer^ = make([]u8, byte_count)
	}

	return raw_data(buffer^)
}

@(export)
gmte_wasm_arg_ptr :: proc "c" (slot: i32, size: i32) -> rawptr {
	context = runtime.default_context()
	return wasm_arg_buffer(int(slot), int(size))
}
