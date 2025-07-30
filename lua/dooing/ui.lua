---@diagnostic disable: undefined-global, param-type-mismatch, deprecated
-- Explicitly declare vim as a global variable
local vim = vim

-- UI Module for Dooing Plugin
-- Handles window creation, rendering and UI interactions for todo management

---@class DoingUI
---@field toggle_todo_window function
---@field render_todos function
---@field close_window function
---@field new_todo function
---@field toggle_todo function
---@field delete_todo function
---@field delete_completed function
local M = {}

--------------------------------------------------
-- Dependencies
--------------------------------------------------
local state = require("dooing.state")
local config = require("dooing.config")
local calendar = require("dooing.calendar")
local server = require("dooing.server")

--------------------------------------------------
-- Utility Helpers
--------------------------------------------------

-- Notification helper for consistent messaging
local notify = {
	success = function(msg) 
		vim.notify(msg, vim.log.levels.INFO, { title = "Dooing" }) 
	end,
	error = function(msg) 
		vim.notify(msg, vim.log.levels.ERROR, { title = "Dooing" }) 
	end,
	warn = function(msg) 
		vim.notify(msg, vim.log.levels.WARN, { title = "Dooing" }) 
	end,
	info = function(msg) 
		vim.notify(msg, vim.log.levels.INFO, { title = "Dooing" }) 
	end,
}

-- Auto-render wrapper for functions that modify todos
local function auto_render(fn)
	return function(...)
		-- Store the current window ID before the action
		local current_win_id = win_id
		local current_buf_id = buf_id
		print("DEBUG: auto_render start - win_id=" .. (win_id or "nil") .. ", buf_id=" .. (buf_id or "nil"))
		
		local result = fn(...)
		
		-- Try to find the todo window if win_id is lost
		if not win_id or not vim.api.nvim_win_is_valid(win_id) then
			print("DEBUG: win_id lost, searching...")
			-- Look for a window with our buffer
			if current_buf_id and vim.api.nvim_buf_is_valid(current_buf_id) then
				for _, w in ipairs(vim.api.nvim_list_wins()) do
					if vim.api.nvim_win_get_buf(w) == current_buf_id then
						print("DEBUG: Found window by buf_id: " .. w)
						win_id = w
						buf_id = current_buf_id
						break
					end
				end
			else
				-- Try to find any window with dooing content
				for _, w in ipairs(vim.api.nvim_list_wins()) do
					local buf = vim.api.nvim_win_get_buf(w)
					local lines = vim.api.nvim_buf_get_lines(buf, 0, 5, false)
					-- Check if this looks like a dooing buffer
					for _, line in ipairs(lines) do
						if line:match("[○◐✓]") then
							print("DEBUG: Found window by content: " .. w)
							win_id = w
							buf_id = buf
							break
						end
					end
					if win_id then break end
				end
			end
		end
		
		print("DEBUG: auto_render end - win_id=" .. (win_id or "nil") .. ", valid=" .. tostring(win_id and vim.api.nvim_win_is_valid(win_id)))
		if win_id and vim.api.nvim_win_is_valid(win_id) then
			print("DEBUG: Calling M.render_todos()")
			M.render_todos()
			print("DEBUG: M.render_todos() completed")
		else
			print("DEBUG: Skipping render - no valid window")
		end
		return result
	end
end

--------------------------------------------------
-- Local Variables and Cache
--------------------------------------------------
-- Namespace for highlighting
local ns_id = vim.api.nvim_create_namespace("dooing")
-- Cache for highlight groups
local highlight_cache = {}

-- Window and buffer IDs
---@type integer|nil
local win_id = nil
---@type integer|nil
local buf_id = nil
---@type integer|nil
local help_win_id = nil
---@type integer|nil
local help_buf_id = nil
---@type integer|nil
local tag_win_id = nil
---@type integer|nil
local tag_buf_id = nil
---@type integer|nil
local search_win_id = nil
---@type integer|nil
local search_buf_id = nil

-- Mapping from displayed line number to todo index; updated in render_todos()
local line_to_todo = {}

-- Forward declare local functions that are used in keymaps
local create_help_window
local create_tag_window
local edit_todo
local edit_priorities

--------------------------------------------------
-- Highlights Setup
--------------------------------------------------
-- Set up highlights

local function setup_highlights()
	-- Clear highlight cache
	highlight_cache = {}

	-- Set up base highlights
	vim.api.nvim_set_hl(0, "DooingPending", { link = "Question", default = true })
	vim.api.nvim_set_hl(0, "DooingDone", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "DooingHelpText", { link = "Directory", default = true })
	vim.api.nvim_set_hl(0, "DooingTimestamp", { link = "Comment", default = true }) -- Add timestamp highlight in blue

	-- Cache the base highlight groups
	highlight_cache.pending = "DooingPending"
	highlight_cache.done = "DooingDone"
	highlight_cache.help = "DooingHelpText"
end

-- Safe input function that doesn't conflict with snacks.nvim
local function safe_input(opts, callback)
	-- Use vim.fn.input instead of vim.ui.input to avoid conflicts
	local result = vim.fn.input(opts.prompt or "", opts.default or "")
	if callback then
		callback(result)
	end
end

-- Helper function to clean up priority selection resources
local function cleanup_priority_selection(select_buf, select_win, keymaps)
	-- Remove all keymaps
	for _, keymap in ipairs(keymaps) do
		pcall(vim.keymap.del, "n", keymap, { buffer = select_buf })
	end

	-- Close window if it's still valid
	if select_win and vim.api.nvim_win_is_valid(select_win) then
		vim.api.nvim_win_close(select_win, true)
	end

	-- Delete buffer if it still exists
	if select_buf and vim.api.nvim_buf_is_valid(select_buf) then
		vim.api.nvim_buf_delete(select_buf, { force = true })
	end
end

-- Get highlight group for a set of priorities
local function get_priority_highlight(priorities)
	if not priorities or #priorities == 0 then
		return highlight_cache.pending
	end

	-- Sort priority groups by number of members (descending)
	local sorted_groups = {}
	for name, group in pairs(config.options.priority_groups) do
		table.insert(sorted_groups, { name = name, group = group })
	end
	table.sort(sorted_groups, function(a, b)
		return #a.group.members > #b.group.members
	end)

	-- Check priority groups from largest to smallest
	for _, group_data in ipairs(sorted_groups) do
		local group = group_data.group
		-- Check if all group members are present in the priorities
		local all_members_match = true
		for _, member in ipairs(group.members) do
			local found = false
			for _, priority in ipairs(priorities) do
				if priority == member then
					found = true
					break
				end
			end
			if not found then
				all_members_match = false
				break
			end
		end

		if all_members_match then
			-- Create cache key from group definition
			local cache_key = table.concat(group.members, "_")
			if highlight_cache[cache_key] then
				return highlight_cache[cache_key]
			end

			local hl_group = highlight_cache.pending
			if group.color and type(group.color) == "string" and group.color:match("^#%x%x%x%x%x%x$") then
				local hl_name = "Dooing" .. group.color:gsub("#", "")
				vim.api.nvim_set_hl(0, hl_name, { fg = group.color })
				hl_group = hl_name
			elseif group.hl_group then
				hl_group = group.hl_group
			end

			highlight_cache[cache_key] = hl_group
			return hl_group
		end
	end

	return highlight_cache.pending
end

-- Helper function to get status icons
local function get_status_icon(status)
	if status == "done" then
		return config.options.formatting.done.icon
	elseif status == "in_progress" then
		return config.options.formatting.in_progress.icon
	else
		return config.options.formatting.pending.icon
	end
end

--------------------------------------------------
-- Todo Management Functions
--------------------------------------------------

-- Handles editing of existing todos
edit_todo = auto_render(function()
	local current_line = vim.api.nvim_win_get_cursor(win_id)[1]
	local todo_index = line_to_todo[current_line]
	if not todo_index then
		notify.warn("No todo selected to edit")
		return
	end
	local line_content = vim.api.nvim_buf_get_lines(buf_id, current_line - 1, current_line, false)[1]
	
	-- Use icon helper
	local all_icons = get_status_icon("done") .. get_status_icon("pending") .. get_status_icon("in_progress")
	if not line_content:match("%s+[" .. all_icons .. "]") then
		return
	end
	
	safe_input({ prompt = "Edit to-do: ", default = state.todos[todo_index].text }, function(input)
		if not input or input == "" then
			return
		end
		if config.options.backend == "todoist" then
			local api = require("dooing.api.todoist")
			local task = state.todos[todo_index]
			if api.update_task(task.id, { content = input }) then
				state.load_todos()
				-- Auto-render will handle this
			else
				notify.error("Failed to update remote task")
				return
			end
		else
			state.todos[todo_index].text = input
			state.save_todos()
			-- Auto-render will handle this
		end
		-- Keep cursor on the edited todo after re-render
		for display_line, idx in pairs(line_to_todo) do
			if idx == todo_index then
				vim.api.nvim_win_set_cursor(win_id, { display_line, 0 })
				break
			end
		end
		notify.success("Todo updated successfully")
	end)
end)

-- Handles editing priorities
edit_priorities = auto_render(function()
	local cursor = vim.api.nvim_win_get_cursor(win_id)
	local todo_index = cursor[1] - 1
	local line_content = vim.api.nvim_buf_get_lines(buf_id, todo_index, todo_index + 1, false)[1]
	local done_icon = config.options.formatting.done.icon
	local pending_icon = config.options.formatting.pending.icon
	local in_progress_icon = config.options.formatting.in_progress.icon

	if line_content:match("%s+[" .. done_icon .. pending_icon .. in_progress_icon .. "]") then
		if state.active_filter then
			local visible_index = 0
			for i, todo in ipairs(state.todos) do
				if todo.text:match("#" .. state.active_filter) then
					visible_index = visible_index + 1
					if visible_index == todo_index - 2 then
						todo_index = i
						break
					end
				end
			end
		end

		-- Check if priorities are configured
		if config.options.priorities and #config.options.priorities > 0 then
			local priorities = config.options.priorities
			local priority_options = {}
			local selected_priorities = {}
			local current_todo = state.todos[todo_index]

			-- Pre-select existing priorities
			for i, priority in ipairs(priorities) do
				local is_selected = false
				if current_todo.priorities then
					for _, existing_priority in ipairs(current_todo.priorities) do
						if existing_priority == priority.name then
							is_selected = true
							selected_priorities[i] = true
							break
						end
					end
				end
				priority_options[i] = string.format("[%s] %s", is_selected and "x" or " ", priority.name)
			end

			-- Create buffer for priority selection
			local select_buf = vim.api.nvim_create_buf(false, true)
			local ui = vim.api.nvim_list_uis()[1]
			local width = 40
			local height = #priority_options + 2
			local row = math.floor((ui.height - height) / 2)
			local col = math.floor((ui.width - width) / 2)

			-- Store keymaps for cleanup
			local keymaps = {
				config.options.keymaps.toggle_priority,
				"<CR>",
				"q",
				"<Esc>",
			}

			local select_win = vim.api.nvim_open_win(select_buf, true, {
				relative = "editor",
				width = width,
				height = height,
				row = row,
				col = col,
				style = "minimal",
				border = "rounded",
				title = " Edit Priorities ",
				title_pos = "center",
				footer = string.format(" %s: toggle | <Enter>: confirm ", config.options.keymaps.toggle_priority),
				footer_pos = "center",
			})

			-- Set buffer content
			vim.api.nvim_buf_set_lines(select_buf, 0, -1, false, priority_options)
			vim.api.nvim_buf_set_option(select_buf, "modifiable", false)

			-- Add keymaps for selection
			vim.keymap.set("n", config.options.keymaps.toggle_priority, function()
				if not (select_win and vim.api.nvim_win_is_valid(select_win)) then
					return
				end

				local cursor = vim.api.nvim_win_get_cursor(select_win)
				local line_num = cursor[1]
				local current_line = vim.api.nvim_buf_get_lines(select_buf, line_num - 1, line_num, false)[1]

				vim.api.nvim_buf_set_option(select_buf, "modifiable", true)
				if current_line:match("^%[%s%]") then
					-- Select item
					local new_line = current_line:gsub("^%[%s%]", "[x]")
					selected_priorities[line_num] = true
					vim.api.nvim_buf_set_lines(select_buf, line_num - 1, line_num, false, { new_line })
				else
					-- Deselect item
					local new_line = current_line:gsub("^%[x%]", "[ ]")
					selected_priorities[line_num] = nil
					vim.api.nvim_buf_set_lines(select_buf, line_num - 1, line_num, false, { new_line })
				end
				vim.api.nvim_buf_set_option(select_buf, "modifiable", false)
			end, { buffer = select_buf, nowait = true })

			-- Add keymap for confirmation
			vim.keymap.set("n", "<CR>", function()
				if not (select_win and vim.api.nvim_win_is_valid(select_win)) then
					return
				end

				local selected_priority_names = {}
				for idx, _ in pairs(selected_priorities) do
					local priority = config.options.priorities[idx]
					if priority then
						table.insert(selected_priority_names, priority.name)
					end
				end

				-- Clean up resources before proceeding
				cleanup_priority_selection(select_buf, select_win, keymaps)

				-- Update todo priorities
				state.todos[todo_index].priorities = #selected_priority_names > 0 and selected_priority_names or nil
				state.save_todos()
				-- Auto-render will handle this
			end, { buffer = select_buf, nowait = true })

			-- Add escape/quit keymaps
			local function close_window()
				cleanup_priority_selection(select_buf, select_win, keymaps)
			end

			vim.keymap.set("n", "q", close_window, { buffer = select_buf, nowait = true })
			vim.keymap.set("n", "<Esc>", close_window, { buffer = select_buf, nowait = true })

			-- Add autocmd for cleanup when leaving buffer
			vim.api.nvim_create_autocmd("BufLeave", {
				buffer = select_buf,
				callback = function()
					cleanup_priority_selection(select_buf, select_win, keymaps)
					return true
				end,
				once = true,
			})
		end
	end
end)

--------------------------------------------------
-- Core Window Management
--------------------------------------------------

-- Creates and manages the help window
create_help_window = function()
	if help_win_id and vim.api.nvim_win_is_valid(help_win_id) then
		vim.api.nvim_win_close(help_win_id, true)
		help_win_id = nil
		help_buf_id = nil
		return
	end

	help_buf_id = vim.api.nvim_create_buf(false, true)

	local width = 50
	local height = 40
	local ui = vim.api.nvim_list_uis()[1]
	local col = math.floor((ui.width - width) / 2) + width + 2
	local row = math.floor((ui.height - height) / 2)

	help_win_id = vim.api.nvim_open_win(help_buf_id, false, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " help ",
		title_pos = "center",
		zindex = 100,
	})

	local keys = config.options.keymaps
	local help_content = {
		" Main window:",
		string.format(" %-12s - Add new todo", keys.new_todo),
		string.format(" %-12s - Toggle todo status", keys.toggle_todo),
		string.format(" %-12s - Complete todo directly", keys.complete_todo),
		string.format(" %-12s - Cancel in-progress todo", keys.cancel_in_progress),
		string.format(" %-12s - Delete current todo", keys.delete_todo),
		string.format(" %-12s - Delete all completed todos", keys.delete_completed),
		string.format(" %-12s - Undo deletion", keys.undo_delete),
		string.format(" %-12s - Close window", keys.close_window),
		string.format(" %-12s - Refresh todo list", keys.refresh_todos),
		"",
		" Editing:",
		string.format(" %-12s - Edit todo item", keys.edit_todo),
		string.format(" %-12s - Edit todo priorities", keys.edit_priorities),
		string.format(" %-12s - Open todo scratchpad", keys.open_todo_scratchpad),
		"",
		" Due dates & Time:",
		string.format(" %-12s - Add due date", keys.add_due_date),
		string.format(" %-12s - Remove due date", keys.remove_due_date),
		string.format(" %-12s - Add time estimation", keys.add_time_estimation),
		string.format(" %-12s - Remove time estimation", keys.remove_time_estimation),
		"",
		" Organization:",
		string.format(" %-12s - Toggle tags window", keys.toggle_tags),
		string.format(" %-12s - Clear active tag filter", keys.clear_filter),
		string.format(" %-12s - Search todos", keys.search_todos),
		string.format(" %-12s - Share todos (QR server)", keys.share_todos),
		"",
		" Import/Export:",
		string.format(" %-12s - Import todos", keys.import_todos),
		string.format(" %-12s - Export todos", keys.export_todos),
		string.format(" %-12s - Remove duplicates", keys.remove_duplicates),
		"",
		" Other:",
		string.format(" %-12s - Toggle this help window", keys.toggle_help),
		"",
		" Tags window:",
		string.format(" %-12s - Filter by tag", "<CR>"),
		string.format(" %-12s - Edit tag", keys.edit_tag),
		string.format(" %-12s - Delete tag", keys.delete_tag),
		string.format(" %-12s - Close window", keys.close_window),
		"",
		" Priority selection:",
		string.format(" %-12s - Toggle priority", keys.toggle_priority),
		string.format(" %-12s - Confirm selection", "<CR>"),
		string.format(" %-12s - Cancel", "q/<Esc>"),
		"",
		" Calendar window:",
		string.format(" %-12s - Previous day", config.options.calendar.keymaps.previous_day),
		string.format(" %-12s - Next day", config.options.calendar.keymaps.next_day),
		string.format(" %-12s - Previous week", config.options.calendar.keymaps.previous_week),
		string.format(" %-12s - Next week", config.options.calendar.keymaps.next_week),
		string.format(" %-12s - Previous month", config.options.calendar.keymaps.previous_month),
		string.format(" %-12s - Next month", config.options.calendar.keymaps.next_month),
		string.format(" %-12s - Select date", config.options.calendar.keymaps.select_day),
		string.format(" %-12s - Close calendar", config.options.calendar.keymaps.close_calendar),
		"",
	}

	vim.api.nvim_buf_set_lines(help_buf_id, 0, -1, false, help_content)
	vim.api.nvim_buf_set_option(help_buf_id, "modifiable", false)
	vim.api.nvim_buf_set_option(help_buf_id, "buftype", "nofile")

	for i = 0, #help_content - 1 do
		vim.api.nvim_buf_add_highlight(help_buf_id, ns_id, "DooingHelpText", i, 0, -1)
	end

	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = help_buf_id,
		callback = function()
			if help_win_id and vim.api.nvim_win_is_valid(help_win_id) then
				vim.api.nvim_win_close(help_win_id, true)
				help_win_id = nil
				help_buf_id = nil
			end
			return true
		end,
	})

	local function close_help()
		if help_win_id and vim.api.nvim_win_is_valid(help_win_id) then
			vim.api.nvim_win_close(help_win_id, true)
			help_win_id = nil
			help_buf_id = nil
		end
	end

	vim.keymap.set("n", config.options.keymaps.close_window, close_help, { buffer = help_buf_id, nowait = true })
	vim.keymap.set("n", config.options.keymaps.toggle_help, close_help, { buffer = help_buf_id, nowait = true })
end

local prompt_export = function()
	local default_path = vim.fn.expand("~/todos.json")

	safe_input({
		prompt = "Export todos to file: ",
		default = default_path,
	}, function(file_path)
		if not file_path or file_path == "" then
			notify.info("Export cancelled")
			return
		end

		-- expand ~ to full home directory path
		file_path = vim.fn.expand(file_path)

		local success, message = state.export_todos(file_path)
		if success then
			notify.success(message)
		else
			notify.error(message)
		end
	end)
end

local prompt_import = auto_render(function(callback)
	local default_path = vim.fn.expand("~/todos.json")

	safe_input({
		prompt = "Import todos from file: ",
		default = default_path,
	}, function(file_path)
		if not file_path or file_path == "" then
			vim.notify("Import cancelled", vim.log.levels.INFO)
			return
		end

		-- expand ~ to full home directory path
		file_path = vim.fn.expand(file_path)

		local success, message = state.import_todos(file_path)
		if success then
			notify.success(message)
			if callback then
				callback()
			end
			-- Auto-render will handle this
		else
			notify.error(message)
		end
	end)
end)

-- Creates and manages the tags window
create_tag_window = auto_render(function()
	if tag_win_id and vim.api.nvim_win_is_valid(tag_win_id) then
		vim.api.nvim_win_close(tag_win_id, true)
		tag_win_id = nil
		tag_buf_id = nil
		return
	end

	tag_buf_id = vim.api.nvim_create_buf(false, true)

	local width = 30
	local height = 10
	local ui = vim.api.nvim_list_uis()[1]
	local main_width = 40
	local main_col = math.floor((ui.width - main_width) / 2)
	local col = main_col - width - 2
	local row = math.floor((ui.height - height) / 2)

	tag_win_id = vim.api.nvim_open_win(tag_buf_id, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " tags ",
		title_pos = "center",
	})

	local tags = state.get_all_tags()
	if #tags == 0 then
		tags = { "No tags found" }
	end

	vim.api.nvim_buf_set_lines(tag_buf_id, 0, -1, false, tags)

	vim.api.nvim_buf_set_option(tag_buf_id, "modifiable", true)

	vim.keymap.set("n", "<CR>", function()
		local cursor = vim.api.nvim_win_get_cursor(tag_win_id)
		local tag = vim.api.nvim_buf_get_lines(tag_buf_id, cursor[1] - 1, cursor[1], false)[1]
		if tag ~= "No tags found" then
			state.set_filter(tag)
			vim.api.nvim_win_close(tag_win_id, true)
			tag_win_id = nil
			tag_buf_id = nil
			-- Auto-render will handle this
		end
	end, { buffer = tag_buf_id })

	vim.keymap.set("n", config.options.keymaps.edit_tag, function()
		local cursor = vim.api.nvim_win_get_cursor(tag_win_id)
		local old_tag = vim.api.nvim_buf_get_lines(tag_buf_id, cursor[1] - 1, cursor[1], false)[1]
		if old_tag ~= "No tags found" then
			safe_input({ prompt = "Edit tag: ", default = old_tag }, function(new_tag)
				if new_tag and new_tag ~= "" and new_tag ~= old_tag then
					state.rename_tag(old_tag, new_tag)
					local tags = state.get_all_tags()
					vim.api.nvim_buf_set_lines(tag_buf_id, 0, -1, false, tags)
					-- Auto-render will handle this
				end
			end)
		end
	end, { buffer = tag_buf_id })

	vim.keymap.set("n", config.options.keymaps.delete_tag, function()
		local cursor = vim.api.nvim_win_get_cursor(tag_win_id)
		local tag = vim.api.nvim_buf_get_lines(tag_buf_id, cursor[1] - 1, cursor[1], false)[1]
		if tag ~= "No tags found" then
			state.delete_tag(tag)
			local tags = state.get_all_tags()
			if #tags == 0 then
				tags = { "No tags found" }
			end
			vim.api.nvim_buf_set_lines(tag_buf_id, 0, -1, false, tags)
			-- Auto-render will handle this
		end
	end, { buffer = tag_buf_id })

	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(tag_win_id, true)
		tag_win_id = nil
		tag_buf_id = nil
		vim.api.nvim_set_current_win(win_id)
	end, { buffer = tag_buf_id })
end)

-- Handle search queries
local function handle_search_query(query)
	if not query or query == "" then
		if search_win_id and vim.api.nvim_win_is_valid(search_win_id) then
			vim.api.nvim_win_close(search_win_id, true)
			vim.api.nvim_set_current_win(win_id)
			search_win_id = nil
			search_buf_id = nil
		end
		return
	end

	local done_icon = config.options.formatting.done.icon
	local pending_icon = config.options.formatting.pending.icon
	local in_progress_icon = config.options.formatting.in_progress.icon

	-- Prepare the search results
	local results = state.search_todos(query)
	vim.api.nvim_buf_set_option(search_buf_id, "modifiable", true)
	local lines = { "Search Results for: " .. query, "" }
	local valid_lines = {} -- Store valid todo lines
	if #results > 0 then
		for _, result in ipairs(results) do
			local icon
			if result.todo.status == "done" then
				icon = done_icon
			elseif result.todo.status == "in_progress" then
				icon = in_progress_icon
			else
				icon = pending_icon
			end
			local line = string.format("  %s %s", icon, result.todo.text)
			table.insert(lines, line)
			table.insert(valid_lines, { line_index = #lines, result = result })
		end
	else
		table.insert(lines, "  No results found")
		vim.api.nvim_set_current_win(win_id)
	end

	-- Add search results to window
	vim.api.nvim_buf_set_lines(search_buf_id, 0, -1, false, lines)

	-- After adding search results, make it unmodifiable
	vim.api.nvim_buf_set_option(search_buf_id, "modifiable", false)

	-- Highlight todos on search results
	for i, line in ipairs(lines) do
		if line:match("%s+[" .. done_icon .. pending_icon .. in_progress_icon .. "]") then
			local hl_group = line:match(done_icon) and "DooingDone" or "DooingPending"
			vim.api.nvim_buf_add_highlight(search_buf_id, ns_id, hl_group, i - 1, 0, -1)
			for tag in line:gmatch("#(%w+)") do
				local start_idx = line:find("#" .. tag) - 1
				vim.api.nvim_buf_add_highlight(search_buf_id, ns_id, "Type", i - 1, start_idx, start_idx + #tag + 1)
			end
		elseif line:match("Search Results") then
			vim.api.nvim_buf_add_highlight(search_buf_id, ns_id, "WarningMsg", i - 1, 0, -1)
		end
	end

	-- Close search window
	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(search_win_id, true)
		search_win_id = nil
		search_buf_id = nil
		if win_id and vim.api.nvim_win_is_valid(win_id) then
			vim.api.nvim_set_current_win(win_id)
		end
	end, { buffer = search_buf_id, nowait = true })

	-- Jump to todo in main window
	vim.keymap.set("n", "<CR>", function()
		local current_line = vim.api.nvim_win_get_cursor(search_win_id)[1]
		local matched_result
		for _, item in ipairs(valid_lines) do
			if item.line_index == current_line then
				matched_result = item.result
				break
			end
		end
		if matched_result then
			vim.api.nvim_win_close(search_win_id, true)
			search_win_id = nil
			search_buf_id = nil
			vim.api.nvim_set_current_win(win_id)
			-- Jump to the correct display line using the line_to_todo map
			local target_line
			for display_line, t_idx in pairs(line_to_todo) do
				if t_idx == matched_result.lnum then
					target_line = display_line
					break
				end
			end
			if target_line then
				vim.api.nvim_win_set_cursor(win_id, { target_line, 3 })
			end
		end
	end, { buffer = search_buf_id, nowait = true })
end

-- Search for todos
local function create_search_window()
	-- If search window exists and is valid, focus on the existing window and return
	if search_win_id and vim.api.nvim_win_is_valid(search_win_id) then
		vim.api.nvim_set_current_win(search_win_id)
		safe_input({ prompt = "Search todos: " }, function(query)
			handle_search_query(query)
		end)
		return
	end

	-- If search window exists but is not valid, reset IDs
	if search_win_id and vim.api.nvim_win_is_valid(search_win_id) then
		search_win_id = nil
		search_buf_id = nil
	end

	-- Create search results buffer
	search_buf_id = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(search_buf_id, "buflisted", true)
	vim.api.nvim_buf_set_option(search_buf_id, "modifiable", false)
	vim.api.nvim_buf_set_option(search_buf_id, "filetype", "todo_search")
	local width = 40
	local height = 10
	local ui = vim.api.nvim_list_uis()[1]
	local main_width = 40
	local main_col = math.floor((ui.width - main_width) / 2)
	local col = main_col - width - 2
	local row = math.floor((ui.height - height) / 2)
	search_win_id = vim.api.nvim_open_win(search_buf_id, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " Search Todos ",
		title_pos = "center",
	})

	-- Create search query pane
	safe_input({ prompt = "Search todos: " }, function(query)
		handle_search_query(query)
	end)

	-- Close the search window if main window is closed
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win_id),
		callback = function()
			if search_win_id and vim.api.nvim_win_is_valid(search_win_id) then
				vim.api.nvim_win_close(search_win_id, true)
				search_win_id = nil
				search_buf_id = nil
			end
		end,
	})
end

-- Parse time estimation string (e.g., "2h", "1d", "0.5w")
function M.parse_time_estimation(time_str)
	local number, unit = time_str:match("^(%d+%.?%d*)([mhdw])$")

	if not (number and unit) then
		return nil,
			"Invalid format. Use number followed by m (minutes), h (hours), d (days), or w (weeks). E.g., 30m, 2h, 1d, 0.5w"
	end

	local hours = tonumber(number)
	if not hours then
		return nil, "Invalid number format"
	end

	-- Convert to hours
	if unit == "m" then
		hours = hours / 60
	elseif unit == "d" then
		hours = hours * 24
	elseif unit == "w" then
		hours = hours * 24 * 7
	end

	return hours
end

-- Add estimated completion time to todo
local add_time_estimation = auto_render(function()
	local current_line = vim.api.nvim_win_get_cursor(win_id)[1]
	local todo_index = line_to_todo[current_line]
	if not todo_index then
		notify.warn("No todo selected for time estimation")
		return
	end

	safe_input({
		prompt = "Estimated completion time (e.g., 15m, 2h, 1d, 0.5w): ",
		default = "",
	}, function(input)
		if input and input ~= "" then
			local hours, err = M.parse_time_estimation(input)
			if hours then
				state.todos[todo_index].estimated_hours = hours
				state.save_todos()
				notify.success("Time estimation added successfully")
				-- Auto-render will handle the UI update
			else
				notify.error("Error adding time estimation: " .. (err or "Unknown error"))
			end
		end
	end)
end)

-- Remove estimated completion time from todo
local remove_time_estimation = auto_render(function()
	local current_line = vim.api.nvim_win_get_cursor(win_id)[1]
	local todo_index = line_to_todo[current_line]
	if not todo_index then
		notify.warn("No todo selected for removing time estimation")
		return
	end

	if state.todos[todo_index] then
		state.todos[todo_index].estimated_hours = nil
		state.save_todos()
		notify.success("Time estimation removed successfully")
		-- Auto-render will handle the UI update
	else
		notify.error("Error removing time estimation")
	end
end)

-- Add due date to to-do in the format MM/DD/YYYY
local add_due_date = auto_render(function()
	local current_line = vim.api.nvim_win_get_cursor(win_id)[1]
	local todo_index = line_to_todo[current_line]
	if not todo_index then
		notify.warn("No todo selected for due date")
		return
	end

	calendar.create(function(date_str)
		if date_str and date_str ~= "" then
			local success, err = state.add_due_date(todo_index, date_str)

			if success then
				-- Auto-render will handle the UI update
				notify.success("Due date added successfully")
			else
				notify.error("Error adding due date: " .. (err or "Unknown error"))
			end
		end
	end, { language = "en" })
end)

-- Remove due date from to-do
local remove_due_date = auto_render(function()
	local current_line = vim.api.nvim_win_get_cursor(win_id)[1]
	local todo_index = line_to_todo[current_line]
	if not todo_index then
		notify.warn("No todo selected for removing due date")
		return
	end

	local success = state.remove_due_date(todo_index)

	if success then
		-- Auto-render will handle the UI update
		notify.success("Due date removed successfully")
	else
		notify.error("Error removing due date")
	end
end)

local function open_todo_scratchpad()
	local cursor = vim.api.nvim_win_get_cursor(win_id)
	local todo_index = cursor[1] - 1
	local todo = state.todos[todo_index]

	if not todo then
		vim.notify("No todo selected", vim.log.levels.WARN)
		return
	end

	if todo.notes == nil then
		todo.notes = ""
	end

	local function is_valid_filetype(filetype)
		local syntax_file = vim.fn.globpath(vim.o.runtimepath, "syntax/" .. filetype .. ".vim")
		return syntax_file ~= ""
	end

	local scratch_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(scratch_buf, "buftype", "acwrite")
	vim.api.nvim_buf_set_option(scratch_buf, "swapfile", false)

	local syntax_highlight = config.options.scratchpad.syntax_highlight
	if not is_valid_filetype(syntax_highlight) then
		vim.notify(
			"Invalid scratchpad syntax highlight '" .. syntax_highlight .. "'. Using default 'markdown'.",
			vim.log.levels.WARN
		)
		syntax_highlight = "markdown"
	end

	vim.api.nvim_buf_set_option(scratch_buf, "filetype", syntax_highlight)

	local ui = vim.api.nvim_list_uis()[1]
	local width = math.floor(ui.width * 0.6)
	local height = math.floor(ui.height * 0.6)
	local row = math.floor((ui.height - height) / 2)
	local col = math.floor((ui.width - width) / 2)

	local scratch_win = vim.api.nvim_open_win(scratch_buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		title = " Scratchpad ",
		title_pos = "center",
	})

	local initial_notes = todo.notes or ""
	vim.api.nvim_buf_set_lines(scratch_buf, 0, -1, false, vim.split(initial_notes, "\n"))

	local function close_notes()
		if vim.api.nvim_win_is_valid(scratch_win) then
			vim.api.nvim_win_close(scratch_win, true)
		end

		if vim.api.nvim_buf_is_valid(scratch_buf) then
			vim.api.nvim_buf_delete(scratch_buf, { force = true })
		end
	end

	local function save_notes()
		local lines = vim.api.nvim_buf_get_lines(scratch_buf, 0, -1, false)
		local new_notes = table.concat(lines, "\n")

		if new_notes ~= initial_notes then
			todo.notes = new_notes
			state.save_todos()
			vim.notify("Notes saved", vim.log.levels.INFO)
		end

		close_notes()
	end

	vim.api.nvim_create_autocmd("WinLeave", {
		buffer = scratch_buf,
		callback = close_notes,
	})

	vim.keymap.set("n", "<CR>", save_notes, { buffer = scratch_buf })
	vim.keymap.set("n", "<Esc>", close_notes, { buffer = scratch_buf })
end

-- Creates and configures the small keys window
local function create_small_keys_window(main_win_pos)
	if not config.options.quick_keys then
		return nil
	end

	local keys = config.options.keymaps
	local small_buf = vim.api.nvim_create_buf(false, true)
	local width = config.options.window.width

	-- Define two separate line arrays for each column
	local lines_1 = {
		"",
		string.format("  %-6s - New todo", keys.new_todo),
		string.format("  %-6s - Toggle todo", keys.toggle_todo),
		string.format("  %-6s - Delete todo", keys.delete_todo),
		string.format("  %-6s - Undo delete", keys.undo_delete),
		string.format("  %-6s - Add due date", keys.add_due_date),
		"",
	}

	local lines_2 = {
		"",
		string.format("  %-6s - Add time", keys.add_time_estimation),
		string.format("  %-6s - Tags", keys.toggle_tags),
		string.format("  %-6s - Search", keys.search_todos),
		string.format("  %-6s - Import", keys.import_todos),
		string.format("  %-6s - Export", keys.export_todos),
		"",
	}

	-- Calculate middle point for even spacing
	local mid_point = math.floor(width / 2)
	local padding = 2

	-- Create combined lines with centered columns
	local lines = {}
	for i = 1, #lines_1 do
		local line1 = lines_1[i] .. string.rep(" ", mid_point - #lines_1[i] - padding)
		local line2 = lines_2[i] or ""
		lines[i] = line1 .. line2
	end

	vim.api.nvim_buf_set_lines(small_buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(small_buf, "modifiable", false)
	vim.api.nvim_buf_set_option(small_buf, "buftype", "nofile")

	-- Position it under the main window
	local row = main_win_pos.row + main_win_pos.height + 1

	local small_win = vim.api.nvim_open_win(small_buf, false, {
		relative = "editor",
		row = row,
		col = main_win_pos.col,
		width = width,
		height = #lines,
		style = "minimal",
		border = "rounded",
		focusable = false,
		zindex = 45,
		footer = " Quick Keys ",
		footer_pos = "center",
	})

	-- Add highlights
	local ns = vim.api.nvim_create_namespace("dooing_small_keys")

	-- Highlight title
	vim.api.nvim_buf_add_highlight(small_buf, ns, "DooingQuickTitle", 0, 0, -1)

	-- Highlight each key and description in both columns
	for i = 1, #lines - 1 do
		if i > 0 then
			-- Left column
			vim.api.nvim_buf_add_highlight(small_buf, ns, "DooingQuickKey", i, 2, 3) -- Key
			vim.api.nvim_buf_add_highlight(small_buf, ns, "DooingQuickDesc", i, 5, mid_point - padding) -- Description

			-- Right column
			local right_key_start = mid_point
			vim.api.nvim_buf_add_highlight(small_buf, ns, "DooingQuickKey", i, right_key_start + 2, right_key_start + 3) -- Key
			vim.api.nvim_buf_add_highlight(small_buf, ns, "DooingQuickDesc", i, right_key_start + 5, -1) -- Description
		end
	end

	return small_win
end

-- Creates and configures the main todo window
local function create_window()
	local ui = vim.api.nvim_list_uis()[1]
	local width = config.options.window.width
	local height = config.options.window.height
	local position = config.options.window.position or "right"
	local padding = 2 -- padding from screen edges

	-- Calculate position based on config
	local col, row
	if position == "right" then
		col = ui.width - width - padding
		row = math.floor((ui.height - height) / 2)
	elseif position == "left" then
		col = padding
		row = math.floor((ui.height - height) / 2)
	elseif position == "top" then
		col = math.floor((ui.width - width) / 2)
		row = padding
	elseif position == "bottom" then
		col = math.floor((ui.width - width) / 2)
		row = ui.height - height - padding
	elseif position == "top-right" then
		col = ui.width - width - padding
		row = padding
	elseif position == "top-left" then
		col = padding
		row = padding
	elseif position == "bottom-right" then
		col = ui.width - width - padding
		row = ui.height - height - padding
	elseif position == "bottom-left" then
		col = padding
		row = ui.height - height - padding
	else -- center or invalid position
		col = math.floor((ui.width - width) / 2)
		row = math.floor((ui.height - height) / 2)
	end

	setup_highlights()

	buf_id = vim.api.nvim_create_buf(false, true)

	win_id = vim.api.nvim_open_win(buf_id, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " to-dos ",
		title_pos = "center",
		footer = " [?] for help ",
		footer_pos = "center",
	})

	-- Create small keys window with main window position
	local small_win = create_small_keys_window({
		row = row,
		col = col,
		width = width,
		height = height,
	})

	-- Close small window when main window is closed
	if small_win then
		vim.api.nvim_create_autocmd("WinClosed", {
			pattern = tostring(win_id),
			callback = function()
				if vim.api.nvim_win_is_valid(small_win) then
					vim.api.nvim_win_close(small_win, true)
				end
			end,
		})
	end

	vim.api.nvim_win_set_option(win_id, "wrap", true)
	vim.api.nvim_win_set_option(win_id, "linebreak", true)
	vim.api.nvim_win_set_option(win_id, "breakindent", true)
	vim.api.nvim_win_set_option(win_id, "breakindentopt", "shift:2")
	vim.api.nvim_win_set_option(win_id, "showbreak", " ")

	-- Setup keymaps
	local function setup_keymap(key_option, callback)
		if config.options.keymaps[key_option] then
			print("DEBUG: Setting up keymap " .. key_option .. " = " .. config.options.keymaps[key_option])
			vim.keymap.set("n", config.options.keymaps[key_option], callback, { buffer = buf_id, nowait = true })
		else
			print("DEBUG: No keymap found for " .. key_option)
		end
	end

	setup_keymap("share_todos", function()
		server.start_qr_server()
	end)

	-- Main actions
	setup_keymap("new_todo", M.new_todo)
	setup_keymap("toggle_todo", M.toggle_todo)
	setup_keymap("complete_todo", M.complete_todo)
	setup_keymap("cancel_in_progress", M.cancel_in_progress)
	setup_keymap("delete_todo", M.delete_todo)
	setup_keymap("delete_completed", M.delete_completed)
	setup_keymap("close_window", M.close_window)
	setup_keymap("refresh_todos", M.reload_todos)
	
	-- Debug: Add test keymaps to verify keybinding works
	vim.keymap.set("n", "Z", function()
		print("DEBUG: Z key pressed - calling M.complete_todo directly")
		M.complete_todo()
	end, { buffer = buf_id, nowait = true })
	
	-- Debug: Add explicit X keymap with debugging
	vim.keymap.set("n", "X", function()
		print("DEBUG: X key pressed explicitly!")
		M.complete_todo()
	end, { buffer = buf_id, nowait = true, desc = "Complete todo (debug)" })
	setup_keymap("undo_delete", auto_render(function()
		if state.undo_delete() then
			notify.success("Todo restored")
		end
	end))

	-- Window and view management
	setup_keymap("toggle_help", create_help_window)
	setup_keymap("toggle_tags", create_tag_window)
	setup_keymap("clear_filter", auto_render(function()
		state.set_filter(nil)
	end))

	-- Todo editing and management
	setup_keymap("edit_todo", edit_todo)
	setup_keymap("edit_priorities", edit_priorities)
	setup_keymap("add_due_date", add_due_date)
	setup_keymap("remove_due_date", remove_due_date)
	setup_keymap("add_time_estimation", add_time_estimation)
	setup_keymap("remove_time_estimation", remove_time_estimation)
	setup_keymap("open_todo_scratchpad", open_todo_scratchpad)

	-- Import/Export functionality
	setup_keymap("import_todos", prompt_import)
	setup_keymap("export_todos", prompt_export)
	setup_keymap("remove_duplicates", M.remove_duplicates)
	setup_keymap("search_todos", create_search_window)
end

-- Public Interface
--------------------------------------------------

-- Helper function to format relative time
local function format_relative_time(timestamp)
	local now = os.time()
	local diff = now - timestamp

	-- Less than a minute
	if diff < 60 then
		return "just now"
	end
	-- Less than an hour
	if diff < 3600 then
		local mins = math.floor(diff / 60)
		return mins .. "m ago"
	end
	-- Less than a day
	if diff < 86400 then
		local hours = math.floor(diff / 3600)
		return hours .. "h ago"
	end
	-- Less than a week
	if diff < 604800 then
		local days = math.floor(diff / 86400)
		return days .. "d ago"
	end
	-- More than a week
	local weeks = math.floor(diff / 604800)
	return weeks .. "w ago"
end

-- Helper function for formatting based on format config
local function render_todo(todo, formatting, lang, notes_icon)
	if not formatting or not formatting.pending or not formatting.done then
		error("Invalid 'formatting' configuration in config.lua")
	end

	local components = {}

	-- Get config formatting based on status
	local format
	if todo.status == "done" then
		format = formatting.done.format
	elseif todo.status == "in_progress" then
		format = formatting.in_progress.format
	else
		format = formatting.pending.format
	end
	
	if not format then
		format = { "notes_icon", "icon", "text", "ect", "relative_time" }
	end

	-- Breakdown config format and get dynamic text based on other configs
	for _, part in ipairs(format) do
		if part == "icon" then
			local icon
			if todo.status == "done" then
				icon = formatting.done.icon
			elseif todo.status == "in_progress" then
				icon = formatting.in_progress.icon
			else
				icon = formatting.pending.icon
			end
			table.insert(components, icon)
		elseif part == "text" then
			table.insert(components, (todo.text:gsub("\n", " ")))
		elseif part == "notes_icon" then
			table.insert(components, notes_icon)
		elseif part == "relative_time" then
			if todo.created_at and config.options.timestamp and config.options.timestamp.enabled then
				table.insert(components, "@" .. format_relative_time(todo.created_at))
			end
		elseif part == "due_date" then
			-- Format due date if exists
			if todo.due_at then
				local date = os.date("*t", todo.due_at)
				local month = calendar.MONTH_NAMES[lang][date.month]
				local formatted_date
				if lang == "pt" or lang == "es" then
					formatted_date = string.format("%d de %s de %d", date.day, month, date.year)
				elseif lang == "fr" then
					formatted_date = string.format("%d %s %d", date.day, month, date.year)
				elseif lang == "de" or lang == "it" then
					formatted_date = string.format("%d %s %d", date.day, month, date.year)
				elseif lang == "jp" then
					formatted_date = string.format("%d年%s%d日", date.year, month, date.day)
				else
					formatted_date = string.format("%s %d, %d", month, date.day, date.year)
				end
				local due_date_str
				if config.options.calendar.icon ~= "" then
					due_date_str = "[" .. config.options.calendar.icon .. " " .. formatted_date .. "]"
				else
					due_date_str = "[" .. formatted_date .. "]"
				end
				local current_time = os.time()
				if todo.status ~= "done" and todo.due_at < current_time then
					due_date_str = due_date_str .. " [OVERDUE]"
				end
				table.insert(components, due_date_str)
			end
		elseif part == "priority" then
			local score = state.get_priority_score(todo)
			table.insert(components, string.format("Priority: %d", score))
		elseif part == "ect" then
			if todo.estimated_hours then
				local time_str
				if todo.estimated_hours >= 168 then -- more than a week
					local weeks = todo.estimated_hours / 168
					time_str = string.format("[≈ %gw]", weeks)
				elseif todo.estimated_hours >= 24 then -- more than a day
					local days = todo.estimated_hours / 24
					time_str = string.format("[≈ %gd]", days)
				elseif todo.estimated_hours >= 1 then -- more than an hour
					time_str = string.format("[≈ %gh]", todo.estimated_hours)
				else -- less than an hour
					time_str = string.format("[≈ %gm]", todo.estimated_hours * 60)
				end
				table.insert(components, time_str)
			end
		end
	end

	-- Join the components into a single string
	return table.concat(components, " ")
end

-- Main function for todos rendering
function M.render_todos()
	if not buf_id then
		return
	end
	
	print("DEBUG: render_todos - total todos: " .. #state.todos)
	-- Debug: show status of first few todos
	for i = 1, math.min(3, #state.todos) do
		local todo = state.todos[i]
		if todo then
			print("DEBUG: Todo " .. i .. ": " .. (todo.text or "nil") .. " - status: " .. (todo.status or "nil"))
		end
	end

	-- Create the buffer
	vim.api.nvim_buf_set_option(buf_id, "modifiable", true)
	vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)
	local lines = { "" }

	-- Sort todos and get config
	state.sort_todos()
	local lang = calendar and calendar.get_language()
	local formatting = config.options.formatting
	local done_icon = config.options.formatting.done.icon
	local pending_icon = config.options.formatting.pending.icon
	local notes_icon = config.options.notes.icon
	local tmp_notes_icon = ""
	local in_progress_icon = config.options.formatting.in_progress.icon

		local groups = {}
		local order = {}
		-- Collect to-do indices grouped by due month
		for idx, todo in ipairs(state.todos) do
			if not state.active_filter or todo.text:match("#" .. state.active_filter) then
				local label
				if todo.due_at then
					local dt = os.date("*t", todo.due_at)
					label = calendar.MONTH_NAMES[lang][dt.month] .. " " .. dt.year
				else
					label = "No due date"
				end
				if not groups[label] then
					groups[label] = {}
					table.insert(order, label)
				end
				table.insert(groups[label], idx)
			end
		end
		line_to_todo = {}
		for _, label in ipairs(order) do
			table.insert(lines, label)
			for _, todo_idx in ipairs(groups[label]) do
				local todo = state.todos[todo_idx]
				if todo.notes == nil or todo.notes == "" then
					tmp_notes_icon = ""
				else
					tmp_notes_icon = notes_icon
				end
				local todo_text = render_todo(todo, formatting, lang, tmp_notes_icon)
				table.insert(lines, "  " .. todo_text)
				line_to_todo[#lines] = todo_idx
			end
			table.insert(lines, "")
		end
		if state.active_filter then
			table.insert(lines, 1, "")
			table.insert(lines, 1, "  Filtered by: #" .. state.active_filter)
			for i = #line_to_todo, 1, -1 do
				line_to_todo[i + 2] = line_to_todo[i]
				line_to_todo[i] = nil
			end
		end

	for i, line in ipairs(lines) do
		lines[i] = line:gsub("\n", " ")
	end
	vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)

	-- Helper function to add highlight
	local function add_hl(line_nr, start_col, end_col, hl_group)
		vim.api.nvim_buf_add_highlight(buf_id, ns_id, hl_group, line_nr, start_col, end_col)
	end

	-- Helper function to find pattern and highlight
	local function highlight_pattern(line, line_nr, pattern, hl_group)
		local start_idx = line:find(pattern)
		if start_idx then
			add_hl(line_nr, start_idx - 1, -1, hl_group)
		end
	end

		for i, line in ipairs(lines) do
			local line_nr = i - 1
			local todo_idx = line_to_todo[i]
			if todo_idx then
				local todo = state.todos[todo_idx]
				-- Base todo highlight
				if todo.status == "done" then
					add_hl(line_nr, 0, -1, "DooingDone")
				elseif todo.status == "in_progress" then
					add_hl(line_nr, 0, -1, "DooingInProgress")
				else
					local hl_group = get_priority_highlight(todo.priorities)
					add_hl(line_nr, 0, -1, hl_group)
				end
				-- Tags highlight
				for tag in line:gmatch("#(%w+)") do
					local tag_pattern = "#" .. tag
					local start_idx = line:find(tag_pattern) - 1
					add_hl(line_nr, start_idx, start_idx + #tag_pattern, "Type")
				end
				-- Due date and overdue highlights
				highlight_pattern(line, line_nr, "%[@%d+/%d+/%d+%]", "Comment")
				highlight_pattern(line, line_nr, "%[OVERDUE%]", "ErrorMsg")
				-- Timestamp highlight
				if config.options.timestamp and config.options.timestamp.enabled then
					local timestamp_pattern = "@[%w%s]+ago"
					local start_idx = line:find(timestamp_pattern)
					if start_idx then
						add_hl(line_nr, start_idx - 1, start_idx + #line:match(timestamp_pattern), "DooingTimestamp")
					end
				end
			elseif line:match("Filtered by:") then
				add_hl(line_nr, 0, -1, "WarningMsg")
			end
		end

	vim.api.nvim_buf_set_option(buf_id, "modifiable", false)
end

-- Toggles the main todo window visibility
function M.toggle_todo_window()
	if win_id and vim.api.nvim_win_is_valid(win_id) then
		M.close_window()
	else
		create_window()
		M.render_todos()
	end
end

-- Closes all plugin windows
function M.close_window()
	if help_win_id and vim.api.nvim_win_is_valid(help_win_id) then
		vim.api.nvim_win_close(help_win_id, true)
		help_win_id = nil
		help_buf_id = nil
	end

	if win_id and vim.api.nvim_win_is_valid(win_id) then
		vim.api.nvim_win_close(win_id, true)
		win_id = nil
		buf_id = nil
	end
end

-- Check if the window is currently open
function M.is_window_open()
    return win_id ~= nil and vim.api.nvim_win_is_valid(win_id)
end

-- Function to reload todos and refresh UI if window is open
function M.reload_todos()
    state.load_todos()
    if M.is_window_open() then
        M.render_todos()
        notify.success("Todo list refreshed")
    end
end

-- Force refresh from backend (useful for Todoist sync)
function M.force_refresh()
    if config.options.backend == "todoist" then
        state.load_todos()
        if M.is_window_open() then
            M.render_todos()
            notify.success("Refreshed from Todoist")
        end
    end
end

-- Creates a new todo item
M.new_todo = auto_render(function()
    safe_input({ prompt = "New to-do: " }, function(input)
        -- If user cancelled or provided no input, do nothing
        if not input or input == "" then
            return
        end
        input = input:gsub("\n", " ")
        if input ~= "" then
			-- Check if priorities are configured
			if config.options.priorities and #config.options.priorities > 0 then
				local priorities = config.options.priorities
				local priority_options = {}
				local selected_priorities = {}

				for i, priority in ipairs(priorities) do
					priority_options[i] = string.format("[ ] %s", priority.name)
				end

				-- Create a buffer for priority selection
				local select_buf = vim.api.nvim_create_buf(false, true)
				local ui = vim.api.nvim_list_uis()[1]
				local width = 40
				local height = #priority_options + 2
				local row = math.floor((ui.height - height) / 2)
				local col = math.floor((ui.width - width) / 2)

				-- Store keymaps for cleanup
				local keymaps = {
					config.options.keymaps.toggle_priority,
					"<CR>",
					"q",
					"<Esc>",
				}

				local select_win = vim.api.nvim_open_win(select_buf, true, {
					relative = "editor",
					width = width,
					height = height,
					row = row,
					col = col,
					style = "minimal",
					border = "rounded",
					title = " Select Priorities ",
					title_pos = "center",
					footer = string.format(" %s: toggle | <Enter>: confirm ", config.options.keymaps.toggle_priority),
					footer_pos = "center",
				})

				-- Set buffer content
				vim.api.nvim_buf_set_lines(select_buf, 0, -1, false, priority_options)
				vim.api.nvim_buf_set_option(select_buf, "modifiable", false)

				-- Add keymaps for selection
				vim.keymap.set("n", config.options.keymaps.toggle_priority, function()
					if not (select_win and vim.api.nvim_win_is_valid(select_win)) then
						return
					end

					local cursor = vim.api.nvim_win_get_cursor(select_win)
					local line_num = cursor[1]
					local current_line = vim.api.nvim_buf_get_lines(select_buf, line_num - 1, line_num, false)[1]

					vim.api.nvim_buf_set_option(select_buf, "modifiable", true)
					if current_line:match("^%[%s%]") then
						-- Select item
						local new_line = current_line:gsub("^%[%s%]", "[x]")
						selected_priorities[line_num] = true
						vim.api.nvim_buf_set_lines(select_buf, line_num - 1, line_num, false, { new_line })
					else
						-- Deselect item
						local new_line = current_line:gsub("^%[x%]", "[ ]")
						selected_priorities[line_num] = nil
						vim.api.nvim_buf_set_lines(select_buf, line_num - 1, line_num, false, { new_line })
					end
					vim.api.nvim_buf_set_option(select_buf, "modifiable", false)
				end, { buffer = select_buf, nowait = true })

				-- Add keymap for confirmation
				vim.keymap.set("n", "<CR>", function()
					if not (select_win and vim.api.nvim_win_is_valid(select_win)) then
						return
					end

					local selected_priority_names = {}
					for idx, _ in pairs(selected_priorities) do
						local priority = config.options.priorities[idx]
						if priority then
							table.insert(selected_priority_names, priority.name)
						end
					end

					-- Clean up resources before proceeding
					cleanup_priority_selection(select_buf, select_win, keymaps)

					-- Add todo with priority names
					local priorities_to_add = #selected_priority_names > 0 and selected_priority_names or nil
					state.add_todo(input, priorities_to_add)
					-- Auto-render will handle this

					-- Make sure we're focusing on the main window
					if win_id and vim.api.nvim_win_is_valid(win_id) then
						vim.api.nvim_set_current_win(win_id)
						
						-- Position cursor at the new todo
						local total_lines = vim.api.nvim_buf_line_count(buf_id)
						local target_line = nil
						for i = 1, total_lines do
							local line = vim.api.nvim_buf_get_lines(buf_id, i - 1, i, false)[1]
							if line:match("%s+" .. config.options.formatting.pending.icon .. ".*" .. vim.pesc(input)) then
								target_line = i
								break
							end
						end

						if target_line and win_id and vim.api.nvim_win_is_valid(win_id) then
							vim.api.nvim_win_set_cursor(win_id, { target_line, 0 })
						end
					end
				end, { buffer = select_buf, nowait = true })

				-- Add escape/quit keymaps
				local function close_window()
					cleanup_priority_selection(select_buf, select_win, keymaps)
				end

				vim.keymap.set("n", "q", close_window, { buffer = select_buf, nowait = true })
				vim.keymap.set("n", "<Esc>", close_window, { buffer = select_buf, nowait = true })

				-- Add autocmd for cleanup when leaving buffer
				vim.api.nvim_create_autocmd("BufLeave", {
					buffer = select_buf,
					callback = function()
						cleanup_priority_selection(select_buf, select_win, keymaps)
						return true -- Remove the autocmd after execution
					end,
					once = true,
				})
			else
				-- If prioritization is disabled, just add the todo without priority
				state.add_todo(input)
				-- Auto-render will handle this
				
				-- Make sure we're focusing on the main window
				if win_id and vim.api.nvim_win_is_valid(win_id) then
					vim.api.nvim_set_current_win(win_id)
					
					-- Position cursor at the new todo
					local total_lines = vim.api.nvim_buf_line_count(buf_id)
					local target_line = nil
					for i = 1, total_lines do
						local line = vim.api.nvim_buf_get_lines(buf_id, i - 1, i, false)[1]
						if line:match("%s+" .. config.options.formatting.pending.icon .. ".*" .. vim.pesc(input)) then
							target_line = i
							break
						end
					end
					
					if target_line and win_id and vim.api.nvim_win_is_valid(win_id) then
						vim.api.nvim_win_set_cursor(win_id, { target_line, 0 })
					end
				end
			end
		end
	end)
end)

-- Centralized UI action helper
local function execute_todo_action(action_name, action_fn, success_msg, validation_fn)
	local cursor = vim.api.nvim_win_get_cursor(win_id)
	local current_line = cursor[1]
	local todo_index = line_to_todo[current_line]
	
	if not todo_index then
		notify.warn("No todo selected")
		return
	end
	
	print("DEBUG: execute_todo_action - todo before: " .. (state.todos[todo_index].text or "nil") .. " - status: " .. (state.todos[todo_index].status or "nil"))
	
	-- Optional validation before action
	if validation_fn then
		local valid, msg = validation_fn(state.todos[todo_index])
		if not valid then
			notify.warn(msg)
			return
		end
	end
	
	-- Execute action (auto-render will handle re-rendering)
	local success = action_fn(todo_index)
	print("DEBUG: execute_todo_action - todo after: " .. (state.todos[todo_index].text or "nil") .. " - status: " .. (state.todos[todo_index].status or "nil"))
	if success and success_msg then
		notify.success(success_msg)
	end
end

-- Toggles the completion status of the current todo
M.toggle_todo = auto_render(function()
	execute_todo_action("toggle", state.toggle_todo)
end)

-- Cancel in-progress todo back to pending
M.cancel_in_progress = auto_render(function()
	execute_todo_action("cancel", state.cancel_in_progress, "Todo cancelled back to pending", function(todo)
		if todo.status == "pending" then
			return false, "Todo is already pending"
		end
		return true
	end)
end)

-- Complete todo directly (Shift+X)
M.complete_todo = auto_render(function()
	print("DEBUG: complete_todo called")
	execute_todo_action("complete", state.complete_todo, "Todo marked as completed", function(todo)
		if todo.status == "done" then
			return false, "Todo is already completed"
		end
		return true
	end)
	print("DEBUG: complete_todo finished")
end)

-- Deletes the current todo item
M.delete_todo = auto_render(function()
	local cursor = vim.api.nvim_win_get_cursor(win_id)
	local todo_index = cursor[1] - 1
	local line_content = vim.api.nvim_buf_get_lines(buf_id, todo_index, todo_index + 1, false)[1]
	
	-- Use icon helper instead of manual icon retrieval
	local all_icons = get_status_icon("done") .. get_status_icon("pending") .. get_status_icon("in_progress")

	if line_content:match("%s+[" .. all_icons .. "]") then
		if state.active_filter then
			local visible_index = 0
			for i, todo in ipairs(state.todos) do
				if todo.text:match("#" .. state.active_filter) then
					visible_index = visible_index + 1
					if visible_index == todo_index - 2 then
						todo_index = 1
						break
					end
				end
			end
		else
			state.delete_todo_with_confirmation(todo_index, win_id, calendar, function()
				-- Auto-render will handle this
			end)
		end
	end
end)

-- Deletes all completed todos
M.delete_completed = auto_render(function()
	state.delete_completed()
end)

-- Delete all duplicated todos
M.remove_duplicates = auto_render(function()
	local dups = state.remove_duplicates()
	notify.success("Removed " .. dups .. " duplicates.")
end)

return M
