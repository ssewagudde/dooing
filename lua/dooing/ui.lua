local M = {}
local state = require("dooing.state")

local win_id = nil
local buf_id = nil
local help_win_id = nil
local help_buf_id = nil
local ns_id = vim.api.nvim_create_namespace("dooing")

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

	-- Create help buffer
	help_buf_id = vim.api.nvim_create_buf(false, true)

	local width = 40
	local ui = vim.api.nvim_list_uis()[1]
	local col = ui.width - width - 2

	-- Position help window above main window
	help_win_id = vim.api.nvim_open_win(help_buf_id, false, {
		relative = "editor",
		row = 1,
		col = col,
		width = width,
		height = 10,
		style = "minimal",
		border = "rounded",
		title = " help ",
		title_pos = "center",
		zindex = 200,
	})

	local help_content = {
		" Keybindings:",
		" ",
		" i     - Add new todo",
		" x     - Toggle todo status",
		" d     - Delete current todo",
		" D     - Delete all completed todos",
		" ?     - Toggle this help window",
		" q     - Close window",
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

local function create_window()
	local width = 40
	local height = 20

	local ui = vim.api.nvim_list_uis()[1]
	local col = ui.width - width - 2

	buf_id = vim.api.nvim_create_buf(false, true)

	win_id = vim.api.nvim_open_win(buf_id, true, {
		relative = "editor",
		row = 13,
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
	vim.keymap.set("n", "i", M.new_todo, { buffer = buf_id })
	vim.keymap.set("n", "x", M.toggle_todo, { buffer = buf_id })
	vim.keymap.set("n", "q", M.close_window, { buffer = buf_id })
	vim.keymap.set("n", "d", M.delete_todo, { buffer = buf_id })
	vim.keymap.set("n", "D", M.delete_completed, { buffer = buf_id })
	vim.keymap.set("n", "?", create_help_window, { buffer = buf_id, nowait = true })
end

function M.render_todos()
	if not buf_id then
		return
	end

	vim.api.nvim_buf_set_option(buf_id, "modifiable", true)
	vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)

	local lines = {}
	state.sort_todos()

	table.insert(lines, "")

	for _, todo in ipairs(state.todos) do
		local icon = todo.done and "✓" or "○"
		local text = todo.text

		if todo.done then
			text = "~" .. text .. "~"
		end

		table.insert(lines, "  " .. icon .. " " .. text)
	end

	table.insert(lines, "")

	vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)

	for i, line in ipairs(lines) do
		if line:match("^%s+[○✓]") then -- Only highlight actual todo lines
			local todo_index = i - 1
			local todo = state.todos[todo_index]
			if todo then
				local hl_group = todo.done and "DooingDone" or "DooingPending"
				vim.api.nvim_buf_add_highlight(buf_id, ns_id, hl_group, i - 1, 0, -1)
			end
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
	vim.ui.input({ prompt = "New todo: " }, function(input)
		if input and input ~= "" then
			state.add_todo(input)
			M.render_todos()
		end
	end)
end

function M.toggle_todo()
	local cursor = vim.api.nvim_win_get_cursor(win_id)
	local line_content = vim.api.nvim_buf_get_lines(buf_id, cursor[1] - 1, cursor[1], false)[1]

	if line_content:match("^%s+[○✓]") then
		local todo_count = 0
		for i = 1, cursor[1] - 1 do
			local line = vim.api.nvim_buf_get_lines(buf_id, i - 1, i, false)[1]
			if line:match("^%s+[○✓]") then
				todo_count = todo_count + 1
			end
		end
		state.toggle_todo(todo_count)
		M.render_todos()
	end
end

function M.delete_todo()
	local cursor = vim.api.nvim_win_get_cursor(win_id)
	local line_content = vim.api.nvim_buf_get_lines(buf_id, cursor[1] - 1, cursor[1], false)[1]

	if line_content:match("^%s+[○✓]") then
		local todo_count = 0
		for i = 1, cursor[1] - 1 do
			local line = vim.api.nvim_buf_get_lines(buf_id, i - 1, i, false)[1]
			if line:match("^%s+[○✓]") then
				todo_count = todo_count + 1
			end
		end
		state.delete_todo(todo_count)
		M.render_todos()
	end
end

function M.delete_completed()
	state.delete_completed()
	M.render_todos()
end

return M
