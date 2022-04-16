## PROMPT

autoload -U colors && colors # Enable colors in prompt

# TODO -- updating git status (and battery)
# create hook on tab completion widget on/off
# then make RPROMPT updating every 1-2 (or more: make tests) seconds to update git status
# then make this update disabled during completion (with to the hook) and reenable it
# after completion (updating prompt during completion breaks the completion menu)
# see: https://stackoverflow.com/questions/2187829/constantly-updated-clock-in-zsh-prompt

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

_bref_zsh_prompt_path=${0:A:h}
if [[ ! -r ${_bref_zsh_prompt_path}/bref_battery_visible ]]; then
    print '0' > ${_bref_zsh_prompt_path}/bref_battery_visible
fi

_bref_toggle_battery() {
    if [ $(<${_bref_zsh_prompt_path}/bref_battery_visible) -eq 0 ]; then
        print '1' > ${_bref_zsh_prompt_path}/bref_battery_visible
    else
        print '0' > ${_bref_zsh_prompt_path}/bref_battery_visible
    fi
    _bref_make_prompt
    zle && zle reset-prompt
}
zle -N _bref_toggle_battery
bindkey "${BREF_SHOW_BATTERY_BINDING}" _bref_toggle_battery

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

    local -a GIT_INFO
    GIT_INFO+=( "%F{15}(${GIT_LOCATION}" )
    [ -n "${GIT_STATUS}" ] && GIT_INFO+=( "${GIT_STATUS}" )
    [[ ${#DIVERGENCES[@]} -ne 0 ]] && GIT_INFO+=( "${(j::)DIVERGENCES}" )
    [[ ${#FLAGS[@]} -ne 0 ]] && GIT_INFO+=( "${(j::)FLAGS}" )
    print "${(j: :)GIT_INFO}%F{15})%f"
}

# Correct the prompt when PWD is big
_bref_format_path() {
    # $1 is the color, following arg(s) are the path
    local newline="%(?:%F{green}:%F{red})\n│${1} "
    (( width = ${COLUMNS} - 3 )) # -3 parce que le append de la barre + l'espace + margin
    local login_hostname=$(print -P "  %n@%M:  ")
    (( width1st = ${COLUMNS} - ${#login_hostname} ))
    local rest=${@[@]:2} # le reste a traiter

    if [[ ${#rest} -le ${width1st} ]]; then
        result=${1}${rest}
    else
        if [[ ${width1st} -le 0 ]]; then # when terminal too small don't show PWD
            return 0
        fi
        # Premiere ligne est speciale
        local temp=${rest:0:${width1st}} # get the beginning of the line
        rest=${rest:${width1st}} # get the remaining

        local result=${1}${temp}
        while [[ ${#rest} -gt ${width} ]]; do
            temp=${rest:0:${width}}
            rest=${rest:${width}}
            result=${result}${newline}${1}${temp}
        done
        result=${result}${newline}${1}${rest}
    fi

    print ${result}
}

local _rprompt_async_proc=0
_bref_make_prompt() {
    ### PROMPT ###

    local path_color="%F{blue}"
    local link_target=$(readlink -f ${PWD})
    if [[ ${link_target} != ${PWD} ]]; then
        link_target="${rsv/$HOME/~}"
        path_color="%F{cyan}"
    fi

    local current_path=$(_bref_format_path ${path_color} $(print -P %~))
    
    PROMPT="%B%(?:%F{green}:%F{red})┌ %F{green}%n@%M${ssh_status}: ${current_path}
%(?:%F{green}:%F{red})└ %(?:%F{green}%(#:#:$):%F{red}%(#:#:$))%f%b "

    ### RPROMPT ###

    # put the battery status in rprompt if it's present and enabled or in virtual console
    if [[ -r /sys/class/power_supply/BAT0/capacity && ( $(<${_bref_zsh_prompt_path}/bref_battery_visible) -eq 1 || ${TERM} = "linux" ) ]]; then
        local bat_capa=$(</sys/class/power_supply/BAT0/capacity)
        (( $(</sys/class/power_supply/AC/online) )) && local bat_charge=+ || local bat_charge=
        RPROMPT=" %F{yellow}[${bat_capa}${bat_charge}]%f"
    else
        RPROMPT=''
    fi
    # put the return value in rprompt if it is > 0
    RPROMPT='%(?:: %F{red}[%?]%f)'${RPROMPT}
    # put a ssh notification in rprompt if we are in a ssh session
    [[ -n ${SSH_CONNECTION-}${SSH_CLIENT-}${SSH_TTY-} ]] && RPROMPT=' %F{magenta}(ssh)%f'${RPROMPT}
    # put the number of running background jobs in rprompt if there are any
    RPROMPT='%(1j: %F{yellow}%jj%f:)'${RPROMPT}

    async() {
        # save to temp file
        printf "%s" "$(_bref_git_info)" > "/tmp/zsh_bref_$$"

        # signal parent
        kill -s USR1 $$
    }

    # do not clear RPROMPT, let it persist

    # kill child if necessary
    if [[ "${_rprompt_async_proc}" != 0 ]]; then
        kill -s HUP ${_rprompt_async_proc} >/dev/null 2>&1 || :
    fi

    # start background computation
    async &!
    _rprompt_async_proc=$!
}

TRAPUSR1() {
    # read from temp file
    RPROMPT="$(</tmp/zsh_bref_$$)${RPROMPT}"

    # reset proc number
    rm /tmp/zsh_bref_$$
    _rprompt_async_proc=0

    # redisplay
    zle && zle reset-prompt
}

PROMPT="%B%F{green}>%f%b "
SPROMPT="Correct %F{red}'%R'%f to %F{green}'%r'%f [Yes, No, Abort, Edit]? "

autoload -Uz add-zsh-hook
# the precmd hook is executed before displaying each prompt
add-zsh-hook -Uz precmd _bref_make_prompt
