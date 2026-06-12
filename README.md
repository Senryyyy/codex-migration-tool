# Codex 迁移工具

中文 | [English](README.en.md)

一个 Windows 图形化迁移工具，用于在同一局域网内的两台电脑之间迁移本地 Codex 对话、Codex 本地状态、默认工作区，以及你额外选择的项目文件夹。

## 迁移内容

- `%USERPROFILE%\.codex` 中的 Codex 对话、本地状态、配置、记忆、技能和插件
- `%USERPROFILE%\Documents\Codex` 中的 Codex 默认工作区
- 你在界面中手动添加的额外项目文件夹
- 额外项目会在新电脑上恢复到旧电脑相同的绝对路径

工具会刻意跳过 API 登录凭据，例如 `auth.json`，避免把登录状态或敏感凭据复制到另一台机器。

## 文件组成

- `CodexMigrationTool.cmd`：双击启动入口
- `CodexMigrationTool.ps1`：图形界面
- `codex-migrate.ps1`：迁移引擎

使用时请把这三个文件放在同一个文件夹里。

## 典型使用流程

1. 在新电脑创建一个接收目录，例如：

   ```text
   C:\CodexImport
   ```

2. 把这个目录共享到局域网。
3. 在旧电脑双击运行 `CodexMigrationTool.cmd`。
4. 将迁移包路径设置为新电脑共享目录，例如：

   ```text
   \\NEWPC\CodexImport
   ```

5. 如果还要迁移自己创建的项目目录，点击 `Add Project Folder` 添加这些项目文件夹。
6. 关闭旧电脑上的 Codex。
7. 点击 `Old PC: Export package` 导出迁移包。
8. 在新电脑运行同一个工具。
9. 点击 `New PC: Verify package` 校验迁移包。
10. 关闭新电脑上的 Codex。
11. 点击 `New PC: Import package` 导入。

## 实际使用注意事项

- 传输时黑色终端窗口会持续显示 `robocopy` 复制进度。白色 GUI 窗口在大文件夹复制期间可能显示“无响应”，这是正常现象。
- 判断是否还在传输，可以看任务管理器里的磁盘/网络活动，也可以看接收电脑共享文件夹大小是否还在变化。
- 如果一次没有成功，最稳妥的做法是删除接收端不完整的迁移包文件夹，然后重新来一遍。网络稳定时通常可以一次完成。
- 额外项目使用 `robocopy` 完整复制，并通过 `extra-projects.json` 记录路径映射；它们不会逐文件写入 `migration-manifest.json`，因为构建目录里经常有超长路径和临时文件。

## 校验范围

`migration-manifest.json` 会校验 Codex 对话、配置和默认工作区文件。额外项目文件夹通过 `extra-projects.json` 检查目录引用，并在导入时用 `robocopy` 恢复。

## 环境要求

- Windows PowerShell 5 或更新版本
- 两台电脑位于同一局域网，且 Windows 文件共享可用
- 如果希望额外项目恢复到完全相同路径，新旧电脑最好使用相同 Windows 用户名

## 不迁移的内容

默认不会迁移以下内容：

- Codex 登录凭据，例如 `.codex\auth.json`
- 机器身份文件，例如 `.codex\installation_id`
- 临时目录、sandbox、浏览器缓存和运行时缓存

这些内容建议在新电脑上由 Codex 重新生成。

