# relacon

Keymap for the ELECOM Relacon trackball, run by `relacon-d`
(`~/Documents/repos/kkrausse/random/relacon-d`). Saved changes apply live.

Setup on a machine:

```sh
mkdir -p ~/.config/relacon
ln -sf ~/Documents/repos/kkrausse/dotfiles/relacon/config.ts ~/.config/relacon/config.ts
cd ~/Documents/repos/kkrausse/random/relacon-d && scripts/install.sh --load
```

Then grant Relacon Input Monitoring + Accessibility. Machine-only bindings go in
an untracked `~/.config/relacon/local.ts`, loaded after this file.
