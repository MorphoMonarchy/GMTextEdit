#+build !js
package main

import "core:fmt"
import "core:os"
import textedit "core:text/edit"

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
