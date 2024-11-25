# Dooing

Dooing is a minimalist todo list manager for Neovim, designed with simplicity and efficiency in mind. It provides a clean, distraction-free interface to manage your tasks directly within Neovim. Perfect for users who want to keep track of their todos without leaving their editor.

![dooing_demo](https://github.com/user-attachments/assets/28936d67-b4d5-44b9-aa22-99138b7db762)

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
    keys = {
        { "<leader>td", desc = "Toggle Todo List" },
    },
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
    save_path = vim.fn.stdpath('data') .. '/dooing_todos.json',
    
    -- Window appearance
    window = {
        width = 40,         -- Width of the floating window
        height = 20,        -- Height of the floating window
        border = 'rounded', -- Border style
    },
    
    -- Icons
    icons = {
        pending = '○',      -- Pending todo icon
        done = '✓',        -- Completed todo icon
    }
}
```

---

## 🔑 Keybindings

Dooing comes with intuitive keybindings:

| Key           | Action                          |
|--------------|----------------------------------|
| `<leader>td` | Toggle the todo list window     |
| `i`          | Add a new todo                  |
| `x`          | Toggle todo status              |
| `d`          | Delete current todo             |
| `D`          | Delete all completed todos      |
| `q`          | Close the todo list window      |
| `?`          | Toggle help window      |

---

## 🛠️ Usage

1. Open Dooing with `<leader>td`
2. Press `i` to add a new todo
3. Use `#tags` in your todos to categorize them (e.g., "Buy milk #shopping")
4. Press `x` to mark a todo as complete
5. Press `d` to delete a todo
6. Press `D` to clear all completed todos
7. Press `q` to close the window
8. Press `?` to toggle help window

---

## 📥 Backlog

Planned features and improvements for future versions of Dooing:

#### Core Features

- [ ] Due Dates Support
- [ ] Priority Levels
- [ ] Todo Filtering by Tags
- [ ] Todo Search
- [ ] Todo List Per Project

#### UI Enhancements

- [ ] Tag Highlighting
- [ ] Custom Todo Colors
- [ ] Todo Categories View

#### Quality of Life

- [ ] Multiple Todo Lists
- [ ] Import/Export Features

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
