## vim:ft=zsh
## svk support by: Frank Terbeck <ft@bewatermyfriend.org>
## Distributed under the same BSD-ish license as zsh itself.

setopt localoptions NO_shwordsplit
local svkbranch svkbase
local -A hook_com

svkbase=${vcs_comm[basedir]}
rrn=${svkbase:t}
zstyle -s ":vcs_info:${vcs}:${usercontext}:${rrn}" branchformat svkbranch || svkbranch="%b:%r"
hook_com=( branch "${vcs_comm[branch]}" revision "${vcs_comm[revision]}" )
if VCS_INFO_hook 'set-branch-format' "${svkbranch}"; then
    zformat -f svkbranch "${svkbranch}" "b:${hook_com[branch]}" "r:${hook_com[revision]}"
else
    svkbranch=${hook_com[branch-replace]}
fi
hook_com=()
VCS_INFO_formats '' "${svkbranch}" "${svkbase}" '' '' "${vcs_comm[revision]}" ''
return 0
