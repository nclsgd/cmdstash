# shellcheck shell=sh
# shellcheck disable=SC2317   # silence code unreachability warnings
# vim: set ft=sh ts=4 sw=4 noet ai tw=79:

# cmdstash: a portable and embeddable shell script micro-framework to create
#           handy command wrappers   <https://github.com/nclsgd/cmdstash>
# SPDX-License-Identifier: 0BSD
# Copyright (C) 2025 Nicolas Godinho <nicolas@godinho.me>

# Safer shell options:
# shellcheck disable=SC3040   # allow pipefail option usage in POSIX sh
set -eu; (set -o pipefail) 2>/dev/null && set -o pipefail

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

CMD() { __CMD__ "$@"; }
__CMD__() {
	___v=''
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
		''|[0-9]*|*[!a-zA-Z0-9_]*) die "CMD: illegal function name: $___v";;
	esac
	__COMMANDS__="${__COMMANDS__:-"# cmdstash commands definition table, DO NOT EDIT!"}
$___v"  # no leading whitespace here!
	unset ___v
	while [ "${1+x}" ]; do
		case "$1" in
			--) shift; break ;;
			''|-*|*[!a-zA-Z0-9_.:@+-]*) die "CMD: invalid command name: $1";;
			*.*) ___v="$(printf '%s' "$1"|sed 's/\./\\./g')" ;;
			*) ___v="$1" ;;
		esac
		if [ "$(printf '%s\n' "$__COMMANDS__" | sed -n \
'/^#/d; /^\t/d; /^$/d; s/$/ /;'"/ $___v /{p;q}")" ]; then
			die "CMD: already defined command: $1"
		fi
		__COMMANDS__="$__COMMANDS__ $1"; shift
	done
	unset ___v
	if [ "${1+x}" ]; then __COMMANDS__="$__COMMANDS__
$(trim "$(printf '%s ' "$@")" | sed '/^[[:space:]]*$/d;s/^/\t/')"; fi
}

# Function to invoke another command from within the cmdstash script:
invoke() {
	[ "${1+x}" ] || die "invoke: missing command"
	# shellcheck disable=SC2046  # word splitting is OK here
	(cd "${CMDSTASH_ORIGINALPWD:?}" &&\
		exec ${CMDSTASH_SHELL:?} "${CMDSTASH_ARGZERO:?}" \
		$(case "$-" in *x*) printf '%s' '-x';; esac) \
		"$@")
}

# WARNING! Invoking cmdstash commands with this function MUST **NOT** be done
# within a conditional command compound construct (whether direct or somehow
# nested in function calls) since such constructs impede the errexit shell
# option behavior.  Therefore invoking with this function a command that relies
# on the errexit shell option to catch errors and within a conditional command
# compound WILL misbehave and MAY cause harmful bugs.
# Please use this function with caution or prefer the safer `invoke' function.
_invoke_unsafe() {
	[ "${1+x}" ] || die "_invoke_unsafe: missing command"
	( CMDFUNC="$(case "$1" in
		''|-*|*[!a-zA-Z0-9_.:@+-]*)
			die "_invoke_unsafe: invalid command name: $1";;
		*.*) ___v="$(printf '%s' "$1"|sed 's/\./\\./g')" || die;;
		*) ___v="$1" || die;;
	esac; printf '%s\n' "$__COMMANDS__" | sed -n \
'/^#/d; /^\t/d; /^$/d; s/$/ /;'"/ $___v /"'{s/^\([^ ]*\).*/\1/p;q;}')" || die
	CMD="$1" || die; shift || die
	[ "$CMDFUNC" ] || die "_invoke_unsafe: unknown command: $CMD"
	__self__="$CMDSTASH_ARGZERO $CMD"
	"$CMDFUNC" "$@" )
}

# Chain cmdstash commands:
# shellcheck disable=SC2034  # unused variable to be used by downstream
CMDSTASH_CHAIN_USAGE="\
invoke commands sequentially
  args:  [-d DELIMITER]  specify a (cautiously chosen) special
                         delimiter argument to allow using
                         arguments on chained commands"
chain() {
	___d=''; ___v=''
	while [ "${1+x}" ]; do ___o="$1"; shift; case "$___o" in
		-d)  [ "${1+x}" ] || die "misused: missing delimiter"
		     [ ! "$___v" ] || die "misused: cannot define delimiter twice"
		     ___d="$1"; ___v=x; shift ;;
		-[d]?*) set -- "${___o%"${___o#??}"}" "${___o#??}" "$@" ;;
		--)  break ;;
		-?*) die "misused: unknown option ${___o%"${___o#??}"}" ;;
		*)   set -- "$___o" "$@"; break ;;
	esac; done; unset ___o
	[ "${1+x}" ] || die "no commands given"
	# Without command delimiter defined:
	if [ ! "$___v" ]; then
		while [ "${1+x}" ]; do
			invoke "$1" || die "command returned $?: $1"
			shift
		done
		return 0
	fi
	# With command delimiter defined:
	___i=1; ___j=1; ___x=''; ___v=''
	while [ "$___j" -le "$#" ]; do
		eval "___x=\"\${$___j}\""
		if [ "$___x" = "$___d" ]; then
			if [ "$___i" != "$___j" ]; then
				___v="$(set -- "$___i" "$((___j-1))"
				while [ "$1" -le "$2" ]; do
				# shellcheck disable=SC2016
				printf ' "${%d}"' "$1"; set -- "$(($1+1))" "$2"; done)"
				eval "invoke$___v || die \"command returned \$?:\"$___v"
			fi
			___i="$((___j+1))"
		fi
		___j="$((___j+1))"
	done
	if [ "$___i" != "$___j" ]; then
		___v="$(set -- "$___i" "$((___j-1))"
		while [ "$1" -le "$2" ]; do
		# shellcheck disable=SC2016
		printf ' "${%d}"' "$1"; set -- "$(($1+1))" "$2"; done)"
		eval "invoke$___v || die \"command returned \$?:\"$___v"
	fi
	unset ___v
}

# Help and usage description listing all the available cmdstash commands:
usage() {
	set -- "$CMDSTASH_ARGZERO"
	printf '%s\n' "\
usage:  $1 [-x] COMMAND [ARG...]  invoke the command  [-x enables xtrace]
        $1 -h                     display this help and exit" || return 1
	[ "$__COMMANDS__" ] || { printf '%s\n' "no commands defined"; return; }
	printf '%s\n' "commands:"
	printf '%s\n' "$__COMMANDS__" | sed '/^#/d; /^$/d;
/^[^	]/{ s/^[^ ]*//; s/^ //; s/ /, /g; s/^/  /; }; s/^	/        /;'
	ABOUT="$(trim "${ABOUT:-}")"
	if [ "$ABOUT" ]; then printf '\n%s\n' "$ABOUT"; fi
}

# Core logic follows:
: "${CMDSTASH_ORIGINALPWD:="${PWD:?}"}"
readonly CMDSTASH_ORIGINALPWD

CMDSTASH_ARGZERO="${0:?}"
# Handle zsh pure mode where $0 would be the cmdstash file and not the source:
if [ "${ZSH_ARGZERO:-}" ] && [ "$(PATH='' emulate 2>/dev/null)" = zsh ]; then
	CMDSTASH_ARGZERO="$ZSH_ARGZERO"
fi
readonly CMDSTASH_ARGZERO

CMDSTASH_SHELL="$(cd "$CMDSTASH_ORIGINALPWD" && sed <"$CMDSTASH_ARGZERO" 's/^#!//;q')"
CMDSTASH_SHELL="$(trim "$CMDSTASH_SHELL")"
case "$CMDSTASH_SHELL" in
	'') die "\$0 does not seem to be a shell script file: $CMDSTASH_ARGZERO";;
	[!/]*|*[!/a-zA-Z0-9_:,.\ +-]*) die "\$0 has an unexpected shebang: $CMDSTASH_SHELL";;
esac
readonly CMDSTASH_SHELL

__self__="$CMDSTASH_ARGZERO"
__COMMANDS__=''
unset ABOUT

# Mark our functions as readonly if the shell supports it (Bash-only):
if [ "$(eval 2>/dev/null \
       'f(){ echo 1;};readonly>&2 -f f||:;f(){ echo 2;}||:;f||:')" = 1 ]; then
	# shellcheck disable=SC3045  # `readonly -f' support is validated above
	readonly -f say die trim quote invoke chain usage
fi

eval "$(cd "$CMDSTASH_ORIGINALPWD" && sed <"$CMDSTASH_ARGZERO" \
'1,/^###.* COMMANDS BELOW .*###$/d')"

# Ensure that errexit and nounset options are still enabled after the eval:
case "$-" in *e*);; *) die "errexit option (set -e) was disabled";; esac
case "$-" in *u*);; *) die "nounset option (set -u) was disabled";; esac

readonly __COMMANDS__
unset -f CMD __CMD__

___x=''
while [ "${1+x}" ]; do ___o="$1"; shift; case "$___o" in
	-x) ___x=x ;;
	-h) usage; exit "$?" ;;
	-[xh]?*) set -- "${___o%"${___o#??}"}" "-${___o#??}" "$@" ;;
	--)  break ;;
	-?*) die "unknown option ${___o%"${___o#??}"}" ;;
	*)   set -- "$___o" "$@"; break ;;
esac; done; unset ___o
[ "${1+x}" ] || { usage>&2||:;exit 1; }

CMDFUNC="$(
case "$1" in
	''|-*|*[!a-zA-Z0-9_.:@+-]*) die "invalid command name: $1";;
	*.*) ___v="$(printf '%s' "$1"|sed 's/\./\\./g')";;
	*) ___v="$1";;
esac
printf '%s\n' "$__COMMANDS__" | sed -n \
'/^#/d; /^\t/d; /^$/d; s/$/ /;'"/ $___v /"'{s/^\([^ ]*\).*/\1/p;q;}'
)"
CMD="$1"
shift
[ "$CMDFUNC" ] || die "unknown command: $CMD"
__self__="$__self__ $CMD"

if [ "$___x" ]; then unset ___x; set -x; else unset ___x; fi
"$CMDFUNC" "$@"
exit "$?"

# ----------------------------------------------------------------------------

### BEGIN BASH COMPLETION ###

# shellcheck disable=SC3010  # [[ is Bash
# shellcheck disable=SC3011  # here-strings are Bash
# shellcheck disable=SC3043  # local keyword is Bash
# shellcheck disable=SC3044  # mapfile is Bash
# shellcheck disable=SC3054  # arrays are Bash
__cmdstash_scripts_completion() {
	# For some shell keyword, complete with commands:
	case "${COMP_WORDS[0]:-}" in
		do|then|command|exec) _comp_command "$@"; return "$?";;
		*/*);; *) return 0;;
	esac

	# Bail out if command is not a shell script with the expected boundary line
	local _script="${COMP_WORDS[0]}"
	[[ -f "$_script" && -x "$_script" && "$(sed '/^!#.*sh/p;q' < "$_script")" &&
		"$(sed '/^###.* COMMANDS BELOW .*###$/!d' < "$_script")" ]] || return 1

	local __cmds
	__cmds="$(_CMDSTASH_COMPLETION=bash "$_script" -h 2>/dev/null | sed \
'1,/^commands:$/d; /^$/,$d; /^    */d; s/, /\n/g; s/   *(/\n/; s/)$//; s/^  //;')"
	mapfile -t COMPREPLY <<< "$(compgen -W "-h $__cmds" -- "${COMP_WORDS[COMP_CWORD]}" )"
}

# shellcheck disable=SC3044  # complete is Bash
_cmdstash_complete() { complete -F __cmdstash_scripts_completion "$@"; }

### END BASH COMPLETION ###
