package main

import "base:runtime"
import "core:fmt"
import "core:os"
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

cmd_real :: proc(cmd: textedit.Command) -> f64 {
	return f64(int(cmd))
}

Test_Context :: struct {
	failures: int,
}

expect_bool :: proc(ctx: ^Test_Context, name: string, got, expected: bool) {
	if got != expected {
		fmt.eprintf("ERROR: %s: expected %v, got %v\n", name, expected, got)
		ctx.failures += 1
	}
}

expect_int :: proc(ctx: ^Test_Context, name: string, got, expected: int) {
	if got != expected {
		fmt.eprintf("ERROR: %s: expected %d, got %d\n", name, expected, got)
		ctx.failures += 1
	}
}

expect_string :: proc(ctx: ^Test_Context, name: string, got, expected: string) {
	if got != expected {
		fmt.eprintf("ERROR: %s: expected \"%s\", got \"%s\"\n", name, expected, got)
		ctx.failures += 1
	}
}

test_create_set_and_destroy :: proc(ctx: ^Test_Context) {
	id := cstring("basic")

	gmte_destroy_all()

	expect_int(ctx, "create returns success", int(gmte_create(id, cstring("Hello"))), 1)
	expect_int(ctx, "exists after create", int(gmte_exists(id)), 1)
	expect_string(ctx, "get text after create", string(gmte_get_text(id)), "Hello")
	expect_int(ctx, "text length after create", int(gmte_get_text_length(id)), 5)

	expect_string(ctx, "set text returns updated text", string(gmte_set_text(id, cstring("World"))), "World")
	expect_string(ctx, "get text after set", string(gmte_get_text(id)), "World")

	expect_int(ctx, "destroy returns success", int(gmte_destroy(id)), 1)
	expect_int(ctx, "missing after destroy", int(gmte_exists(id)), 0)
}

test_input_selection_and_clipboard :: proc(ctx: ^Test_Context) {
	id := cstring("edit")

	gmte_destroy_all()
	gmte_create(id, cstring("Hello"))
	gmte_set_selection(id, gmte_get_text_length(id), gmte_get_text_length(id))

	expect_string(ctx, "input text appends at caret", string(gmte_input_text(id, cstring(", Odin"))), "Hello, Odin")
	expect_int(ctx, "caret after input", int(gmte_get_caret(id)), 11)
	expect_int(ctx, "anchor after input", int(gmte_get_anchor(id)), 11)

	gmte_command(id, cmd_real(.Select_Word_Left))
	expect_string(ctx, "selected word left", string(gmte_get_selected_text(id)), "Odin")

	gmte_clipboard_set(cstring("GameMaker"))
	expect_string(ctx, "paste replaces selection", string(gmte_command(id, cmd_real(.Paste))), "Hello, GameMaker")

	gmte_command(id, cmd_real(.Select_All))
	gmte_command(id, cmd_real(.Copy))
	expect_string(ctx, "copy selected text to clipboard", string(gmte_clipboard_get()), "Hello, GameMaker")
}

test_multiline_navigation :: proc(ctx: ^Test_Context) {
	id := cstring("lines")

	gmte_destroy_all()
	gmte_create(id, cstring("abc\ndef\nghi"))
	gmte_set_selection(id, 5, 5)

	gmte_command(id, cmd_real(.Up))
	expect_int(ctx, "up moves to matching previous line column", int(gmte_get_caret(id)), 1)

	gmte_command(id, cmd_real(.Down))
	expect_int(ctx, "down moves back to matching next line column", int(gmte_get_caret(id)), 5)

	gmte_command(id, cmd_real(.Line_Start))
	expect_int(ctx, "line start moves to current line start", int(gmte_get_caret(id)), 4)

	gmte_command(id, cmd_real(.Line_End))
	expect_int(ctx, "line end moves to current line end", int(gmte_get_caret(id)), 7)
}

test_utf8_selection_clamping :: proc(ctx: ^Test_Context) {
	id := cstring("utf8")

	gmte_destroy_all()
	gmte_create(id, cstring("aéz"))

	gmte_set_selection(id, 2, 2)
	expect_int(ctx, "selection clamps away from UTF-8 continuation byte", int(gmte_get_caret(id)), 1)
}

test_error_reporting :: proc(ctx: ^Test_Context) {
	gmte_destroy_all()

	expect_int(ctx, "empty id create fails", int(gmte_create(cstring(""), cstring(""))), 0)
	expect_int(ctx, "empty id status", int(gmte_last_status()), int(Status.Invalid_Id))
	expect_bool(ctx, "empty id error has text", len(string(gmte_last_error())) > 0, true)

	expect_string(ctx, "missing editor get text returns empty", string(gmte_get_text(cstring("missing"))), "")
	expect_int(ctx, "missing editor status", int(gmte_last_status()), int(Status.Editor_Not_Found))

	gmte_create(cstring("bad-command"), cstring("Safe"))
	expect_string(ctx, "invalid command keeps text", string(gmte_command(cstring("bad-command"), 999)), "Safe")
	expect_int(ctx, "invalid command status", int(gmte_last_status()), int(Status.Invalid_Command))
}

run_tests :: proc() -> int {
	ctx := Test_Context{}

	test_create_set_and_destroy(&ctx)
	test_input_selection_and_clipboard(&ctx)
	test_multiline_navigation(&ctx)
	test_utf8_selection_clamping(&ctx)
	test_error_reporting(&ctx)

	gmte_destroy_all()
	return ctx.failures
}

main :: proc() {
	failures := run_tests()
	if failures != 0 {
		fmt.eprintf("ERROR: GMTextEdit failed %d test(s)\n", failures)
		os.exit(1)
	}

	fmt.println("GMTextEdit ready")
}
