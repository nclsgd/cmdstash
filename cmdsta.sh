# shellcheck shell=sh
# shellcheck disable=SC2317,SC2329   # silence code unreachability warnings
# vim: set ft=sh ts=4 sw=4 noet ai tw=79:

# cmdstash: a portable and embeddable shell script micro-framework to create
#           handy command wrappers   <https://github.com/nclsgd/cmdstash>
# SPDX-License-Identifier: 0BSD
# Copyright (C) 2025 Nicolas Godinho <nicolas@godinho.me>

# Safer shell options:
# shellcheck disable=SC3040   # allow pipefail option usage in POSIX sh
set -eu; (set -o pipefail) 2>/dev/null && set -o pipefail

# Handy basic utility functions exposed in the cmdstash'ed scripts:
# shellcheck disable=SC2015   # yes, A && B || C is not if-then-else
say() { printf>&2 '%s:' "${__self__:-${CMDSTASH_ARGZERO:?}}" &&\
printf>&2 ' %s' "$@" && printf>&2 '\n' ||:; }
# shellcheck disable=SC2015   # yes, A && B || C is not if-then-else
die() { printf>&2 '%s:' "${__self__:-${CMDSTASH_ARGZERO:?}}" &&\
printf>&2 ' %s' "${@:-an error has occurred}" && printf>&2 '\n' ||:; exit 1; }
trim() { set -- "${1#"${1%%[![:space:]]*}"}" &&\
printf '%s' "${1%"${1##*[![:space:]]}"}"; }
quote() { while [ "${1+x}" ]; do printf '|%s|' "$1" | sed \
"s/'/'\\\\''/g; 1s/^|/'/; \$s/|\$/'/;${2+" \$s/\$/ /;"}"; shift; done; }

# Core logic follows:
CMDSTASH_ARGZERO="${0:?}"
# Handle zsh pure mode where $0 would be the cmdstash file and not the source:
if [ "${ZSH_ARGZERO:-}" ] && [ "$(PATH='' emulate 2>/dev/null)" = zsh ]; then
	CMDSTASH_ARGZERO="$ZSH_ARGZERO"
fi
readonly CMDSTASH_ARGZERO

: "${CMDSTASH_ORIGINALPWD:="${PWD:?}"}"
readonly CMDSTASH_ORIGINALPWD

CMDSTASH_SHELL="$(cd "$CMDSTASH_ORIGINALPWD" && sed <"$CMDSTASH_ARGZERO" 's/^#!//;q')"
CMDSTASH_SHELL="$(trim "$CMDSTASH_SHELL")"
case "$CMDSTASH_SHELL" in
	'') die "cmdstash: \$0 does not begin with a shebang: $CMDSTASH_ARGZERO";;
	[!/]*|*[!/a-zA-Z0-9_:,.\ +-]*)
		die "cmdstash: unexpected shebang read: #!$CMDSTASH_SHELL";;
esac
readonly CMDSTASH_SHELL

# Mark our functions as readonly if the shell supports it (Bash-only):
if [ "$(eval 2>/dev/null \
       'f(){ echo 1;};readonly>&2 -f f||:;f(){ echo 2;}||:;f||:')" = 1 ]; then
	# shellcheck disable=SC3045  # `readonly -f' support is validated above
	readonly -f say die trim quote
fi

__self__="${CMDSTASH_ARGZERO##*/}"
__COMMANDS__=''
unset ABOUT

# Declaring CMD (commands):
CMD() { __CMD__ "$@"; }
__CMD__() {
	___v=''  # function name behind the command
	while [ "${1+x}" ]; do ___o="$1"; shift; case "$___o" in
		-f)  [ "${1+x}" ] || die "CMD: missing function name"
		     [ ! "$___v" ] || die "CMD: cannot define function twice"
		     ___v="$1"; shift ;;
		-[f]?*) set -- "${___o%"${___o#??}"}" "${___o#??}" "$@" ;;
		--)  break ;;
		-?*) die "CMD: unknown option ${___o%"${___o#??}"}" ;;
		*)   set -- "$___o" "$@"; break ;;
	esac; done; unset ___o
	[ "${1+x}" ] || die "CMD: missing name"
	: "${___v:="$1"}"
	case "$___v" in
		''|-*|*[!a-zA-Z0-9_.:@+-]*) die "CMD: invalid command name: $1";;
		[!a-zA-Z_]*|*[!a-zA-Z0-9_]*)
			[ "$(eval 2>/dev/null "$___v(){ echo K;}&& $___v")" = K ] || die \
				"CMD: valid command name but illegal function name: $___v"
	esac
	__COMMANDS__="${__COMMANDS__:-"# cmdstash commands definition table, DO NOT EDIT!"}
$___v"  # no leading whitespace here!
	unset ___v
	while [ "${1+x}" ]; do
		case "$1" in
			--) shift; break ;;
			''|-*|*[!a-zA-Z0-9_.:@+-]*) die "CMD: invalid command name: $1";;
		esac
		__COMMANDS__="$__COMMANDS__ $1"; shift
	done
	if [ "${1+x}" ]; then __COMMANDS__="$__COMMANDS__
$(trim "$(printf '%s ' "$@")" | sed '/^[[:space:]]*$/d;s/^/\t/')"; fi
}

eval "$(cd "$CMDSTASH_ORIGINALPWD" && sed <"$CMDSTASH_ARGZERO" \
'1,/^###.* COMMANDS BELOW .*###$/d')"

# Ensure that errexit and nounset options are still enabled after the eval:
case "$-" in *e*);; *) die "cmdstash: the shell \`errexit' option (\`set -e')" \
"has been disabled by the script, this is unsupported by cmdstash";; esac
case "$-" in *e*);; *) die "cmdstash: the shell \`nounset' option (\`set -u')" \
"has been disabled by the script, this is unsupported by cmdstash";; esac

# Invoke another command from the cmdstash script (potentially wrapped by a
# function or command provided with the `-w' option):
invoke() {
	___w=''  # wrapper function or command
	___x=''  # whether to pass -x again
	while [ "${1+x}" ]; do ___o="$1"; shift; case "$___o" in
		-w)  [ "${1+x}" ] || die "invoke: missing wrapper function or command"
		     [ ! "$___w" ] || die "invoke: cannot define wrapper twice"
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
"${CMDSTASH_ORIGINALPWD:?}" \
${CMDSTASH_SHELL:?} "${CMDSTASH_ARGZERO:?}" ${CMDSTASH_OPTS?} \
${___x:+-x} -- "$@"
		unset ___w ___x
		"$@"
	else
		# shellcheck disable=SC2086  # word splitting is expected here
		set -- ${CMDSTASH_SHELL:?} "${CMDSTASH_ARGZERO:?}" ${CMDSTASH_OPTS?} \
${___x:+-x} -- "$@"
		unset ___w ___x
		( cd "${CMDSTASH_ORIGINALPWD:?}" && exec "$@" )
	fi
}

# Chain cmdstash commands:
readonly CMDSTASH_CHAIN_USAGE="\
invoke commands sequentially
  args:  [-d DELIMITER]  specify a (cautiously chosen) special
                         delimiter argument to allow using
                         arguments on chained commands
         [-v]    be verbose and print the invoked commands
         [-x]    enable xtrace on chain commands (implies -v)
"
chain() {
	___d=''  # the delimiter value
	___D=''  # is the delimiter defined?
	___v=''  # verbosity
	___X=''  # xtrace on invoked commands
	while [ "${1+x}" ]; do ___o="$1"; shift; case "$___o" in
		-d)  [ "${1+x}" ] || die "misused: missing delimiter"
		     [ ! "$___D" ] || die "misused: cannot define delimiter twice"
		     ___d="$1"; ___D=x; shift ;;
		-v)  ___v=x;;
		-x)  ___X=x; ___v=x;;
		-[d]?*) set -- "${___o%"${___o#??}"}" "${___o#??}" "$@" ;;
		-[vx]?*) set -- "${___o%"${___o#??}"}" "-${___o#??}" "$@" ;;
		--)  break ;;
		-?*) die "misused: unknown option ${___o%"${___o#??}"}" ;;
		*)   set -- "$___o" "$@"; break ;;
	esac; done; unset ___o
	[ "${1+x}" ] || die "no commands given"
	# Without command delimiter defined:
	if [ ! "$___D" ]; then
		while [ "${1+x}" ]; do
			[ "$___v" ] && say "invoking command: $1"
			invoke ${___X:+-x} -- "$1" || die "command returned $?: $1"
			shift
		done
		unset ___d ___D ___v ___X; return 0
	fi
	# With command delimiter defined:
	___i=1; ___j=1; ___k=''; ___l=''
	while [ "$___j" -le "$#" ]; do
		eval "___k=\"\${$___j}\""
		if [ "$___k" = "$___d" ]; then
			if [ "$___i" != "$___j" ]; then
				___l="$(set -- "$___i" "$((___j-1))"
				while [ "$1" -le "$2" ]; do
				# shellcheck disable=SC2016
				printf ' "${%d}"' "$1"; set -- "$(($1+1))" "$2"; done)"
				[ "$___v" ] && eval "say \"invoking command:\"$___l"
				eval "invoke ${___X:+-x} --$___l || die \"command returned \$?:\"$___l"
			fi
			___i="$((___j+1))"
		fi
		___j="$((___j+1))"
	done
	if [ "$___i" != "$___j" ]; then
		___l="$(set -- "$___i" "$((___j-1))"
		while [ "$1" -le "$2" ]; do
		# shellcheck disable=SC2016
		printf ' "${%d}"' "$1"; set -- "$(($1+1))" "$2"; done)"
		[ "$___v" ] && eval "say \"invoking command:\"$___l"
		eval "invoke ${___X:+-x} --$___l || die \"command returned \$?:\"$___l"
	fi
	unset ___d ___D ___v ___X ___i ___j ___k ___l
}

# Help and usage description listing all the available cmdstash commands:
usage() {
	set -- "$CMDSTASH_ARGZERO"
	printf '%s\n' "\
usage: $1 [-x] COMMAND [ARGS...]
       $1 -h|-c
options:
   -h   display this help and exit
   -x   enable xtrace during command invocation
   -c   generate a Bash completion script and exit
" || return 1
	[ "$__COMMANDS__" ] || { printf '%s\n' "no commands defined"; return; }
	printf '%s\n' "commands:"
	printf '%s\n' "$__COMMANDS__" | sed '/^#/d; /^$/d;
/^[^	]/{ s/^[^ ]* //; s/ /|/; s/ /||/g;
s/|/                                                  /;
/ /s/[^ ][^ ]*$/(&)/;
s/^\(..................................................\)  */\1  /;
/^..................................................[^ ]/s/  */  /;
s/||/, /g; s/^/  /; }; s/^\t/        /;'
	ABOUT="$(trim "${ABOUT:-}")"
	if [ "$ABOUT" ]; then printf '\n%s\n' "$ABOUT"; fi
}

cmdstash_bash_completion_script() {
	if [ -t 1 ] && [ ! "${CMDSTASH_STDOUTISATTY:-}" ]; then
		say "cmdstash: unexpected: stdout is a tty"
		die "cmdstash: the completion script must be evaluated by the shell, try running:
    eval \"\$($CMDSTASH_ARGZERO -c)\""
	fi
	# shellcheck disable=SC2016
	printf '%s\n' '__cmdstash_scripts_completion() {
	local _script="${COMP_WORDS[0]}"
	if ! [[ -f "$_script" && -x "$_script" && "$_script" =~ .+/.+ &&
	        -n "$(sed "/^#!/p;q" < "$_script")" &&
	        -n "$(sed "/^###.* COMMANDS BELOW .*###$/!d" < "$_script")" ]]; then
		return 1
	fi
	case "${COMP_WORDS[COMP_CWORD]}" in
		/*|./*|../*) mapfile -t COMPREPLY <<<"$(compgen -f \
-- "${COMP_WORDS[COMP_CWORD]}")";;
		*) local __cmds
__cmds="$(CMDSTASH_COMPLETION=bash "$_script" -h 2>/dev/null | sed \
"1,/^commands:\$/d; /^\$/,\$d; /^    */d; s/^  //; s/ .*//;")"
[[ "$__cmds" ]] && mapfile -t COMPREPLY <<<"$(compgen \
-W "-h $__cmds" -- "${COMP_WORDS[COMP_CWORD]}")"
	esac
}
_cmdstash_complete() {
	local _c; for _c; do
		case "$_c" in
			""|*[!a-zA-Z0-9_.+-]*) echo >&2 \
"_cmdstash_complete: skipping unsupported script basename: $_c" ||: ;;
			*) __cmdstash_completions+=("$_c")
complete -F __cmdstash_scripts_completion -- "$_c" "./$_c" ;;
		esac
	done
}
_cmdstash_remove_completions() {
	local _c; for _c in "${__cmdstash_completions[@]}"; do
		complete -r -- "$_c" "./$_c"
	done
	unset __cmdstash_completions
}'
	printf '%s\n' "_cmdstash_complete $(quote "${CMDSTASH_ARGZERO##*/}")"
}

# Mark our functions as readonly if the shell supports it (Bash-only):
if [ "$(eval 2>/dev/null \
       'f(){ echo 1;};readonly>&2 -f f||:;f(){ echo 2;}||:;f||:')" = 1 ]; then
	# shellcheck disable=SC3045  # `readonly -f' support is validated above
	readonly -f invoke chain usage
fi

# Expose the chain command if there are more than two commands defined:
# shellcheck disable=SC2086  # word splitting is expected here
case "$(printf '%s\n' "$__COMMANDS__" | sed '/^#/d;/^\t/d;/^$/d' | sed -n '$=')" in
	''|0|1);;
	*) [ "${CMDSTASH_CHAIN_NOCMD:-0}" = 0 ] &&\
		CMD chain ${CMDSTASH_CHAIN_ALIAS:-} -- "$CMDSTASH_CHAIN_USAGE";;
esac

readonly __COMMANDS__
unset -f CMD __CMD__

# Check there is no duplicate commands
___v="$(printf '%s\n' "$__COMMANDS__" \
	| sed '/^#/d; /^\t/d; /^$/d; s/^[^ ]* //;' \
	| sed ':a; N; $!ba; s/\n/ /g; s/  */ /g; s/^  *//; s/  *$//;')"
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
	-h) usage; exit "$?" ;;
	-c) cmdstash_bash_completion_script; exit "$?" ;;
	-[xhc]?*) set -- "${___o%"${___o#??}"}" "-${___o#??}" "$@" ;;
	--)  break ;;
	-?*) die "cmdstash: unknown option ${___o%"${___o#??}"}" ;;
	*)   set -- "$___o" "$@"; break ;;
esac; done; unset ___o
[ "${1+x}" ] || { usage>&2||:;exit 1; }

CMDSTASH_OPTS="${___x:+-x}"
readonly CMDSTASH_OPTS

___c="$(
case "$1" in
	''|-*|*[!a-zA-Z0-9_.:@+-]*) die "invalid command name: $1";;
	*.*) ___v="$(printf '%s' "$1"|sed 's/\./\\./g')";;
	*) ___v="$1";;
esac
printf '%s\n' "$__COMMANDS__" | sed -n '/^#/d; /^$/d;
/^[^	]/{ s/$/ /; '"/ $___v /"'{
s/^\([^ ]*  *[^ ]*\).*/\1 /; N; s/\n\t//; t USAGE; s/\n.*//; p
}; }; b; :USAGE p; n; s/^\t//; t USAGE'
)" || exit 1
[ "$___c" ] || die "unknown command: $1"
CMDFUNC="${___c%% *}"; CMD="${___c#"$CMDFUNC "}"; CMD="${CMD%%" "*}";
# shellcheck disable=SC2034  # CMDUSAGE is to be used by cmdstash'ed scripts
CMDUSAGE="${___c#"$CMDFUNC $CMD "}"
unset ___c; shift
readonly CMD CMDFUNC CMDUSAGE
__self__="${CMDSTASH_ARGZERO##*/} $CMD"

if [ "$___x" ]; then unset ___x; set -x; else unset ___x; fi
"$CMDFUNC" "$@"
exit "$?"
