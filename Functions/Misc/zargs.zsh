# function zargs {
#
# This function works like GNU xargs, except that instead of reading lines
# of arguments from the standard input, it takes them from the command
# line.  This is possible/useful because, especially with recursive glob
# operators, zsh often can construct a command line for a shell function
# that is longer than can be accepted by an external command.
#
# Like xargs, zargs exits with the following status:
#   0 if it succeeds
#   123 if any invocation of the command exited with status 1-125
#   124 if the command exited with status 255
#   125 if the command is killed by a signal
#   126 if the command cannot be run
#   127 if the command is not found
#   1 if some other error occurred.
#
# The full set of GNU xargs options is supported (see help text below);
# although --eof and --max-lines therefore have odd names, they have
# analogous meanings to their xargs counterparts.  Also zargs --help is
# a lot more helpful than xargs --help, at least as of xargs 4.1.
#
# Note that "--" is used both to end the options and to begin the command,
# so to specify some options along with an empty set of input-args, one
# must repeat the "--" as TWO consecutive arguments, e.g.:
#   zargs --verbose -- -- print There are no input-args
# If there is at least one input-arg, the first "--" may be omitted:
#   zargs -p -i one -- print There is just {} input-arg
# Obviously, if there is no command, the second "--" may be omitted:
#   zargs -n2 These words will be echoed in five lines of two
#
# BUGS:
#
# In the interests of expediency, numeric options (max-procs, max-lines,
# etc.) are range-checked only when their values make a difference to the
# end result.  Because of the way zsh handles variables in math context,
# it's possible to pass the name of a variable as the value of a numeric
# option, and the value of that variable becomes the value of the option.
#
# "Killed by a signal" is determined by the usual shell rule that $? is
# the signal number plus 128, so zargs can be fooled by a command that
# explicitly exits with 129+.  Also, zsh prior to 4.1.x returns 1 rather
# than 127 for "command not found" so this function incorrectly returns
# 123 in that case if used with zsh 4.0.x.
#
# With the --max-procs option, zargs may not correctly capture the exit
# status of the backgrounded jobs, because of limitations of the "wait"
# builtin.  If the zsh/parameter module is not available, the status is
# NEVER correctly returned, otherwise the status of the longest-running
# job in each batch is captured.
#
# Also because of "wait" limitations, --max-procs spawns max-procs jobs,
# then waits for all of those, then spawns another batch, etc.
#
# Differences from POSIX xargs:
#
# * POSIX requires a space between -I/-L/-n/-s and their numeric argument;
#   zargs uses zparseopts, which does not require the space.
#
# * POSIX -L and -n are mutually exclusive and effectively synonymous;
#   zargs accepts both and considers -n to be a limit on the total number
#   of arguments per command line, that is, including the initial-args.
#   Thus the following fails with "argument list too long":
#     zargs -n 3 -- echo Here are four words
#   The smallest limit implied by the combination of -L and -n is used.
#
# * POSIX implies the last of -n/-i/-I/-l/-L on the command line is meant
#   to cancel any of those that precede it.  (This is unspecified for
#   -I/-L and implementations reportedly differ.)  In zargs, -i/-I have
#   this behavior, as do -l/-L, but when -i/-I appear anywhere then -l/-L
#   are ignored (forced to 1).

emulate -L zsh || return 1
local -a opts eof n s l P i

local ZARGS_VERSION="1.5"

if zparseopts -a opts -D -- \
	-eof::=eof e::=eof \
	-exit x \
	-help \
	-interactive p \
	-max-args:=n n:=n \
	-max-chars:=s s:=s \
	-max-lines::=l l::=l L:=l \
	-max-procs:=P P:=P \
	-no-run-if-empty r \
	-null 0 \
	-replace::=i i::=i I:=i \
	-verbose t \
	-version
then
    if (( $opts[(I)--version] ))
    then
	print -u2 zargs version $ZARGS_VERSION zsh $ZSH_VERSION
    fi
    if (( $opts[(I)--help] ))
    then
	>&2 <<-\HELP
	Usage: zargs [options --] [input-args] [-- command [initial-args]]

	If command and initial-args are omitted, "print -r --" is used.

	Options:
	--eof[=eof-str], -e[eof-str]
	    Change the end-of-input-args string from "--" to eof-str.  If
	    given as --eof=, an empty argument is the end; as --eof or -e,
	    with no (or an empty) eof-str, all arguments are input-args.
	--exit, -x
	    Exit if the size (see --max-chars) is exceeded.
	--help
	    Print this summary and exit.
	--interactive, -p
	    Prompt before executing each command line.
	--max-args=max-args, -n max-args
	    Use at most max-args arguments per command line.
	--max-chars=max-chars, -s max-chars
	    Use at most max-chars characters per command line.
	--max-lines[=max-lines], -l[max-lines]
	    Use at most max-lines of the input-args per command line.
	    This option is misnamed for xargs compatibility.
	--max-procs=max-procs, -P max-procs
	    Run up to max-procs command lines in the background at once.
	--no-run-if-empty, -r
	    Do nothing if there are no input arguments before the eof-str.
	--null, -0
	    Split each input-arg at null bytes, for xargs compatibility.
	--replace[=replace-str], -i[replace-str]
	    Substitute replace-str in the initial-args by each initial-arg.
	    Implies --exit --max-lines=1.
	--verbose, -t
	    Print each command line to stderr before executing it.
	--version
	    Print the version number of zargs and exit.
HELP
	return 0
    fi
    if (( $opts[(I)--version] ))
    then
	return 0
    fi
    if (( $#i ))
    then
	l=1
	i=${${${i##-(i|I|-replace(=|))}[-1]}:-\{\}}
	opts[(r)-x]=-x
	# The following is not how xargs is documented,
	# but GNU xargs does behave as if -i implies -r.
	opts[(r)-r]=-r
    fi
    if (( $#P ))
    then
	P=${${P##-(P|-max-procs(=|))}:-1}
	if [[ x${P} != x$[P] ]]
	then
	    print -u2 zargs: invalid number for -P option
	    return 1
	fi
    else P=1
    fi
else
    return 1
fi

local -i end c=0
if [[ $eof == -(e|-eof) ]]; then ((end=ARGC+1))
elif (( $#eof )); then end=$argv[(i)${eof##-(e|-eof=)}]
else end=$argv[(i)--]
fi
local -a args call command; command=( "${(@)argv[end+1,-1]}" )

if (( $opts[(I)-(null|0)] ))
then set -- "${(@ps:\000:)argv[1,end-1]}"
else set -- "${(@)argv[1,end-1]}"
fi

if (( $#command ))
then (( c = $#command - 1 ))
else command=( print -r -- )
fi

local wait bg
local execute='
    if (( $opts[(I)-(-interactive|p)] ))
    then read -q "?$call?..." || continue
    elif (( $opts[(I)-(-verbose|t)] ))
    then print -u2 -r -- "$call"
    fi
    eval "{
	\"\${(@)call}\"
    } $bg"'
local ret=0 analyze='
    case $? in
    (0) ;;
    (<1-125>|128)  ret=123;;
    (255)       return 124;;
    (<129-254>) return 125;;
    (126)       return 126;;
    (127)       return 127;;
    (*)         return 1;;
    esac'

if (( ARGC == 0 ))
then
    if (( $opts[(I)-(-no-run-if-empty|r)] ))
    then return 0
    else
	call=($command)
	# Use "repeat" here so "continue" won't complain.
	repeat 1; do eval "$execute ; $analyze"; done
	return $ret
    fi
fi

n=${${n##-(n|-max-args(=|))}:-$[ARGC+c]}
if (( n <= 0 ))
then
    print -u2 'zargs: value for max-args must be >= 1'
    return 1
fi

if (( n > c ))
then (( n -= c ))
else
    print -u2 zargs: argument list too long
    return 1
fi

s=${${s##-(s|-max-chars(=|))}:-20480}
if (( s <= 0 ))
then
    print -u2 'zargs: value for max-chars must be >= 1'
    return 1
fi

l=${${${l##*-(l|L|-max-lines(=|))}[-1]}:-${${l[1]:+1}:-$ARGC}}
if (( l <= 0 ))
then
    print -u2 'zargs: value for max-lines must be >= 1'
    return 1
fi

P=${${P##-(P|-max-procs(=|))}:-1}
if (( P < 0 ))
then
    print -u2 'zargs: value for max-procs must be >= 0'
    return 1
fi

if (( P != 1 && ARGC > 1 ))
then
    # These setopts are necessary for "wait" on multiple jobs to work.
    setopt nonotify nomonitor
    bg='&'
    if zmodload -i zsh/parameter 2>/dev/null
    then
	wait='wait ${${jobstates[(R)running:*]/#*:/}/%=*/}'
    else
	wait='wait'
    fi
fi

# Everything has to be in a subshell just in case of backgrounding jobs,
# so that we don't unintentionally "wait" for jobs of the parent shell.
(

while ((ARGC))
do
    if (( P == 0 || P > ARGC ))
    then (( P = ARGC ))
    fi

    repeat $P
    do
	((ARGC)) || break
	for (( end=l; end && ${(c)#argv[1,end]} > s; end/=2 )) { }
	(( end > n && ( end = n ) ))
	args=( "${(@)argv[1,end]}" )
	shift $((end > ARGC ? ARGC : end))
	if (( $#i ))
	then call=( "${(@)command/$i/$args}" )
	else call=( "${(@)command}" "${(@)args}" )
	fi
	if (( ${(c)#call} > s ))
	then
	    print -u2 zargs: cannot fit single argument within size limit
	    # GNU xargs exits here whether or not -x,
	    # but that just makes the option useless.
	    (( $opts[(I)-(-exit|x)] )) && return 1
	    continue
	else
	    eval "$execute"
	fi
    done

    eval "$wait
	$analyze"
done
return $ret

)

# }
