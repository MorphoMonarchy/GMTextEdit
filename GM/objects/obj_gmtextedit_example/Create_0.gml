editor_id = "example";

edit_x = 64;
edit_y = 104;
edit_width = 740;
edit_height = 220;
line_sep = 24;

display_text = "Edit this text with gmtextedit.dll.\nMove between these lines with Up and Down.\nThe caret state below should follow.";
selected_text = "";
clipboard_text = "";
system_clipboard_text = "";
status = GMTE_Status.OK;
error_text = "";
caret = 0;
anchor = 0;
selection_start = 0;
selection_end = 0;

gmte_create(editor_id, display_text);
gmte_set_selection(editor_id, gmte_get_text_length(editor_id), gmte_get_text_length(editor_id));

display_text = gmte_get_text(editor_id);
caret = gmte_get_caret(editor_id);
anchor = gmte_get_anchor(editor_id);
selection_start = gmte_get_selection_start(editor_id);
selection_end = gmte_get_selection_end(editor_id);
clipboard_text = gmte_clipboard_get();
system_clipboard_text = clipboard_get_text();
status = gmte_last_status();
error_text = gmte_last_error();

keyboard_string = "";
