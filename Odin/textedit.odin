package main

import "base:runtime"
import "core:strings"
import textedit "core:text/edit"

Status :: enum i32 {
	OK,
	Invalid_Id,
	Editor_Not_Found,
	Invalid_Command,
}

Editor :: struct {
	key:     string,
	builder: strings.Builder,
	state:   textedit.State,
}

editors: map[string]^Editor
return_buffer: strings.Builder
error_buffer: strings.Builder
clipboard_buffer: strings.Builder
initialized := false
last_status := Status.OK

ensure_initialized :: proc() {
	if initialized {
		return
	}

	editors = make(map[string]^Editor)
	return_buffer = strings.builder_make()
	error_buffer = strings.builder_make()
	clipboard_buffer = strings.builder_make()
	initialized = true
}

set_status :: proc(status: Status, message: string = "") {
	ensure_initialized()
	last_status = status

	strings.builder_reset(&error_buffer)
	strings.write_string(&error_buffer, message)
}

cstring_to_string :: proc(value: cstring) -> string {
	if value == nil {
		return ""
	}
	return string(value)
}

return_string :: proc(text: string) -> cstring {
	ensure_initialized()
	strings.builder_reset(&return_buffer)
	strings.write_string(&return_buffer, text)
	return strings.to_cstring(&return_buffer)
}

clamp_byte_index :: proc(editor: ^Editor, index: int) -> int {
	buf := editor.builder.buf[:]
	result := clamp(index, 0, len(buf))

	for result > 0 && result < len(buf) && buf[result] >= 0x80 && buf[result] < 0xc0 {
		result -= 1
	}

	return result
}

editor_text :: proc(editor: ^Editor) -> string {
	return strings.to_string(editor.builder)
}

editor_touch :: proc(editor: ^Editor) {
	editor.state.builder = &editor.builder
	textedit.update_time(&editor.state)
}

editor_set_clipboard :: proc(user_data: rawptr, text: string) -> (ok: bool) {
	ensure_initialized()
	strings.builder_reset(&clipboard_buffer)
	strings.write_string(&clipboard_buffer, text)
	return true
}

editor_get_clipboard :: proc(user_data: rawptr) -> (text: string, ok: bool) {
	ensure_initialized()
	return strings.to_string(clipboard_buffer), true
}

editor_configure :: proc(editor: ^Editor) {
	textedit.init(&editor.state, context.allocator, context.allocator)
	textedit.setup_once(&editor.state, &editor.builder)
	editor.state.set_clipboard = editor_set_clipboard
	editor.state.get_clipboard = editor_get_clipboard
}

editor_reset_text :: proc(editor: ^Editor, text: string) {
	strings.builder_reset(&editor.builder)
	strings.write_string(&editor.builder, text)
	textedit.setup_once(&editor.state, &editor.builder)
	editor.state.set_clipboard = editor_set_clipboard
	editor.state.get_clipboard = editor_get_clipboard
}

editor_destroy :: proc(editor: ^Editor) {
	textedit.destroy(&editor.state)
	strings.builder_destroy(&editor.builder)
	delete(editor.key)
	free(editor)
}

find_editor :: proc(id: cstring) -> (editor: ^Editor, ok: bool) {
	ensure_initialized()

	key := cstring_to_string(id)
	if key == "" {
		set_status(.Invalid_Id, "editor id must not be empty")
		return nil, false
	}

	editor, ok = editors[key]
	if !ok {
		set_status(.Editor_Not_Found, "editor id was not found")
		return nil, false
	}

	editor_touch(editor)
	return editor, true
}

command_from_real :: proc(command: f64) -> (cmd: textedit.Command, ok: bool) {
	value := int(command)
	if value < int(textedit.Command.None) || value > int(textedit.Command.Select_Line_End) {
		return .None, false
	}
	return textedit.Command(value), true
}

command_needs_line_navigation :: proc(cmd: textedit.Command) -> bool {
	#partial switch cmd {
	case .Up,
	     .Down,
	     .Line_Start,
	     .Line_End,
	     .Select_Up,
	     .Select_Down,
	     .Select_Line_Start,
	     .Select_Line_End:
		return true
	}
	return false
}

editor_update_line_navigation :: proc(editor: ^Editor) {
	buf := editor.builder.buf[:]
	caret := clamp_byte_index(editor, editor.state.selection[0])

	line_start := 0
	line_end := len(buf)

	for i in 0..<len(buf) {
		if buf[i] == 10 {
			if i < caret {
				line_start = i + 1
			} else {
				line_end = i
				break
			}
		}
	}

	column := caret - line_start
	up_index := caret
	down_index := caret

	if line_start > 0 {
		prev_start := 0
		prev_end := line_start - 1

		for i in 0..<prev_end {
			if buf[i] == 10 {
				prev_start = i + 1
			}
		}

		up_index = min(prev_start + column, prev_end)
	}

	if line_end < len(buf) {
		next_start := line_end + 1
		next_end := len(buf)

		for i := next_start; i < len(buf); i += 1 {
			if buf[i] == 10 {
				next_end = i
				break
			}
		}

		down_index = min(next_start + column, next_end)
	}

	editor.state.line_start = clamp_byte_index(editor, line_start)
	editor.state.line_end = clamp_byte_index(editor, line_end)
	editor.state.up_index = clamp_byte_index(editor, up_index)
	editor.state.down_index = clamp_byte_index(editor, down_index)
}

// Command values mirror core:text/edit.Command:
// 0 None, 1 Undo, 2 Redo, 3 New_Line, 4 Cut, 5 Copy, 6 Paste, 7 Select_All,
// 8 Backspace, 9 Delete, 10 Delete_Word_Left, 11 Delete_Word_Right,
// 12 Left, 13 Right, 14 Up, 15 Down, 16 Word_Left, 17 Word_Right,
// 18 Start, 19 End, 20 Line_Start, 21 Line_End, 22 Select_Left,
// 23 Select_Right, 24 Select_Up, 25 Select_Down, 26 Select_Word_Left,
// 27 Select_Word_Right, 28 Select_Start, 29 Select_End,
// 30 Select_Line_Start, 31 Select_Line_End.

@(export)
gmte_create :: proc "c" (id: cstring, initial_text: cstring) -> f64 {
	context = runtime.default_context()
	ensure_initialized()

	key := cstring_to_string(id)
	if key == "" {
		set_status(.Invalid_Id, "editor id must not be empty")
		return 0
	}

	text := cstring_to_string(initial_text)
	if editor, ok := editors[key]; ok {
		editor_reset_text(editor, text)
		set_status(.OK)
		return 1
	}

	editor := new(Editor)
	editor.key = strings.clone(key)
	editor.builder = strings.builder_make()
	strings.write_string(&editor.builder, text)
	editor_configure(editor)

	editors[editor.key] = editor
	set_status(.OK)
	return 1
}

@(export)
gmte_destroy :: proc "c" (id: cstring) -> f64 {
	context = runtime.default_context()
	editor, ok := find_editor(id)
	if !ok {
		return 0
	}

	delete_key(&editors, editor.key)
	editor_destroy(editor)
	set_status(.OK)
	return 1
}

@(export)
gmte_destroy_all :: proc "c" () -> f64 {
	context = runtime.default_context()
	ensure_initialized()

	for _, editor in editors {
		editor_destroy(editor)
	}
	delete(editors)
	editors = make(map[string]^Editor)

	set_status(.OK)
	return 1
}

@(export)
gmte_exists :: proc "c" (id: cstring) -> f64 {
	context = runtime.default_context()
	ensure_initialized()

	key := cstring_to_string(id)
	if key == "" {
		set_status(.Invalid_Id, "editor id must not be empty")
		return 0
	}

	if _, ok := editors[key]; ok {
		set_status(.OK)
		return 1
	}

	set_status(.Editor_Not_Found, "editor id was not found")
	return 0
}

@(export)
gmte_set_text :: proc "c" (id: cstring, text: cstring) -> cstring {
	context = runtime.default_context()
	editor, ok := find_editor(id)
	if !ok {
		return return_string("")
	}

	editor_reset_text(editor, cstring_to_string(text))
	set_status(.OK)
	return return_string(editor_text(editor))
}

@(export)
gmte_get_text :: proc "c" (id: cstring) -> cstring {
	context = runtime.default_context()
	editor, ok := find_editor(id)
	if !ok {
		return return_string("")
	}

	set_status(.OK)
	return return_string(editor_text(editor))
}

@(export)
gmte_input_text :: proc "c" (id: cstring, text: cstring) -> cstring {
	context = runtime.default_context()
	editor, ok := find_editor(id)
	if !ok {
		return return_string("")
	}

	textedit.input_text(&editor.state, cstring_to_string(text))
	set_status(.OK)
	return return_string(editor_text(editor))
}

@(export)
gmte_command :: proc "c" (id: cstring, command: f64) -> cstring {
	context = runtime.default_context()
	editor, ok := find_editor(id)
	if !ok {
		return return_string("")
	}

	cmd, command_ok := command_from_real(command)
	if !command_ok {
		set_status(.Invalid_Command, "command value is outside core:text/edit.Command")
		return return_string(editor_text(editor))
	}

	if command_needs_line_navigation(cmd) {
		editor_update_line_navigation(editor)
	}

	textedit.perform_command(&editor.state, cmd)
	set_status(.OK)
	return return_string(editor_text(editor))
}

@(export)
gmte_set_selection :: proc "c" (id: cstring, head: f64, tail: f64) -> cstring {
	context = runtime.default_context()
	editor, ok := find_editor(id)
	if !ok {
		return return_string("")
	}

	editor.state.selection = {
		clamp_byte_index(editor, int(head)),
		clamp_byte_index(editor, int(tail)),
	}

	set_status(.OK)
	return return_string(editor_text(editor))
}

@(export)
gmte_get_caret :: proc "c" (id: cstring) -> f64 {
	context = runtime.default_context()
	editor, ok := find_editor(id)
	if !ok {
		return -1
	}

	set_status(.OK)
	return f64(editor.state.selection[0])
}

@(export)
gmte_get_anchor :: proc "c" (id: cstring) -> f64 {
	context = runtime.default_context()
	editor, ok := find_editor(id)
	if !ok {
		return -1
	}

	set_status(.OK)
	return f64(editor.state.selection[1])
}

@(export)
gmte_get_selection_start :: proc "c" (id: cstring) -> f64 {
	context = runtime.default_context()
	editor, ok := find_editor(id)
	if !ok {
		return -1
	}

	lo, _ := textedit.sorted_selection(&editor.state)
	set_status(.OK)
	return f64(lo)
}

@(export)
gmte_get_selection_end :: proc "c" (id: cstring) -> f64 {
	context = runtime.default_context()
	editor, ok := find_editor(id)
	if !ok {
		return -1
	}

	_, hi := textedit.sorted_selection(&editor.state)
	set_status(.OK)
	return f64(hi)
}

@(export)
gmte_get_text_length :: proc "c" (id: cstring) -> f64 {
	context = runtime.default_context()
	editor, ok := find_editor(id)
	if !ok {
		return -1
	}

	set_status(.OK)
	return f64(len(editor.builder.buf))
}

@(export)
gmte_get_selected_text :: proc "c" (id: cstring) -> cstring {
	context = runtime.default_context()
	editor, ok := find_editor(id)
	if !ok {
		return return_string("")
	}

	set_status(.OK)
	return return_string(textedit.current_selected_text(&editor.state))
}

@(export)
gmte_set_line_navigation :: proc "c" (
	id: cstring,
	line_start: f64,
	line_end: f64,
	up_index: f64,
	down_index: f64,
) -> f64 {
	context = runtime.default_context()
	editor, ok := find_editor(id)
	if !ok {
		return 0
	}

	editor.state.line_start = clamp_byte_index(editor, int(line_start))
	editor.state.line_end = clamp_byte_index(editor, int(line_end))
	editor.state.up_index = clamp_byte_index(editor, int(up_index))
	editor.state.down_index = clamp_byte_index(editor, int(down_index))

	set_status(.OK)
	return 1
}

@(export)
gmte_set_translate_by_grapheme :: proc "c" (id: cstring, enabled: f64) -> f64 {
	context = runtime.default_context()
	editor, ok := find_editor(id)
	if !ok {
		return 0
	}

	editor.state.translate_by_grapheme = enabled != 0
	set_status(.OK)
	return 1
}

@(export)
gmte_clipboard_set :: proc "c" (text: cstring) -> f64 {
	context = runtime.default_context()
	editor_set_clipboard(nil, cstring_to_string(text))
	set_status(.OK)
	return 1
}

@(export)
gmte_clipboard_get :: proc "c" () -> cstring {
	context = runtime.default_context()
	ensure_initialized()
	set_status(.OK)
	return return_string(strings.to_string(clipboard_buffer))
}

@(export)
gmte_last_status :: proc "c" () -> f64 {
	return f64(int(last_status))
}

@(export)
gmte_last_error :: proc "c" () -> cstring {
	context = runtime.default_context()
	ensure_initialized()
	return strings.to_cstring(&error_buffer)
}
