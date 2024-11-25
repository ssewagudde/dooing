local M = {}
local config = require("dooing.config")
local ui = require("dooing.ui")
local state = require("dooing.state")

function M.setup(opts)
	config.setup(opts)
	state.load_todos()

	-- Set up keymaps
	vim.keymap.set("n", "<leader>td", function()
		ui.toggle_todo_window()
	end, { desc = "Toggle Todo List" })
end

return M
