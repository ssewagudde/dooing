local M = {}
local state = require("dooing.state")
local config = require("dooing.config")

local win_id = nil
local buf_id = nil
local help_win_id = nil
local help_buf_id = nil
local ns_id = vim.api.nvim_create_namespace("dooing")

local tag_win_id = nil
local tag_buf_id = nil

vim.api.nvim_exec(
	[[
  highlight default link DooingPending Question
  highlight default link DooingDone Comment
  highlight default link DooingHelpText Directory
]],
	false
)

local function create_help_window()
	if help_win_id and vim.api.nvim_win_is_valid(help_win_id) then
		vim.api.nvim_win_close(help_win_id, true)
		help_win_id = nil
		help_buf_id = nil
		return
	end

	help_buf_id = vim.api.nvim_create_buf(false, true)

	local width = 40
	local height = 10
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
		zindex = 200,
	})

	local help_content = {
		" Keybindings:",
		" ",
		" i     - Add new to-do",
		" x     - Toggle to-do status",
		" d     - Delete current to-do",
		" D     - Delete all completed todos",
		" ?     - Toggle this help window",
		" q     - Close window",
		" t     - Toggle tags window",
		" ",
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

	vim.keymap.set("n", "q", close_help, { buffer = help_buf_id })
	vim.keymap.set("n", "?", close_help, { buffer = help_buf_id })
end

local function create_tag_window()
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

	-- Handle tag selection
	vim.keymap.set("n", "<CR>", function()
		local cursor = vim.api.nvim_win_get_cursor(tag_win_id)
		local tag = vim.api.nvim_buf_get_lines(tag_buf_id, cursor[1] - 1, cursor[1], false)[1]
		if tag ~= "No tags found" then
			state.set_filter(tag)
			vim.api.nvim_win_close(tag_win_id, true)
			tag_win_id = nil
			tag_buf_id = nil
			M.render_todos()
		end
	end, { buffer = tag_buf_id })

	-- Close with q
	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(tag_win_id, true)
		tag_win_id = nil
		tag_buf_id = nil
	end, { buffer = tag_buf_id })
end

local function create_window()
	local ui = vim.api.nvim_list_uis()[1]
	local width = 40
	local height = 20
	local col = math.floor((ui.width - width) / 2)
	local row = math.floor((ui.height - height) / 2)

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
		footer = " Press ? for help ",
		footer_pos = "center",
	})

	-- Set window options
	vim.api.nvim_win_set_option(win_id, "wrap", true)
	vim.api.nvim_win_set_option(win_id, "linebreak", true)
	vim.api.nvim_win_set_option(win_id, "breakindent", true)
	vim.api.nvim_win_set_option(win_id, "breakindentopt", "shift:2")
	vim.api.nvim_win_set_option(win_id, "showbreak", " ")

	-- Set buffer keymaps
	vim.keymap.set("n", config.options.keymaps.new_todo, M.new_todo, { buffer = buf_id })
	vim.keymap.set("n", config.options.keymaps.toggle_todo, M.toggle_todo, { buffer = buf_id })
	vim.keymap.set("n", config.options.keymaps.delete_todo, M.delete_todo, { buffer = buf_id })
	vim.keymap.set("n", config.options.keymaps.delete_completed, M.delete_completed, { buffer = buf_id })
	vim.keymap.set("n", config.options.keymaps.close_window, M.close_window, { buffer = buf_id })
	vim.keymap.set("n", config.options.keymaps.toggle_help, create_help_window, { buffer = buf_id, nowait = true })
	vim.keymap.set("n", config.options.keymaps.toggle_tags, create_tag_window, { buffer = buf_id })
	vim.keymap.set("n", config.options.keymaps.clear_filter, function()
		state.set_filter(nil)
		M.render_todos()
	end, { buffer = buf_id, desc = "Clear filter" })
end

function M.render_todos()
	if not buf_id then
		return
	end

	vim.api.nvim_buf_set_option(buf_id, "modifiable", true)
	vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)

	local lines = { "" }
	state.sort_todos()

	for _, todo in ipairs(state.todos) do
		if not state.active_filter or todo.text:match("#" .. state.active_filter) then
			local icon = todo.done and "✓" or "○"
			local text = todo.text

			if todo.done then
				text = "~" .. text .. "~"
			end

			table.insert(lines, "  " .. icon .. " " .. text)
		end
	end

	if state.active_filter then
		table.insert(lines, 1, "")
		table.insert(lines, 1, "  Filtered by: #" .. state.active_filter)
	end

	table.insert(lines, "")
	vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)

	-- Add highlights
	for i, line in ipairs(lines) do
		if line:match("^%s+[○✓]") then
			local todo_index = i - (state.active_filter and 3 or 1)
			local todo = state.todos[todo_index]
			if todo then
				local hl_group = todo.done and "DooingDone" or "DooingPending"
				vim.api.nvim_buf_add_highlight(buf_id, ns_id, hl_group, i - 1, 0, -1)

				-- Highlight tags
				for tag in line:gmatch("#(%w+)") do
					local start_idx = line:find("#" .. tag) - 1
					vim.api.nvim_buf_add_highlight(buf_id, ns_id, "Type", i - 1, start_idx, start_idx + #tag + 1)
				end
			end
		elseif line:match("Filtered by:") then
			vim.api.nvim_buf_add_highlight(buf_id, ns_id, "WarningMsg", i - 1, 0, -1)
		end
	end

	vim.api.nvim_buf_set_option(buf_id, "modifiable", false)
end

function M.toggle_todo_window()
	if win_id and vim.api.nvim_win_is_valid(win_id) then
		M.close_window()
	else
		create_window()
		M.render_todos()
	end
end

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

function M.new_todo()
	vim.ui.input({ prompt = "New to-do: " }, function(input)
		if input and input ~= "" then
			state.add_todo(input)
			M.render_todos()
		end
	end)
end

function M.toggle_todo()
	local cursor = vim.api.nvim_win_get_cursor(win_id)
	local todo_index = cursor[1] - 1
	local line_content = vim.api.nvim_buf_get_lines(buf_id, todo_index, todo_index + 1, false)[1]

	if line_content:match("^%s+[○✓]") then
		if state.active_filter then
			local visible_index = 0
			for i, todo in ipairs(state.todos) do
				if todo.text:match("#" .. state.active_filter) then
					visible_index = visible_index + 1
					if visible_index == todo_index - 2 then -- -2 for filter header
						state.toggle_todo(i)
						break
					end
				end
			end
		else
			state.toggle_todo(todo_index)
		end
		M.render_todos()
	end
end

function M.delete_todo()
	local cursor = vim.api.nvim_win_get_cursor(win_id)
	local todo_index = cursor[1] - 1
	local line_content = vim.api.nvim_buf_get_lines(buf_id, todo_index, todo_index + 1, false)[1]

	if line_content:match("^%s+[○✓]") then
		if state.active_filter then
			local visible_index = 0
			for i, todo in ipairs(state.todos) do
				if todo.text:match("#" .. state.active_filter) then
					visible_index = visible_index + 1
					if visible_index == todo_index - 2 then
						state.delete_todo(i)
						break
					end
				end
			end
		else
			state.delete_todo(todo_index)
		end
		M.render_todos()
	end
end

function M.delete_completed()
	state.delete_completed()
	M.render_todos()
end

return M
