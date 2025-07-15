# AGENTS.md - Dooing Neovim Plugin Development Guide

## Project Overview
Dooing is a Neovim plugin written in Lua for todo list management with Todoist API integration.

## Build/Test Commands
- No build system (pure Lua plugin)
- No formal test suite - test manually with `:Dooing` command
- Plugin loads via Neovim's runtime path

## Code Style Guidelines

### File Structure
- Main entry: `lua/dooing/init.lua`
- Modules: `config.lua`, `state.lua`, `ui.lua`, `api/todoist.lua`, `calendar.lua`, `server.lua`
- Documentation: `doc/dooing.txt`

### Lua Conventions
- Use `local M = {}` module pattern
- Declare `local vim = vim` at top of files for LSP
- Use `---@diagnostic disable` for vim globals
- Type annotations with `---@class` and `---@field`
- Snake_case for functions and variables
- Use `vim.tbl_deep_extend("force", defaults, opts)` for config merging

### Error Handling
- Use `pcall()` for potentially failing operations
- `vim.notify()` for user messages with log levels (INFO, WARN, ERROR)
- Return `nil` on errors with optional error message

### API Integration
- Environment variable `TODOIST_API_TOKEN` or config option
- Use `vim.fn.system()` with curl for HTTP requests
- JSON encoding/decoding with `vim.fn.json_encode/decode`