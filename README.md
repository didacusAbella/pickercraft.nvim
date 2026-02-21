# pickercraft.nvim

A lightweight, configurable picker for Neovim.

It works with Neovim 0.11+ and uses floating windows for a Telescope-like experience without heavy dependencies.

---

## ⚡ Features

- File picker
- Live grep
- Fast sorting
- Preview buffer
- Optional icons via `nvim-web-devicons`
- Lazy-load friendly

---

## 🚀 Installation (lazy.nvim)

```lua
require("lazy").setup({
  {
    "didacusAbella/pickercraft.nvim",
    opts = {}
  }
})
```

## Commands

| Command        | Description           |
| -------------- | --------------------- |
| `:PickerFiles` | Open file picker      |
| `:PickerGrep`  | Open live grep picker |

## Configuration
You can customize pickercraft by passing options to `setup()`:

```lua
require("pickercraft").setup({
    file = { -- This configure the command to use for file searching
        cmd = "ag",
		args = function(input)
			return { "-g", input }
		end,
	},
	grep = { -- This configure the command to use for grepping
        cmd = "ag",
		args = function(input)
			return { "--vimgrep", input }
		end,
	},
	sort = { -- This configure the command for sorting
		cmd = "fzy",
		args = function(input)
			return { "-e", input }
		end,
	},
	preview = { -- This configure the command for preview
		cmd = "cat",
		args = function(input)
			return { input }
		end,
	},
})
```


## Architecture

### Philosophy and Design 
Pickercraft tries to follow a UNIX approach: do one thing and do it well. In my opinion solutions like Telescope or FZFLua are amazing but they do a lot
of things. I think the better approach to customize neovim is enchance every single parts with specialized plugins instead of an __all in one approach__.
Pickercraft tries to solve one thing: __file finding__ with the best solutions there are already implemented by other people. 

### Components
Pickercraft is created around file finding. The common pattern about this requirements is the following:
1. The user have to search some file (by name or by content)
2. The picker return the results based on pattern
3. The user choose the file from result and open it

These steps involve the use of 2 component:
1. The finder (a program responsible of find files)
2. The sorter (a program responsible of sorting results with best matches)
3. The previewer (a program responsible to show the preview of the file)

Pickercraft use the concept of __PIPELINE__ to unify the interaction of these components.
The are two pipeline: 
- __SearchPipeline__ input -> finder -> sorter -> results
- __PreviewPipeline__ input -> preview -> result

A pipeline is a simple list of shell commands executed in sequence where the output of previous command is the input of the next.
The beauty of Pickercraft is that you can use all the commands that altready exists (if properly configured and compatible with the pipeline model) to build your
personal file picker. A command is configured as a lua table with the following structure

- cmd _string_ the path to the command name
- args _function_ is a callback that accept the query as parameter and return an array of string representing the options to pass to the command

### Icons
If you install **nvim-web-devicons** pickercraft will show file icons in both file picker and grep results
