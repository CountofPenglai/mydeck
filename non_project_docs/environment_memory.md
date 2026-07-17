# Environment Memory

This folder stores local-machine notes that are useful for Codex work but are not part of the Godot game itself.

## Godot

- Godot directory: `C:\Program Files (x86)\Steam\steamapps\common\Godot Engine`
- Godot executable: `C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`
- Detected version family: Godot `4.7.1-stable`
- Verified version command: `4.7.1.stable.steam.a13da4feb`
- The former `D:\deep_learning_tool\godot` 4.6.3 installation was no longer present when checked on 2026-07-17.

## Useful Commands

Run a strict headless editor compile/load check for this project:

```powershell
& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --disable-crash-handler --log-file "tmp\project_compile.log" --path "D:\py_work\my-deck" --editor --quit
```

Run one diagnostic scene:

```powershell
& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --disable-crash-handler --log-file "tmp\battle_flow.log" --path "D:\py_work\my-deck" --scene "res://tools/diagnostics/battle_flow_check.tscn"
```

Check the Godot version:

```powershell
& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --version
```

Temporarily add Godot to the current PowerShell session PATH:

```powershell
$env:GODOT = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
```

After that, this should work in the same session:

```powershell
& $env:GODOT --version
& $env:GODOT --headless --path "D:\py_work\my-deck" --quit
```

## Current Test Status

- The Steam tools executable prints its version and supports both editor and headless diagnostic commands.
- In the default Codex workspace sandbox, project/script loading checks can crash the Godot process with `CrashHandlerException: Program crashed with signal 11` after printing `Could not create directory: 'user://logs'`:

```powershell
& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path "D:\py_work\my-deck" --quit
& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --path "D:\py_work\my-deck" --check-only --script "res://scripts/battle/battle_controller.gd"
```

Root cause: Godot writes logs/cache under `%APPDATA%\Godot\...`, which is outside the workspace sandbox. When the sandbox denies that write, Godot can crash before reporting project errors.

Resolution: run Godot CLI checks outside the workspace sandbox / with Codex escalation so AppData writes are allowed.

Verified with the current Steam installation on 2026-07-17:

```powershell
& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --disable-crash-handler --log-file "tmp\project_compile.log" --path "D:\py_work\my-deck" --editor --quit
& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --disable-crash-handler --log-file "tmp\battle_load.log" --path "D:\py_work\my-deck" --scene "res://tools/diagnostics/diagnose_battle_load.tscn"
```

Both commands complete successfully when run outside the sandbox. Key diagnostic scenes are indexed in `project_structure_and_skill_workflow.md`.

Headless diagnostics currently print Dummy Renderer texture/RID and ObjectDB cleanup warnings during process exit. Treat the process exit code and the diagnostic completion marker as the test result; do not treat those known exit-only warnings as gameplay failures.

Commands using `--log-file "tmp\..."` create local log files. Remove them after inspection so they are not mistaken for project artifacts.
