## vim:ft=zsh
## git support by: Frank Terbeck <ft@bewatermyfriend.org>
## Distributed under the same BSD-ish license as zsh itself.

setopt localoptions NO_shwordsplit

[[ $1 == '--flavours' ]] && { print -l git-p4 git-svn; return 0 }

if VCS_INFO_check_com ${vcs_comm[cmd]} && ${vcs_comm[cmd]} rev-parse --is-inside-work-tree &> /dev/null ; then
    vcs_comm[gitdir]="$(${vcs_comm[cmd]} rev-parse --git-dir 2> /dev/null)" || return 1
    if   [[ -d ${vcs_comm[gitdir]}/svn ]]             ; then vcs_comm[overwrite_name]='git-svn'
    elif [[ -d ${vcs_comm[gitdir]}/refs/remotes/p4 ]] ; then vcs_comm[overwrite_name]='git-p4' ; fi
    return 0
fi
return 1
