local M = {}
local config = require("dooing.config")
local ui = require("dooing.ui")
local state = require("dooing.state")

function M.setup(opts)
	config.setup(opts)
	state.load_todos()

	vim.api.nvim_create_user_command("Dooing", function(opts)
		if opts.args ~= "" then
			state.add_todo(opts.args)
		else
			ui.toggle_todo_window()
		end
	end, {
		desc = "Toggle Todo List window or add new todo",
		nargs = "?",
	})

	-- Set up keymaps
	vim.keymap.set("n", "<leader>td", function()
		ui.toggle_todo_window()
	end, { desc = "Toggle Todo List" })
end

return M
