# shellcheck shell=sh
# shellcheck disable=SC2317,SC2329   # silence code unreachability warnings
# vim: set ft=sh ts=4 sw=4 noet ai tw=79:

# cmdstash: a portable and embeddable shell script micro-framework to create
#           handy command wrappers   <https://github.com/nclsgd/cmdstash>
# SPDX-License-Identifier: 0BSD
# Copyright (C) 2025-2026 Nicolas Godinho <nicolas@godinho.me>

# cmdstash dedicated constants and runtime checks:
CMDSTASH_ARGZERO="${0:?}"
# Handle zsh pure mode where $0 would be the cmdstash file and not the source:
if [ "${ZSH_ARGZERO:-}" ] && [ "$(builtin emulate 2>/dev/null)" = zsh ]; then
	CMDSTASH_ARGZERO="$ZSH_ARGZERO"
fi
readonly CMDSTASH_ARGZERO

# Write a message on stderr with a context prefix:
say() {
	# shellcheck disable=SC2015   # yes, A && B || C is not if-then-else
	printf>&2 '%s:' "${__CMDSTASH_SELF:-${CMDSTASH_ARGZERO:-$0}}" &&\
	printf>&2 ' %s' "$@" && printf>&2 '\n' ||:
}

# Terminate shell with a context-prefixed explanation message on stderr:
die() {
	# shellcheck disable=SC2015   # yes, A && B || C is not if-then-else
	printf>&2 '%s:' "${__CMDSTASH_SELF:-${CMDSTASH_ARGZERO:-$0}}" &&\
	printf>&2 ' %s' "${@:-an error has occurred}" && printf>&2 '\n' ||:
	exit 1
}

# Trim leading and trailing whitespaces:
# (Note: IFS concatenation is followed when multiple arguments are provided)
trim() {
	set -- "$*" && set -- "${1#"${1%%[![:space:]]*}"}" &&\
	printf '%s' "${1%"${1##*[![:space:]]}"}" || exit 1
}

# Ensure sed is available via PATH resolution:
[ "${CMDSTASH_DONOTCHECKSED:-}" ] || case "$(command -v sed)" in \
/*);; *) die "cmdstash: \`sed' seems unfound in PATH";; esac

# Quote arguments following POSIX shell escaping rules:
quote() {
	while [ "${1+x}" ]; do
		printf '|%s|' "$1" | sed \
			"s/'/'\\\\''/g; 1s/^|/'/; \$s/|\$/'/;${2+" \$s/\$/ /;"}" || exit 1
		shift
	done
}

# Retrieve from parent script the user working directory (if provided):
: "${CMDSTASH_USERWORKDIR:="${PWD:?}"}"
readonly CMDSTASH_USERWORKDIR

# Compute path relative to the user working directory (CMDSTASH_USERWORKDIR):
rel2uwd() {
	case "$CMDSTASH_USERWORKDIR" in /*);; *) die \
		"rel2uwd: CMDSTASH_USERWORKDIR is not an absolute path";; esac
	case "$#" in 0) die "rel2uwd: missing path";; 1);; *) die \
		"rel2uwd: too many arguments";; esac
	case "${1:?}" in
		/*) printf '%s' "$1";;
		*)  printf '%s' "$CMDSTASH_USERWORKDIR/$1";;
	esac
}

# Retrieve the shell to be used by the parent script:
CMDSTASH_SHELL="$(cd "$CMDSTASH_USERWORKDIR" &&\
	sed <"$CMDSTASH_ARGZERO" 's/^#!//;q')" || die
CMDSTASH_SHELL="$(trim "$CMDSTASH_SHELL")" || die
case "$CMDSTASH_SHELL" in
	'') die "cmdstash: \$0 does not begin with a shebang: $CMDSTASH_ARGZERO";;
	[!/]*|*[!/a-zA-Z0-9_:,.\ +-]*)
		die "cmdstash: unexpected shebang read: #!$CMDSTASH_SHELL";;
esac

# Shell special features:
CMDSTASH_SHELLFEAT=''
# Probe if the shell supports readonly functions with `readonly -f' (Bash):
if [ "$(eval 2>/dev/null \
'_f(){ echo 1;}; readonly>&2 -f _f||:; _f(){ echo 2;}||:; _f||:')" = 1 ]; then
	CMDSTASH_SHELLFEAT="$CMDSTASH_SHELLFEAT${CMDSTASH_SHELLFEAT:+:}readonlyfuncs"
fi
readonly CMDSTASH_SHELL CMDSTASH_SHELLFEAT

# Mark the basic utility functions as readonly if supported:
case ":$CMDSTASH_SHELLFEAT:" in *:readonlyfuncs:*)
	# shellcheck disable=SC3045  # `readonly -f' support is validated above
	readonly -f say die trim quote rel2uwd ;;
esac

__CMDSTASH_SELF="${CMDSTASH_ARGZERO##*/}"
__CMDSTASH_CMDS='# cmdstash commands defintion table, DO NOT EDIT!'
__CMDSTASH_CURRENTSECTION=''
unset ABOUT

# Declaring CMD (commands):
CMD() { _cmdstash_CMD "$@"; }
_cmdstash_CMD() {
	___v=''  # function name behind the command
	while [ "${1+x}" ]; do ___o="$1"; shift; case "$___o" in
		-f)  [ "${1+x}" ] || die "CMD: missing function name"
		     [ ! "$___v" ] || die "CMD: option $___o can only be used once"
		     ___v="$1"; shift ;;
		-[f]?*) set -- "${___o%"${___o#??}"}" "${___o#??}" "$@" ;;
		--)  break ;;
		-?*) die "CMD: unknown option ${___o%"${___o#??}"}" ;;
		*)   set -- "$___o" "$@"; break ;;
	esac; done; unset ___o
	[ "${1+x}" ] || die "CMD: missing command name"
	: "${___v:="$1"}"
	case "$___v" in
		''|-*|*[!a-zA-Z0-9_.:@+-]*) die "CMD: invalid command name: $1";;
		[!a-zA-Z_]*|*[!a-zA-Z0-9_]*)
			[ "$(eval 2>/dev/null "$___v(){ echo ok;}&& $___v")" = ok ] || die \
				"CMD: accepted command name but illegal function name: $___v"
	esac
	[ "${__CMDSTASH_CURRENTSECTION:-}" ] && {
		__CMDSTASH_CMDS="$__CMDSTASH_CMDS
$__CMDSTASH_CURRENTSECTION"; __CMDSTASH_CURRENTSECTION=''
	}
	__CMDSTASH_CMDS="$__CMDSTASH_CMDS
$___v"  # no leading whitespace here!
	unset ___v
	while [ "${1+x}" ]; do
		case "$1" in
			--) shift; break ;;
			''|-*|*[!a-zA-Z0-9_.:@+-]*) die "CMD: invalid command name: $1";;
		esac
		__CMDSTASH_CMDS="$__CMDSTASH_CMDS $1"; shift
	done
	if [ "${1+x}" ]; then
		__CMDSTASH_CMDS="$__CMDSTASH_CMDS
$(trim "$(printf '%s ' "$@")" | sed '/^[[:space:]]*$/d;s/^/\t/')"
	fi
}

# Declaring command sections:
CMDSECTION() { _cmdstash_CMDSECTION "$@"; }
_cmdstash_CMDSECTION() {
	while [ "${1+x}" ]; do ___o="$1"; shift; case "$___o" in
		--)  break ;;
		-?*) die "CMDSECTION: unknown option ${___o%"${___o#??}"}" ;;
		*)   set -- "$___o" "$@"; break ;;
	esac; done; unset ___o
	__CMDSTASH_CURRENTSECTION="$(trim "$(printf '%s ' "$@")" | sed \
		'/^[[:space:]]*$/d;s/^/>/')"
}

# Evaluate all the command definitions in the parent script:
eval "$(cd "$CMDSTASH_USERWORKDIR" && sed -n <"$CMDSTASH_ARGZERO" \
's/^__CMDSTASH__//;t a;b;:a /^[[:blank:]]*$/bb;/^[[:blank:]][[:blank:]]*#/bb;b;:b {n;p;bb;}')"

# Invoke another command from the cmdstash script (potentially wrapped by a
# function or command provided with the `-w' option):
invoke() {
	___w=''  # wrapper function or command
	___x=''  # whether to pass -x again
	while [ "${1+x}" ]; do ___o="$1"; shift; case "$___o" in
		-w)  [ "${1+x}" ] || die "invoke: missing wrapper function or command"
		     [ ! "$___w" ] || die "invoke: option $___o can only be used once"
		     ___w="$1"; shift ;;
		-x)  ___x=x ;;
		-[w]?*) set -- "${___o%"${___o#??}"}" "${___o#??}" "$@" ;;
		-[x]?*) set -- "${___o%"${___o#??}"}" "-${___o#??}" "$@" ;;
		--)  break ;;
		-?*) die "invoke: unknown option ${___o%"${___o#??}"}" ;;
		*)   set -- "$___o" "$@"; break ;;
	esac; done; unset ___o
	[ "${1+x}" ] || die "invoke: missing command"
	if [ "$___w" ]; then
		# shellcheck disable=SC2016  # no expansion between single quotes
		# shellcheck disable=SC2086  # word splitting is expected here
		set -- $___w /bin/sh -c 'cd "$0" && exec "$@"' \
			"${CMDSTASH_USERWORKDIR:?}" \
			${CMDSTASH_SHELL:?} "${CMDSTASH_ARGZERO:?}" ${CMDSTASH_OPTS?} \
			${___x:+-x} -- "$@"
		unset ___w ___x
		"$@"
	else
		# shellcheck disable=SC2086  # word splitting is expected here
		set -- ${CMDSTASH_SHELL:?} "${CMDSTASH_ARGZERO:?}" ${CMDSTASH_OPTS?} \
			${___x:+-x} -- "$@"
		unset ___w ___x
		( cd "${CMDSTASH_USERWORKDIR:?}" && exec "$@" )
	fi
}

# Chain cmdstash commands:
chain() {
	# NB: these "fake" local vars must not collide with those of invoke
	___d=''  # the delimiter value
	___D=''  # is the delimiter defined?
	___v=''  # verbosity
	___X=''  # xtrace on invoked commands
	___C='die'  # function to call on invoke returning an error
	while [ "${1+x}" ]; do ___o="$1"; shift; case "$___o" in
		-d)  [ "${1+x}" ] || die "misused: missing delimiter"
		     [ ! "$___D" ] || die "misused: option $___o can only be used once"
		     ___d="$1"; ___D=x; shift ;;
		-v)  ___v=x;;
		-x)  ___X=x; ___v=x;;
		-h) printf '%s\n' "\
usage: $CMDSTASH_ARGZERO chain [-vxC]          COMMAND [COMMAND...]
       $CMDSTASH_ARGZERO chain [-vxC] -d DELIM COMMAND [ARGS...] [DELIM COMMAND [ARGS...]]...
       $CMDSTASH_ARGZERO chain -h

invoke commands in sequence

options:  -v        be verbose and print the invoked commands
          -d DELIM  specify a delimiter value to allow arguments on chained
                    commands  [tip: commas \`,' usually make good delimiters]
          -x        enable xtrace on the invoked commands  [implies -v]
          -C        continue: do not stop sequence upon failed commands
          -h        display this help and exit"; exit 0;;
		-C) ___C='say';;
		-[d]?*) set -- "${___o%"${___o#??}"}" "${___o#??}" "$@" ;;
		-[vxCh]?*) set -- "${___o%"${___o#??}"}" "-${___o#??}" "$@" ;;
		--)  break ;;
		-?*) die "misused: unknown option ${___o%"${___o#??}"}" ;;
		*)   set -- "$___o" "$@"; break ;;
	esac; done; unset ___o
	[ "${1+x}" ] || die "no commands given"
	# Without command delimiter defined:
	if [ ! "$___D" ]; then
		while [ "${1+x}" ]; do
			[ "$___v" ] && say "invoking command: $1"
			invoke ${___X:+-x} -- "$1" || "$___C" "command returned $?: $1"
			shift
		done
		unset ___d ___D ___v ___X ___C; return 0
	fi
	# With command delimiter defined:
	___i=1; ___j=1; ___k=''; ___l=''
	while [ "$___j" -le "$#" ]; do
		eval "___k=\"\${$___j}\""
		if [ "$___k" = "$___d" ]; then
			if [ "$___i" != "$___j" ]; then
				___l="$(
					set -- "$___i" "$((___j-1))"
					while [ "$1" -le "$2" ]; do
						# shellcheck disable=SC2016
						printf ' "${%d}"' "$1"
						set -- "$(($1+1))" "$2"
					done)"
				[ "$___v" ] && eval "say \"invoking command:\"$___l"
				eval "invoke ${___X:+-x} -- $___l || $___C \"command returned \$?:\" $___l"
			fi
			___i="$((___j+1))"
		fi
		___j="$((___j+1))"
	done
	if [ "$___i" != "$___j" ]; then
		___l="$(
			set -- "$___i" "$((___j-1))"
			while [ "$1" -le "$2" ]; do
				# shellcheck disable=SC2016
				printf ' "${%d}"' "$1"
				set -- "$(($1+1))" "$2"
			done)"
		[ "$___v" ] && eval "say \"invoking command:\"$___l"
		eval "invoke ${___X:+-x} -- $___l || $___C \"command returned \$?:\" $___l"
	fi
	unset ___d ___D ___v ___X ___C ___i ___j ___k ___l
}

# Help and usage description listing all the available cmdstash commands:
cmdstash_usage() {
	printf '%s\n' "\
usage: $CMDSTASH_ARGZERO [-x] COMMAND [ARGS...]
       $CMDSTASH_ARGZERO -h|-c
options:   -h   display this help and exit
           -x   enable xtrace during command invocation
           -c   generate a Bash completion script and exit
" || return 1
	case "$(printf '%s\n' "$__CMDSTASH_CMDS" | sed '/^#/d;/^\t/d;/^$/d' | sed -n '$=')" in
		''|0)
			printf '%s\n' "no commands defined or missing \`__CMDSTASH__' marker line"
			return
	esac
	printf '%s\n' "commands (and aliases):"
	printf '%s\n' "$__CMDSTASH_CMDS" | sed -n '/^#/d; /^$/d;
/^>/ { s/^>/\n    > /p; :H { n; s/^>/    > /p; t H; } }
s/^\t/        /p; t;
s/^[^ ]* //; s/ /|/; s/ /||/g;
s/|/                                                  /;
/ /s/[^ ][^ ]*$/(&)/;
s/^\(..................................................\)  */\1  /;
/^..................................................[^ ]/s/  */  /;
s/||/, /g;
s/^/  /p;'
	ABOUT="$(trim "${ABOUT:-}")"
	if [ "$ABOUT" ]; then printf '\n%s\n' "$ABOUT"; fi
}

cmdstash_bash_completion_script() {
	if [ -t 1 ] && [ ! "${CMDSTASH_STDOUTISATTY:-}" ]; then
		say "cmdstash: unexpected: stdout is a tty"
		die "\
cmdstash: the completion script must be evaluated by the shell, try running:
    . <($CMDSTASH_ARGZERO -c)"
	fi
	# shellcheck disable=SC2016
	printf '%s\n' '__cmdstash_scripts_completion() {
	local _script="${COMP_WORDS[0]}"
	[[ -f "$_script" &&\
	   -x "$_script" &&\
	   "$_script" =~ .+/.+ &&\
	   -n "$(sed "/^#!/p;q" <"$_script")" &&\
	   -n "$(sed -n <"$_script" "s/^__CMDSTASH__//; t a; b;
:a s/^[[:blank:]]*\$//; t b; s/^[[:blank:]][[:blank:]]*#//; t b; b; :b =; q")" ]] || return 1
	case "${COMP_WORDS[COMP_CWORD]}" in
		/*|./*|../*)
			mapfile -t COMPREPLY <<<"$(compgen -f -- "${COMP_WORDS[COMP_CWORD]}")";;
		*)
			local __cmds
			__cmds="$(CMDSTASH_COMPLETION=bash "$_script" "-\$")"
			[[ "$__cmds" ]] && mapfile -t COMPREPLY <<<"$(compgen \
				-W "-h $__cmds" -- "${COMP_WORDS[COMP_CWORD]}")"
	esac
}
_cmdstash_complete() {
	local _c; for _c; do case "$_c" in
		""|*[!a-zA-Z0-9_.+-]*)
			echo >&2 "_cmdstash_complete: skipping unsupported script basename: $_c" ||:
			;;
		*)
			__cmdstash_completions+=("$_c")
			complete -F __cmdstash_scripts_completion -- "$_c" "./$_c"
			;;
	esac; done
}
_cmdstash_remove_completions() {
	local _c; for _c in "${__cmdstash_completions[@]}"; do
		complete -r -- "$_c" "./$_c"
	done
	unset __cmdstash_completions
}'
	printf '%s\n' "_cmdstash_complete $(quote "${CMDSTASH_ARGZERO##*/}")"
}

# Mark our functions as readonly if the shell supports it:
case ":$CMDSTASH_SHELLFEAT:" in *:readonlyfuncs:*)
	# shellcheck disable=SC3045  # `readonly -f' support is validated above
	readonly -f invoke chain cmdstash_usage
esac

# Inject the chain command definition:
[ "${CMDSTASH_NOCHAIN:-}" ] || {
: "${CMDSTASH_CHAINALIAS=ch}"  # default alias to the chain command
case " ${CMDSTASH_CHAINALIAS:-}" in *[!" "a-zA-Z0-9_.:@+-]*|*" "-*) \
die "cmdstash: invalid chain command alias definition: $CMDSTASH_CHAINALIAS";; esac
case "$(printf '%s\n' "$__CMDSTASH_CMDS" | sed '/^#/d;/^\t/d;/^$/d' | sed -n '$=')" in
	''|0);;
	*) __CMDSTASH_CMDS="$(printf '%s\n' "$__CMDSTASH_CMDS" | sed -n "
/^>/ { i\\
chain chain ${CMDSTASH_CHAINALIAS:-}\\
	invoke commands in sequence  (use \`chain -h' for more information)
b cont; }
\$ { a\\
chain chain ${CMDSTASH_CHAINALIAS:-}\\
	invoke commands in sequence  (use \`chain -h' for more information)
b cont; }
p; b; :cont { p; n; b cont; }")";;
esac
}

readonly __CMDSTASH_CMDS
unset __CMDSTASH_CURRENTSECTION
unset -f CMD _cmdstash_CMD CMDSECTION _cmdstash_CMDSECTION

# Check there is no duplicate commands
___v="$(
	printf '%s\n' "$__CMDSTASH_CMDS" \
	| sed '/^#/d; /^\t/d; /^$/d; s/^[^ ]* //;' \
	| sed ':a; N; $!ba; s/\n/ /g; s/  */ /g; s/^  *//; s/  *$//;')" || die
while [ "${___v#* }" != "${___v%% *}" ]; do
	case " ${___v#* } " in *" ${___v%% *} "*)
		die "cmdstash: duplicate definition for command or alias: ${___v%% *}";;
	esac
	___v="${___v#* }"
done
unset ___v

___x=''  # xtrace option
while [ "${1+x}" ]; do ___o="$1"; shift; case "$___o" in
	-x) ___x=x ;;
	-h) cmdstash_usage; exit "$?" ;;
	-c) cmdstash_bash_completion_script; exit "$?" ;;
	-\$) die "TODO: fix completion mechanism";;
	-[xhc\$]?*) set -- "${___o%"${___o#??}"}" "-${___o#??}" "$@" ;;
	--)  break ;;
	-?*) die "cmdstash: unknown option ${___o%"${___o#??}"}" ;;
	*)   set -- "$___o" "$@"; break ;;
esac; done; unset ___o
[ "${1+x}" ] || { cmdstash_usage>&2 ||:; exit 1; }

CMDSTASH_OPTS="${___x:+-x}"
readonly CMDSTASH_OPTS

___c="$(
case "$1" in
	''|-*|*[!a-zA-Z0-9_.:@+-]*) die "invalid command name: $1";;
	*.*) ___v="$(printf '%s' "$1" | sed 's/\./\\./g')" || die;;
	*) ___v="$1";;
esac
printf '%s\n\n' "$__CMDSTASH_CMDS" | sed -n '/^#/d; /^$/d; /^>/d;
/^[^[:blank:]]/{ s/$/ /; '"/ $___v /"'{
s/^\([^ ]*  *[^ ]*\).*/\1 /; N; s/\n\t//; t hlp; s/\n.*//; p
}; }; b; :hlp p; n; s/^\t//; t hlp' || die
)" || exit 1
[ "$___c" ] || die "unknown command: $1"
CMDFUNC="${___c%% *}"; CMD="${___c#"$CMDFUNC "}"; CMD="${CMD%%" "*}";
# shellcheck disable=SC2034  # CMDHELP is to be used by cmdstash scripts
CMDHELP="${___c#"$CMDFUNC $CMD "}"
unset ___c; shift
# shellcheck disable=SC2034  # CMDHELP is unused here but left for users
readonly CMD CMDFUNC CMDHELP

# Only allow commands to be shell functions and complains if not so:
[ "${CMDSTASH_NOCHECKCMDFUNC:-}" ] || case "$(command -v "$CMDFUNC" 2>/dev/null ||:)" in
	''|/*) die "cmdstash: $CMD: missing shell function: $CMDFUNC";;
esac

# Append the command name to the self contaxtual value for say/die:
__CMDSTASH_SELF="${CMDSTASH_ARGZERO##*/} $CMD"

# That's it, handle the xtrace option (if asked), run the command and exit:
if [ "$___x" ]; then unset ___x; set -x; else unset ___x; fi
"$CMDFUNC" "$@"
exit "$?"
