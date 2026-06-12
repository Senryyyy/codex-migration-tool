# Codex Migration Tool

[中文](README.md) | English

A Windows migration helper for moving local Codex conversations, Codex app state, and selected project folders between two PCs over a LAN shared folder.

## What It Migrates

- Codex conversations and local state from `%USERPROFILE%\.codex`
- Codex workspaces from `%USERPROFILE%\Documents\Codex`
- Optional extra project folders selected in the GUI
- Extra project folders are restored to the same absolute paths on the new PC

The tool intentionally does not migrate API login credentials such as `auth.json`.

## Files

- `CodexMigrationTool.cmd` - double-click launcher
- `CodexMigrationTool.ps1` - GUI wrapper
- `codex-migrate.ps1` - migration engine

Keep all three files in the same folder.

## Typical Workflow

1. On the new PC, create and share a folder such as `C:\CodexImport`.
2. On the old PC, run `CodexMigrationTool.cmd`.
3. Set the migration package folder to the network share, for example:

   ```text
   \\NEWPC\CodexImport
   ```

4. Add any extra project folders that should be copied.
5. Close Codex on the old PC.
6. Click `Old PC: Export package`.
7. On the new PC, run the same tool.
8. Click `New PC: Verify package`.
9. Close Codex on the new PC.
10. Click `New PC: Import package`.

## Notes From Real Use

- During transfer, the black terminal window keeps showing copy progress. The GUI window may show as not responding during large copies; this is expected. Check Task Manager or watch whether the receiving folder size is still changing.
- If a run fails partway through, the safest practical recovery is to delete the incomplete migration package folder and start again. With a stable LAN connection, the transfer usually completes in one clean run.
- Extra projects are copied with `robocopy` and tracked in `extra-projects.json`; they are not fully hashed into `migration-manifest.json`, because build folders can contain very long paths and many transient files.

## Verification Scope

The main manifest verifies Codex conversations, settings, and workspace files. Extra project folders are checked by presence through `extra-projects.json` and restored with `robocopy`.

## Requirements

- Windows PowerShell 5 or newer
- Windows file sharing enabled between the two PCs
- Same Windows username on both PCs if you want extra project folders restored to the exact same paths

