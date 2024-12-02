# Dooing

Dooing is a minimalist todo list manager for Neovim, designed with simplicity and efficiency in mind. It provides a clean, distraction-free interface to manage your tasks directly within Neovim. Perfect for users who want to keep track of their todos without leaving their editor.

![dooing demo](https://github.com/user-attachments/assets/ffb921d6-6dd8-4a01-8aaa-f2440891b22e)



## 🚀 Features

- 📝 Manage todos in a clean **floating window**
- 🏷️ Categorize tasks with **#tags**
- ✅ Simple task management with clear visual feedback
- 💾 **Persistent storage** of your todos
- 🎨 Adapts to your Neovim **colorscheme**
- 🛠️ Compatible with **Lazy.nvim** for effortless installation

---

## 📦 Installation

### Prerequisites

- Neovim `>= 0.10.0`
- [Lazy.nvim](https://github.com/folke/lazy.nvim) as your plugin manager

### Using Lazy.nvim

```lua
return {
    "atiladefreitas/dooing",
    config = function()
        require("dooing").setup({
            -- your custom config here (optional)
        })
    end,
}
```

Run the following commands in Neovim to install Dooing:

```vim
:Lazy sync
```

### Default Configuration
Dooing comes with sensible defaults that you can override:
```lua
{
    -- Core settings
	save_path = vim.fn.stdpath("data") .. "/dooing_todos.json",

    -- Window settings
    window = {
		width = 55,
		height = 20,
		border = "rounded",
		padding = {
			top = 1,
			bottom = 1,
			left = 2,
			right = 2,
		},
	},

    -- To-do formatting
	formatting = {
		pending = {
			icon = "○",
			format = { "icon", "text", "due_date" },
		},
		done = {
			icon = "✓",
			format = { "icon", "text", "due_date" },
		},
	},

    -- Priorization options
	prioritization = false,
	priorities = {
		{
			name = "important",
			weight = 4,
		},
		{
			name = "urgent",
			weight = 2,
		},
	},
	priority_thresholds = {
		{
			min = 5, -- Corresponds to `urgent` and `important` tasks
			max = 999,
			color = nil,
			hl_group = "DiagnosticError",
		},
		{
			min = 3, -- Corresponds to `important` tasks
			max = 4,
			color = nil,
			hl_group = "DiagnosticWarn",
		},
		{
			min = 1, -- Corresponds to `urgent tasks`
			max = 2,
			color = nil,
			hl_group = "DiagnosticInfo",
		},
	},

    -- Default keymaps
	keymaps = {
		toggle_window = "<leader>td",
		new_todo = "i",
		toggle_todo = "x",
		delete_todo = "d",
		delete_completed = "D",
		close_window = "q",
		add_due_date = "H",
		remove_due_date = "r",
		toggle_help = "?",
		toggle_tags = "t",
		clear_filter = "c",
		edit_todo = "e",
		edit_tag = "e",
		delete_tag = "d",
		search_todos = "/",
		import_todos = "I",
		export_todos = "E",
		remove_duplicates = "<leader>D",
	},

    -- Calendar options
	calendar = {
		language = "en",
		icon = "",
		keymaps = {
			previous_day = "h",
			next_day = "l",
			previous_week = "k",
			next_week = "j",
			previous_month = "H",
			next_month = "L",
			select_day = "<CR>",
			close_calendar = "q",
		},
	},
}
```

## Commands

Dooing can be controlled through user commands:

- `:Dooing` opens the main window,
- `:Dooing add Your Simple Task`, adds a task.
- `:Dooing -p important,urgent Your Important and Urgent task`, assigns priority to it.

---

## 🔑 Keybindings

Dooing comes with intuitive keybindings:

#### Main Window
| Key           | Action                      |
|--------------|----------------------------|
| `<leader>td` | Toggle todo window         |
| `i`          | Add new todo               |
| `x`          | Toggle todo status         |
| `d`          | Delete current todo        |
| `D`          | Delete all completed todos |
| `q`          | Close window               |
| `H`          | Add due date               |
| `r`          | Remove due date            |
| `?`          | Toggle help window         |
| `t`          | Toggle tags window         |
| `c`          | Clear active tag filter    |
| `e`          | Edit todo                  |
| `/`          | Toggle todo searching      |
| `I`          | Import todos               |
| `E`          | Export todos               |
| `<leader>D`  | Remove duplicates          |



#### Tags Window
| Key    | Action        |
|--------|--------------|
| `e`    | Edit tag     |
| `d`    | Delete tag   |
| `<CR>` | Filter by tag|
| `q`    | Close window |

#### Calendar Window
| Key    | Action              |
|--------|-------------------|
| `h`    | Previous day       |
| `l`    | Next day          |
| `k`    | Previous week     |
| `j`    | Next week         |
| `H`    | Previous month    |
| `L`    | Next month        |
| `<CR>` | Select date       |
| `q`    | Close calendar    |

---

## 📥 Backlog

Planned features and improvements for future versions of Dooing:

#### Core Features

- [x] Due Dates Support
- [x] Priority Levels
- [x] Todo Filtering by Tags
- [x] Todo Search
- [ ] Todo List Per Project

#### UI Enhancements

- [x] Tag Highlighting
- [ ] Custom Todo Colors
- [ ] Todo Categories View

#### Quality of Life

- [ ] Multiple Todo Lists
- [X] Import/Export Features

---

## 📝 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

---

## 🔖 Versioning

We use [Semantic Versioning](https://semver.org/) for versioning. For the available versions, see the [tags on this repository](https://github.com/atiladefreitas/dooing/tags).

---

## 🤝 Contributing

Contributions are welcome! If you'd like to improve Dooing, feel free to:

- Submit an issue for bugs or feature requests
- Create a pull request with your enhancements

---

## 🌟 Acknowledgments

Dooing was built with the Neovim community in mind. Special thanks to all the developers who contribute to the Neovim ecosystem and plugins like [Lazy.nvim](https://github.com/folke/lazy.nvim).

---

## 📬 Contact

If you have any questions, feel free to reach out:
- [LinkedIn](https://linkedin.com/in/atilafreitas)
- Email: [contact@atiladefreitas.com](mailto:contact@atiladefreitas.com)
