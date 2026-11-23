# Records demo/demo.gif with Helix beside two throwaway Claude Code sessions in tmux.
# Run through `nix run .#demo` from the repository root; SIDEKICK_SRC is this checkout in the store.

if [ ! -f demo/demo.tape ]; then
  echo "run this from the sidekick.hx repository root" >&2
  exit 1
fi

work=$(mktemp -d)
cleanup() {
  tmux -L sidekick-demo kill-server 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

# Recording from inside a Claude Code session would carry it into the demo's.
while read -r name; do
  [ "$name" = CLAUDE_CONFIG_DIR ] || unset "$name"
done < <(compgen -e | grep '^CLAUDE')

mkdir "$work/project"
install -m 644 "$SIDEKICK_SRC/sidekick/agent/claude.scm" "$work/project/"
# IS_DEMO hides the account's email, and skipping user settings keeps their
# hooks, plugins and status line out of the recording.
claude="IS_DEMO=1 claude --setting-sources project"

tmux -L sidekick-demo -f /dev/null \
  new-session -d -s demo -x 170 -y 42 -c "$work/project" \
  "HELIX_STEEL_CONFIG=$SIDEKICK_SRC/demo/steel hx -c $SIDEKICK_SRC/demo/config.toml claude.scm" \; \
  set -g status off \; \
  set -g focus-events on \; \
  set -g pane-border-status top \; \
  set -g pane-border-format " #{pane_id} " \; \
  split-window -h -c "$work/project" "$claude" \; \
  split-window -v -c "$work/project" "$claude" \; \
  select-pane -t 0

# Each session first asks whether to trust the new folder.
for pane in demo:0.1 demo:0.2; do
  for _ in $(seq 60); do
    tmux -L sidekick-demo capture-pane -p -t "$pane" | grep -q 'trust this folder' && break
    sleep 0.5
  done
  tmux -L sidekick-demo send-keys -t "$pane" Down Enter
done
sleep 3

vhs demo/demo.tape
