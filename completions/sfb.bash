_sfb_completions() {
  local cur prev
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  case "${COMP_WORDS[1]}" in
    scan)
      COMPREPLY=( $(compgen -W "--depth --top --human --json --tsv" -- "$cur") )
      ;;
    list)
      COMPREPLY=( $(compgen -W "--top --sort --human --json --tsv" -- "$cur") )
      ;;
    summary)
      COMPREPLY=( $(compgen -W "--json" -- "$cur") )
      ;;
    find)
      COMPREPLY=( $(compgen -W "--name --json" -- "$cur") )
      ;;
    trash)
      COMPREPLY=( $(compgen -W "--allow-delete --unlock-token --json" -- "$cur") )
      ;;
    doctor)
      COMPREPLY=( $(compgen -W "--install-deps --issue-token --json" -- "$cur") )
      ;;
    protect)
      COMPREPLY=( $(compgen -W "list add remove" -- "$cur") )
      ;;
    *)
      COMPREPLY=( $(compgen -W "tui scan list summary find trash doctor unlock protect help" -- "$cur") )
      ;;
  esac
}

complete -F _sfb_completions sfb
