complete -c sfb -f

complete -c sfb -n "not __fish_seen_subcommand_from tui scan list summary find trash doctor unlock protect help" -a "tui" -d "interactive TUI"
complete -c sfb -n "not __fish_seen_subcommand_from tui scan list summary find trash doctor unlock protect help" -a "scan" -d "scan directories by size"
complete -c sfb -n "not __fish_seen_subcommand_from tui scan list summary find trash doctor unlock protect help" -a "list" -d "list immediate children"
complete -c sfb -n "not __fish_seen_subcommand_from tui scan list summary find trash doctor unlock protect help" -a "summary" -d "show recursive summary report"
complete -c sfb -n "not __fish_seen_subcommand_from tui scan list summary find trash doctor unlock protect help" -a "find" -d "find entries by name"
complete -c sfb -n "not __fish_seen_subcommand_from tui scan list summary find trash doctor unlock protect help" -a "trash" -d "move paths to Trash"
complete -c sfb -n "not __fish_seen_subcommand_from tui scan list summary find trash doctor unlock protect help" -a "doctor" -d "check dependencies"
complete -c sfb -n "not __fish_seen_subcommand_from tui scan list summary find trash doctor unlock protect help" -a "unlock" -d "issue unlock token"
complete -c sfb -n "not __fish_seen_subcommand_from tui scan list summary find trash doctor unlock protect help" -a "protect" -d "manage path protection"
complete -c sfb -n "not __fish_seen_subcommand_from tui scan list summary find trash doctor unlock protect help" -a "help" -d "show help"

complete -c sfb -n "__fish_seen_subcommand_from scan" -l depth -d "scan depth"
complete -c sfb -n "__fish_seen_subcommand_from scan" -l top -d "top entries"
complete -c sfb -n "__fish_seen_subcommand_from scan" -l human -d "human-readable sizes"
complete -c sfb -n "__fish_seen_subcommand_from scan" -l json -d "json output"
complete -c sfb -n "__fish_seen_subcommand_from scan" -l tsv -d "tsv output"

complete -c sfb -n "__fish_seen_subcommand_from list" -l top -d "top entries"
complete -c sfb -n "__fish_seen_subcommand_from list" -l sort -d "sort mode" -a "size name"
complete -c sfb -n "__fish_seen_subcommand_from list" -l human -d "human-readable sizes"
complete -c sfb -n "__fish_seen_subcommand_from list" -l json -d "json output"
complete -c sfb -n "__fish_seen_subcommand_from list" -l tsv -d "tsv output"

complete -c sfb -n "__fish_seen_subcommand_from summary" -l json -d "json output"

complete -c sfb -n "__fish_seen_subcommand_from find" -l name -d "filename glob pattern"
complete -c sfb -n "__fish_seen_subcommand_from find" -l json -d "json output"

complete -c sfb -n "__fish_seen_subcommand_from trash" -l allow-delete -d "enable deletion"
complete -c sfb -n "__fish_seen_subcommand_from trash" -l unlock-token -d "unlock token"
complete -c sfb -n "__fish_seen_subcommand_from trash" -l json -d "json output"

complete -c sfb -n "__fish_seen_subcommand_from doctor" -l install-deps -d "install missing dependencies"
complete -c sfb -n "__fish_seen_subcommand_from doctor" -l issue-token -d "issue unlock token"
complete -c sfb -n "__fish_seen_subcommand_from doctor" -l json -d "json output"

complete -c sfb -n "__fish_seen_subcommand_from protect; and not __fish_seen_subcommand_from list add remove" -a "list add remove" -d "protect subcommand"
