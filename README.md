# GMTextEdit

GMTextEdit is a small GameMaker + Odin project that wraps Odin's `core:text/edit`
text editing primitives in a native extension for GameMaker.

The goal is to let GameMaker code create lightweight text editor states, send
text input or editing commands to Odin, then read back the edited string, caret,
selection, status, and clipboard state.

Windows uses a native DLL. HTML5/GX uses a generated JavaScript extension that
embeds the same Odin code compiled to WebAssembly, so the GML API stays the
same across targets.

## Project Layout

```text
GMTextEdit/
  GM/                         GameMaker project
    extensions/ext_gmtextedit GameMaker extension resource and packaged DLL
                              plus generated GX/HTML5 JavaScript bridge
    objects/                  Example object that demonstrates editing text
    rooms/Room1               Example room with the sample object
    scripts/                  Command/status enums for GameMaker
  Odin/
    textedit.odin             Odin source for the DLL and test runner
    textedit_wasm.odin        JS/Wasm scratch-buffer bridge helpers
    textedit_native_test.odin Native-only smoke tests and executable entry point
    build.bat                 Windows build script
    build_gx.bat              GX/HTML5 Wasm + JavaScript bridge build script
    build_gx_bridge.ps1       Embeds the Wasm module into gmtextedit.js
    build/                    Build outputs
```

## Requirements

- GameMaker 2024 project format
- Odin compiler
- Windows/MSVC toolchain for the native DLL build in `build.bat`
- PowerShell for generating the GX/HTML5 JavaScript bridge

The GameMaker extension includes the Windows DLL:

```text
GM/extensions/ext_gmtextedit/gmtextedit.dll
```

and a generated JavaScript bridge for HTML5/GX:

```text
GM/extensions/ext_gmtextedit/gmtextedit.js
```

Linux and macOS builds would need matching shared libraries (`.so` / `.dylib`)
and GameMaker extension proxy-file metadata for those targets.

## Building

Build and test the native Windows DLL, then regenerate the GX/HTML5 bridge:

```bat
Odin\build.bat
```

If you only need the GX/HTML5 JavaScript bridge, run:

```bat
Odin\build_gx.bat
```

`build_gx.bat` compiles `Odin/build/gmtextedit.wasm` with Odin's `js_wasm32`
target, then embeds that Wasm payload into
`GM/extensions/ext_gmtextedit/gmtextedit.js`.

## GameMaker Example

Open the GameMaker project at:

```text
GM/GMTextEdit.yyp
```

`Room1` contains `obj_gmtextedit_example`, which:

- creates an editor state with `gmte_create`
- accepts typed input with `gmte_input_text`
- handles common edit/navigation commands with `gmte_command`
- draws the edited string
- displays caret, anchor, selection, clipboard, and error status values
- mirrors copied/cut text to the system clipboard and reads system clipboard text before paste

The example includes multiline text so Up/Down caret movement can be tested
immediately.

## GameMaker API

The extension functions are documented in:

```text
GM/extensions/ext_gmtextedit/ext_gmtextedit.yy
```

Main functions:

| Function | Purpose |
| --- | --- |
| `gmte_create(id, initial_text)` | Creates or resets an editor state. |
| `gmte_destroy(id)` | Destroys one editor state. |
| `gmte_destroy_all()` | Destroys every editor state. |
| `gmte_exists(id)` | Returns whether an editor exists. |
| `gmte_set_text(id, text)` | Replaces the editor text. |
| `gmte_get_text(id)` | Returns the current editor text. |
| `gmte_input_text(id, text)` | Inserts text at the caret or selection. |
| `gmte_command(id, command)` | Runs an edit/navigation command. |
| `gmte_set_selection(id, head, tail)` | Sets caret/selection byte indices. |
| `gmte_get_caret(id)` | Returns the caret byte index. |
| `gmte_get_anchor(id)` | Returns the selection anchor byte index. |
| `gmte_get_selection_start(id)` | Returns the lower selection byte index. |
| `gmte_get_selection_end(id)` | Returns the upper selection byte index. |
| `gmte_get_text_length(id)` | Returns text length in bytes. |
| `gmte_get_selected_text(id)` | Returns selected text. |
| `gmte_set_translate_by_grapheme(id, enabled)` | Toggles grapheme-aware left/right movement. |
| `gmte_clipboard_set(text)` | Sets the extension clipboard buffer. |
| `gmte_clipboard_get()` | Gets the extension clipboard buffer. |
| `gmte_last_status()` | Returns the last status code. |
| `gmte_last_error()` | Returns the last error message. |

## Commands

GameMaker command constants live in:

```text
GM/scripts/scr_gmtextedit_constants/scr_gmtextedit_constants.gml
```

They mirror Odin's `core:text/edit.Command` values:

```gml
gmte_command(editor_id, GMTE_Command.Left);
gmte_command(editor_id, GMTE_Command.Right);
gmte_command(editor_id, GMTE_Command.Up);
gmte_command(editor_id, GMTE_Command.Down);
gmte_command(editor_id, GMTE_Command.SelectAll);
gmte_command(editor_id, GMTE_Command.Paste);
```

The numeric enum values are explicit because they are ABI constants shared with
the Odin DLL.

## Notes

- Selection and caret positions are byte indices, not GameMaker character
  indices.
- The extension stores text editor states by string id.
- The extension clipboard functions use an internal buffer. The included
  GameMaker example mirrors Copy/Cut to the system clipboard when possible,
  but keeps a local fallback clipboard for GX/browser builds where
  `clipboard_get_text()` can return an empty string.
- Up/Down and line-start/end movement are handled inside the Odin wrapper before
  dispatching to Odin's built-in text edit commands.
