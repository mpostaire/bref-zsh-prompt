# BREF PROMPT

# Get config
BREF_SHOW_BATTERY_BINDING=${BREF_SHOW_BATTERY_BINDING:-'^B'}

# TODO I'm not sure about the colors of the icons below...
BREF_GIT_AHEAD=${BREF_GIT_AHEAD:-'%F{red}⇡'}
BREF_GIT_BEHIND=${BREF_GIT_BEHIND:-'%F{cyan}⇣'}
BREF_GIT_MERGING=${BREF_GIT_MERGING:-'%F{magenta}✖'}
BREF_GIT_STAGED=${BREF_GIT_STAGED:-'%F{green}⦁'}
BREF_GIT_UNTRACKED=${BREF_GIT_UNTRACKED:-'%F{yellow}?'}
BREF_GIT_MODIFIED=${BREF_GIT_MODIFIED:-'%F{yellow}!'}
BREF_GIT_STASHED=${BREF_GIT_STASHED:-'%F{gray}*'}

BREF_GIT_COLOR=${BREF_GIT_COLOR:-'%F{15}'}
BREF_CODE_COLOR=${BREF_CODE_COLOR:-'%F{red}'}
BREF_SSH_COLOR=${BREF_SSH_COLOR:-'%F{magenta}'}
BREF_JOBS_COLOR=${BREF_JOBS_COLOR:-'%F{yellow}'}
BREF_BATTERY_COLOR=${BREF_BATTERY_COLOR:-'%F{11}'}

# Spelling prompt
SPROMPT="Correct %F{red}'%R'%f to %F{green}'%r'%f [Yes, No, Abort, Edit]? "

# _bref_git_info taken and modified from https://joshdick.net/2017/06/08/my_git_prompt_for_zsh_revisited.html
# Echoes information about Git repository status when inside a Git repository
_bref_git_info() {
    # Exit if not inside a Git repository
    ! git rev-parse --is-inside-work-tree > /dev/null 2>&1 && return

    # Git branch/tag, or name-rev if on detached head
    local GIT_LOCATION=${$(git symbolic-ref -q HEAD || git name-rev --name-only --no-undefined --always HEAD)#(refs/heads/|tags/)}

    local -a DIVERGENCES
    local -a FLAGS

    local NUM_AHEAD="$(git log --oneline @{u}.. 2> /dev/null | wc -l | tr -d ' ')"
    if [ "${NUM_AHEAD}" -gt 0 ]; then
        local AHEAD="${BREF_GIT_AHEAD}NUM"
        DIVERGENCES+=( "${AHEAD//NUM/${NUM_AHEAD}}" )
    fi

    local NUM_BEHIND="$(git log --oneline ..@{u} 2> /dev/null | wc -l | tr -d ' ')"
    if [ "${NUM_BEHIND}" -gt 0 ]; then
        local BEHIND="${BREF_GIT_BEHIND}NUM"
        DIVERGENCES+=( "${BEHIND//NUM/${NUM_BEHIND}}" )
    fi

    local GIT_DIR="$(git rev-parse --git-dir 2> /dev/null)"
    if [ -n ${GIT_DIR} ] && test -r ${GIT_DIR}/MERGE_HEAD; then
        FLAGS+=( "${BREF_GIT_MERGING}" )
    fi

    if ! git diff --cached --quiet 2> /dev/null; then
        FLAGS+=( "${BREF_GIT_STAGED}" )
    fi

    if ! git diff --quiet 2> /dev/null; then
        FLAGS+=( "${BREF_GIT_MODIFIED}" )
    fi
    
    if [[ -n $(git ls-files --others --exclude-standard 2> /dev/null) ]]; then
        FLAGS+=( "${BREF_GIT_UNTRACKED}" )
    fi

    if [[ -n $(git stash list 2> /dev/null) ]]; then
        FLAGS+=( "${BREF_GIT_STASHED}" )
    fi

    local GIT_INFO=( "${BREF_GIT_COLOR}(${GIT_LOCATION}" )
    [ -n "${GIT_STATUS}" ] && GIT_INFO+=( "${GIT_STATUS}" )
    [[ ${#DIVERGENCES[@]} -ne 0 ]] && GIT_INFO+=( "${(j::)DIVERGENCES}" )
    [[ ${#FLAGS[@]} -ne 0 ]] && GIT_INFO+=( "${(j::)FLAGS}" )
    print "${(j: :)GIT_INFO}${BREF_GIT_COLOR})%f%b%u%s%k"
}

# Correct the prompt when PWD is big
_bref_format_path() {
    # colorize path differently if it's a link
    local path_color="%F{blue}"
    if [[ $(readlink -f ${PWD}) != ${PWD} ]]; then
        path_color="%F{cyan}"
    fi

    local newline="%(?:%F{green}:%F{red})\n│${path_color} "
    (( width = ${COLUMNS} - 3 )) # available drawing width space (-3 because of the newline bar + space and 1 free space at the end)
    local user_hostname=$(print -P "┌ %n@%M:  ")
    (( width1st = ${COLUMNS} - ${#user_hostname} )) # available drawing width space for the first line (containing the user@hostane info)

    local rest=$(print -P %~) # the remaining path to format (initialized to the full path)
    if [[ ${#rest} -le ${width1st} ]]; then
        result=${path_color}${rest}
    else
        if [[ ${width1st} -le 0 ]]; then # when terminal too small don't show PWD
            return 0
        fi
        # first line is special
        local temp=${rest:0:${width1st}} # get the beginning of the line
        rest=${rest:${width1st}} # get the remaining

        local result=${path_color}${temp}
        while [[ ${#rest} -gt ${width} ]]; do
            temp=${rest:0:${width}}
            rest=${rest:${width}}
            result=${result}${newline}${path_color}${temp}
        done
        result=${result}${newline}${path_color}${rest}
    fi

    print ${result}
}

_bref_rprompt_async_proc=0
_bref_make_prompt() {
    ### PROMPT ###

    PROMPT="%B%(?:%F{green}:%F{red})┌ %F{green}%n@%M: $(_bref_format_path)
%(?:%F{green}:%F{red})└ %(?:%F{green}%(#:#:$):%F{red}%(#:#:$))%f%b "

    ### RPROMPT ###

    # put the battery status in rprompt if it's present and enabled or in virtual console
    if [[ -r /sys/class/power_supply/BAT0/capacity && ( $(<${_bref_zsh_prompt_path}/bref_battery_visible) -eq 1 || ${TERM} = "linux" ) ]]; then
        (( $(</sys/class/power_supply/AC/online) )) && local bat_charge=+ || local bat_charge=
        RPROMPT=" ${BREF_BATTERY_COLOR}[$(</sys/class/power_supply/BAT0/capacity)${bat_charge}]%f"
    else
        RPROMPT=''
    fi
    # put the return value in rprompt if it is > 0
    RPROMPT="%(?:: ${BREF_CODE_COLOR}[%?]%f%b%u%s%k)${RPROMPT}"
    # put a ssh notification in rprompt if we are in a ssh session
    [[ -n ${SSH_CONNECTION-}${SSH_CLIENT-}${SSH_TTY-} ]] && RPROMPT=" ${BREF_SSH_COLOR}(ssh)%f%b%u%s%k${RPROMPT}"
    # put the number of running background jobs in rprompt if there are any
    RPROMPT="%(1j: ${BREF_JOBS_COLOR}%jj%f:)${RPROMPT}"
    
    # Use cached git status instead of generating a new one if $1 is set
    if [[ -n ${1} ]]; then
        RPROMPT="${_bref_git_status}${RPROMPT}"
        return
    fi

    # Retreive git status asynchronously

    async() {
        # save to temp file
        printf "%s" "$(_bref_git_info)" > "/tmp/zsh_bref_$$"

        # signal parent
        kill -s USR1 $$
    }

    # do not clear RPROMPT, let it persist

    # kill child if necessary
    if [[ "${_bref_rprompt_async_proc}" != 0 ]]; then
        kill -s HUP ${_bref_rprompt_async_proc} >/dev/null 2>&1 || :
    fi

    # start background computation
    async &!
    _bref_rprompt_async_proc=$!
}

# Called when git status has been generated
TRAPUSR1() {
    # read from temp file
    _bref_git_status="$(</tmp/zsh_bref_$$)"
    RPROMPT="${_bref_git_status}${RPROMPT}"

    # reset proc number
    rm /tmp/zsh_bref_$$
    _bref_rprompt_async_proc=0

    # redisplay
    zle && zle reset-prompt
}

# Redraw prompt on terminal resize
TRAPWINCH () {
    _bref_make_prompt 0 # pass any argument to use cached git status
    zle && zle reset-prompt
}

_bref_toggle_battery() {
    if [ $(<${_bref_zsh_prompt_path}/bref_battery_visible) -eq 0 ]; then
        print '1' > ${_bref_zsh_prompt_path}/bref_battery_visible
    else
        print '0' > ${_bref_zsh_prompt_path}/bref_battery_visible
    fi
    _bref_make_prompt
    zle && zle reset-prompt
}

# create bref_battery_visible if it doesn't exist
_bref_zsh_prompt_path=${0:A:h}
if [[ ! -r ${_bref_zsh_prompt_path}/bref_battery_visible ]]; then
    print '0' > ${_bref_zsh_prompt_path}/bref_battery_visible
fi

zle -N _bref_toggle_battery
bindkey "${BREF_SHOW_BATTERY_BINDING}" _bref_toggle_battery

# the precmd hook is executed before displaying each prompt
autoload -U add-zsh-hook
add-zsh-hook -Uz precmd _bref_make_prompt
