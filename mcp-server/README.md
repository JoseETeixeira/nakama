# Kiro MCP Server

Model Context Protocol server for Kiro mode-specific prompt injection into Copilot.

## Overview

This MCP server provides tools that allow Copilot to execute with Kiro's mode-specific prompts (executeTask and requirements) in native context, without going through the `@kiro` chat participant.

## Installation

```bash
cd mcp-server
npm install
npm run build
```

## Configuration

Add to your `.kiro/settings/mcp.json` or `~/.kiro/settings/mcp.json`:

```json
{
  "mcpServers": {
    "kiro": {
      "command": "node",
      "args": ["path/to/VSCodeExtension/mcp-server/dist/index.js"],
      "disabled": false,
      "autoApprove": [
        "kiro_execute_task",
        "kiro_create_requirements",
        "kiro_set_mode",
        "kiro_get_current_mode"
      ]
    }
  }
}
```

## Available Tools

### `kiro_execute_task`
Execute a task using the executeTask workflow (Vibe mode).
- Loads the full executeTask prompt with mandatory context gathering
- Reads design.md, requirements.md, and .kiro/steering/ files
- Implements the task following the workflow

**Example usage in Copilot:**
```
Use kiro_execute_task to implement the login feature
Use kiro_execute_task to execute task 12 from the spec
```

### `kiro_create_requirements`
Create or refine requirements using the requirements workflow (Spec mode).
- Loads the requirements prompt
- Guides structured feature planning

**Example usage in Copilot:**
```
Use kiro_create_requirements to create requirements for the user authentication system
```

### `kiro_set_mode`
Switch between Kiro modes: "vibe" or "spec"

**Example usage in Copilot:**
```
Use kiro_set_mode with mode "vibe"
Use kiro_set_mode with mode "spec"
```

### `kiro_get_current_mode`
Get the current Kiro mode and its description

## How It Works

1. Copilot calls the MCP tool (e.g., `kiro_execute_task`)
2. The MCP server loads the appropriate mode-specific prompt file
3. The server combines the prompt with the user's command
4. Returns the full prompt to Copilot
5. Copilot executes with the injected instructions in native context

## Benefits

- ✅ Copilot executes in native context with full capabilities
- ✅ No need for `@kiro` participant workarounds
- ✅ Automatic prompt injection based on mode
- ✅ Can be auto-approved for seamless workflow
- ✅ Works with Copilot Chat, Copilot Edits, and inline suggestions

## Development

```bash
npm run watch  # Watch mode for development
npm run build  # Build for production
```
