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

	-- Only set up keymap if it's enabled in config
	if config.options.keymaps.toggle_window then
		vim.keymap.set("n", config.options.keymaps.toggle_window, function()
			ui.toggle_todo_window()
		end, { desc = "Toggle Todo List" })
	end
end

return M
