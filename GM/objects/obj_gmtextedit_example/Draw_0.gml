draw_set_halign(fa_left);
draw_set_valign(fa_top);

draw_set_color(make_color_rgb(18, 22, 28));
draw_rectangle(0, 0, room_width, room_height, false);

draw_set_color(c_white);
draw_text(64, 40, "GMTextEdit extension sample");

draw_set_color(make_color_rgb(42, 48, 58));
draw_rectangle(edit_x - 16, edit_y - 16, edit_x + edit_width + 16, edit_y + edit_height, false);

draw_set_color(make_color_rgb(96, 112, 132));
draw_rectangle(edit_x - 16, edit_y - 16, edit_x + edit_width + 16, edit_y + edit_height, true);

draw_set_color(c_white);
draw_text_ext(edit_x, edit_y, display_text, line_sep, edit_width);

draw_set_color(make_color_rgb(160, 210, 255));
draw_text(edit_x, edit_y + edit_height + 24, "caret " + string(caret) + "  anchor " + string(anchor) + "  selection " + string(selection_start) + "-" + string(selection_end));

draw_set_color(make_color_rgb(188, 210, 180));
draw_text(edit_x, edit_y + edit_height + 52, "selected: " + selected_text);
draw_text(edit_x, edit_y + edit_height + 80, "clipboard: " + clipboard_text);

if (status != GMTE_Status.OK) {
    draw_set_color(make_color_rgb(255, 112, 112));
    draw_text(edit_x, edit_y + edit_height + 116, "status " + string(status) + ": " + error_text);
}
