return {
  "nvim-treesitter/nvim-treesitter", 
  build = ":TSUpdate",
  config = function()
    local treesitter = require("nvim-treesitter.configs")
    treesitter.setup({
      ensure_installed = { "lua", "vim", "vimdoc", "javascript", "html", "go", "typescript", "yaml" },
      highlight = { enable = true },
      indent = { enable = true },  
    })
  end
}
