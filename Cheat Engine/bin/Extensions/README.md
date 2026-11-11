# Extensions

Every sub folder in this folder is an extension that is loaded when Cheat Engine starts (after the `autorun` folder).

* Lua files directly in this folder are loaded first.
* Then every sub folder is loaded, in alphabetical order.
* If a sub folder has a `loadorder.txt`, only the entries in it are loaded, in that order: one Lua file or folder per
  line, lines starting with `#` are comments. Without it, every `.lua` file in the sub folder is loaded.
* `getCurrentScriptPath()` returns the path of the file being loaded, so an extension can find its own files.

To remove an extension, delete its folder.

## AITools

A copy of <https://github.com/cheat-engine/AITools> (MIT license), updated for this build. See
[`docs/AITOOLS.md`](../../../docs/AITOOLS.md) in the repository for what changed and how to use it.
