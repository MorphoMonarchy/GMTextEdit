var ctrl_down = keyboard_check(vk_control);
var shift_down = keyboard_check(vk_shift);
var changed = false;

if (ctrl_down) {
    if (keyboard_check_pressed(ord("A"))) {
        display_text = gmte_command(editor_id, GMTE_Command.SelectAll);
        changed = true;
    } else if (keyboard_check_pressed(ord("C"))) {
        display_text = gmte_command(editor_id, GMTE_Command.Copy);
        local_clipboard_text = gmte_clipboard_get();
        clipboard_set_text(local_clipboard_text);
        changed = true;
    } else if (keyboard_check_pressed(ord("X"))) {
        display_text = gmte_command(editor_id, GMTE_Command.Cut);
        local_clipboard_text = gmte_clipboard_get();
        clipboard_set_text(local_clipboard_text);
        changed = true;
    } else if (keyboard_check_pressed(ord("V"))) {
        var paste_text = clipboard_get_text();
        if (paste_text != "") {
            local_clipboard_text = paste_text;
            gmte_clipboard_set(paste_text);
        } else if (local_clipboard_text != "") {
            gmte_clipboard_set(local_clipboard_text);
        }
        display_text = gmte_command(editor_id, GMTE_Command.Paste);
        changed = true;
    } else if (keyboard_check_pressed(ord("Z"))) {
        display_text = gmte_command(editor_id, GMTE_Command.Undo);
        changed = true;
    } else if (keyboard_check_pressed(ord("Y"))) {
        display_text = gmte_command(editor_id, GMTE_Command.Redo);
        changed = true;
    } else if (keyboard_check_pressed(vk_left)) {
        display_text = gmte_command(editor_id, shift_down ? GMTE_Command.SelectWordLeft : GMTE_Command.WordLeft);
        changed = true;
    } else if (keyboard_check_pressed(vk_right)) {
        display_text = gmte_command(editor_id, shift_down ? GMTE_Command.SelectWordRight : GMTE_Command.WordRight);
        changed = true;
    }
} else {
    if (keyboard_check_pressed(vk_left)) {
        display_text = gmte_command(editor_id, shift_down ? GMTE_Command.SelectLeft : GMTE_Command.Left);
        changed = true;
    } else if (keyboard_check_pressed(vk_right)) {
        display_text = gmte_command(editor_id, shift_down ? GMTE_Command.SelectRight : GMTE_Command.Right);
        changed = true;
    } else if (keyboard_check_pressed(vk_up)) {
        display_text = gmte_command(editor_id, shift_down ? GMTE_Command.SelectUp : GMTE_Command.Up);
        changed = true;
    } else if (keyboard_check_pressed(vk_down)) {
        display_text = gmte_command(editor_id, shift_down ? GMTE_Command.SelectDown : GMTE_Command.Down);
        changed = true;
    } else if (keyboard_check_pressed(vk_home)) {
        display_text = gmte_command(editor_id, shift_down ? GMTE_Command.SelectLineStart : GMTE_Command.LineStart);
        changed = true;
    } else if (keyboard_check_pressed(vk_end)) {
        display_text = gmte_command(editor_id, shift_down ? GMTE_Command.SelectLineEnd : GMTE_Command.LineEnd);
        changed = true;
    } else if (keyboard_check_pressed(vk_backspace)) {
        display_text = gmte_command(editor_id, GMTE_Command.Backspace);
        changed = true;
    } else if (keyboard_check_pressed(vk_delete)) {
        display_text = gmte_command(editor_id, GMTE_Command.Delete);
        changed = true;
    } else if (keyboard_check_pressed(vk_enter)) {
        display_text = gmte_command(editor_id, GMTE_Command.NewLine);
        changed = true;
    } else if (keyboard_check_pressed(vk_tab)) {
        display_text = gmte_input_text(editor_id, "    ");
        changed = true;
    }
}

var typed = keyboard_string;
keyboard_string = "";

if (!ctrl_down && !changed && typed != "") {
    display_text = gmte_input_text(editor_id, typed);
    changed = true;
}

if (changed) {
    display_text = gmte_get_text(editor_id);
}

caret = gmte_get_caret(editor_id);
anchor = gmte_get_anchor(editor_id);
selection_start = gmte_get_selection_start(editor_id);
selection_end = gmte_get_selection_end(editor_id);
selected_text = gmte_get_selected_text(editor_id);
clipboard_text = gmte_clipboard_get();
system_clipboard_text = clipboard_get_text();
if (system_clipboard_text != "") {
    local_clipboard_text = system_clipboard_text;
}
status = gmte_last_status();
error_text = gmte_last_error();
