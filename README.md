jasonelston dotfiles
===============

I use [thoughtbot/dotfiles](https://github.com/thoughtbot/dotfiles) and
jasonelston/dotfiles together using [the `*.local` convention][dot-local].

[dot-local]: http://robots.thoughtbot.com/manage-team-and-personal-dotfiles-together-with-rcm

Requirements
------------

Set zsh as my login shell.

    chsh -s /bin/zsh

Install [rcm](https://github.com/mike-burns/rcm).

    brew tap thoughtbot/formulae
    brew install rcm

Install
-------

Clone onto my laptop:

    git clone https://github.com/jasonelston/dotfiles.git ~/dotfiles-local
    git clone https://github.com/thoughtbot/dotfiles.git ~/dotfiles

Symlink dotfiles into `$HOME` (rcm picks files from `dotfiles-local` first
when both repos have the same name, so my customizations win):

    env RCRC=$HOME/dotfiles-local/rcrc rcup

Run the [thoughtbot/laptop](https://github.com/thoughtbot/laptop) script,
which installs Homebrew + base tools and then sources `~/.laptop.local` to
install everything else (Ghostty, sesh, fzf, zoxide, lazygit, tmux, ...) and
create the non-rcm symlinks (Ghostty config, `sesh-combined-picker` on PATH,
tmux plugins via TPM):

    bash <(curl -s https://raw.githubusercontent.com/thoughtbot/laptop/main/mac)

After `laptop` finishes, everything is set up — no manual steps required.
`rcup` and `laptop` can both be re-run safely; they're idempotent.

Architecture notes
------------------

### Tmux

The canonical tmux config lives at `~/dotfiles-local/tmux.conf`. It fully
replaces thoughtbot's tmux.conf so the public repo stays untouched. `rcup`
creates `~/.tmux.conf -> ~/dotfiles-local/tmux.conf` automatically (because
`dotfiles-local` precedes `dotfiles` in `rcrc`'s `DOTFILES_DIRS`).

All `@plugin` declarations live directly in this file — TPM scans it on its
single `run` line at the bottom and installs/loads everything.

### Ghostty

The Ghostty config lives at `~/dotfiles-local/ghostty-config` and is
symlinked to `~/.config/ghostty/config` by `laptop.local` (rcm doesn't
handle XDG paths well). Two macOS keybinds in the file pair with tmux
`user-keys`:

- `Cmd + K` -> sends `\e[1;31337~` -> tmux User0 -> opens the sesh picker
- `Cmd + G` -> sends `\e[1;31338~` -> tmux User1 -> opens lazygit

After editing the Ghostty config, fully relaunch Ghostty (`Cmd + Q` then
reopen). Reload via `Cmd + Shift + ,` covers most settings but `text:`
keybinds reliably apply only on full restart.

### Sesh combined picker

`~/dotfiles-local/sesh-combined-picker` is a unified fzf-driven chooser over
tmux sessions, tmux windows (sorted by recent activity), sesh configured
sessions, and zoxide directories. `laptop.local` symlinks it into `~/.bin/`
for command-line use; the tmux bindings (`prefix + K`, `Cmd + K`) point at
the absolute path.
