# Records demo/demo.gif. Run `nix run .#demo` instead, which sets up the tmux session this attaches to.

Output demo/demo.gif

Set Shell "bash"
Set FontSize 14
Set Width 1400
Set Height 760
Set Padding 12
Set TypingSpeed 50ms

Hide
Type "tmux -L sidekick-demo attach -t demo" Enter
Sleep 2s
Show

Sleep 1s
Type ":sidekick-attach"
Sleep 600ms
Enter
Sleep 2.5s
Down
Sleep 1s
Enter
Sleep 1.5s

Type ":sidekick-send-file"
Sleep 600ms
Enter
Sleep 1.5s

Type "5G"
Sleep 300ms
Type "xxx"
Sleep 600ms
Type ":sidekick-send-selection"
Sleep 600ms
Enter
Sleep 2s

# Move to the attached session, %2, and finish the prompt there.
Ctrl+B
Type "o"
Sleep 300ms
Ctrl+B
Type "o"
Sleep 800ms
Type "what does format return in each case?"
Sleep 600ms
Enter
Sleep 16s
