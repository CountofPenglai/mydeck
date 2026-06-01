# Environment Memory

This folder stores local-machine notes that are useful for Codex work but are not part of the Godot game itself.

## Godot

- Godot directory: `D:\deep_learning_tool\godot`
- Godot executable: `D:\deep_learning_tool\godot\godot.exe`
- Console executable, if needed: `D:\deep_learning_tool\godot\Godot_v4.6.3-stable_win64_console.exe`
- Detected version family: Godot `4.6.3-stable`
- Verified console version command: `4.6.3.stable.official.7d41c59c4`

## Useful Commands

Run a headless editor compile/load check for this project:

```powershell
& "D:\deep_learning_tool\godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\py_work\my-deck" --quit
```

Check the Godot version:

```powershell
& "D:\deep_learning_tool\godot\Godot_v4.6.3-stable_win64_console.exe" --version
```

Temporarily add Godot to the current PowerShell session PATH:

```powershell
$env:PATH = "D:\deep_learning_tool\godot;$env:PATH"
```

After that, this should work in the same session:

```powershell
godot --version
godot --headless --path "D:\py_work\my-deck" --quit
```

## Current Test Status

- `Godot_v4.6.3-stable_win64_console.exe --version` works and prints the version.
- `godot.exe --version` launches successfully but does not print version output to this PowerShell session, likely because it is the Windows GUI executable.
- In the default Codex workspace sandbox, project/script loading checks can crash the Godot process with `CrashHandlerException: Program crashed with signal 11` after printing `Could not create directory: 'user://logs'`:

```powershell
& "D:\deep_learning_tool\godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\py_work\my-deck" --quit
& "D:\deep_learning_tool\godot\Godot_v4.6.3-stable_win64_console.exe" --path "D:\py_work\my-deck" --check-only --script "res://scripts/battle/battle_controller.gd"
```

Root cause: Godot writes logs/cache under `%APPDATA%\Godot\...`, which is outside the workspace sandbox. When the sandbox denies that write, Godot 4.6.3 can crash before reporting project errors.

Resolution: run Godot CLI checks outside the workspace sandbox / with Codex escalation so AppData writes are allowed.

Verified on 2026-06-01:

```powershell
& "D:\deep_learning_tool\godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\py_work\my-deck" --quit
& "D:\deep_learning_tool\godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\py_work\my-deck" --scene "res://scenes/battle_scene.tscn" --quit
```

Both commands complete successfully when run outside the sandbox.
