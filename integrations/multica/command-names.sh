# The runtime profiles' command names, sourced by install.sh and uninstall.sh (one place to change).
# D1a (P1) swap point: R50 passes the bare wrapper names; if P1 records that the daemon needs an
# absolute path, change these two to "$HOME/.local/bin/<name>". uninstall.sh matches on the
# basename, so profiles made with either form are found.
CMD_OMEGA=omega-multica-agent
CMD_CLAUDE=claude-multica
