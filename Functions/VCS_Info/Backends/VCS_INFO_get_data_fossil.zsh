## vim:ft=zsh
## fossil support by: Mike Meyer (mwm@mired.org)
## Distributed under the same BSD-ish license as zsh itself.

setopt localoptions extendedglob
local a b
local -A fsinfo
local fshash fsbranch changed merging action

${vcs_comm[cmd]} status |
   while IFS=: read a b; do
      fsinfo[${a//-/_}]="${b## #}"
   done

fshash=${fsinfo[checkout]%% *}
fsbranch=${fsinfo[tags]%%, *}
changed=${(Mk)fsinfo:#(ADDED|EDITED|DELETED|UPDATED)*}
merging=${(Mk)fsinfo:#*_BY_MERGE*}
if [ -n "$merging" ]; then
   action="merging"
fi

VCS_INFO_formats "$action" "${fsbranch}" "${fsinfo[local_root]}" '' "$changed" "${fshash}" "${fsinfo[repository]}"
return 0
