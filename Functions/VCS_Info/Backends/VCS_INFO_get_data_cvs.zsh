## vim:ft=zsh
## cvs support by: Frank Terbeck <ft@bewatermyfriend.org>
## Distributed under the same BSD-ish license as zsh itself.

setopt localoptions NO_shwordsplit
local cvsbranch cvsbase

cvsbase="."
while [[ -d "${cvsbase}/../CVS" ]]; do
    cvsbase="${cvsbase}/.."
done
cvsbase=${cvsbase:P}
cvsbranch=$(< ./CVS/Repository)
rrn=${cvsbase:t}
cvsbranch=${cvsbranch##${rrn}/}
[[ -z ${cvsbranch} ]] && cvsbranch=${rrn}
VCS_INFO_formats '' "${cvsbranch}" "${cvsbase}" '' '' '' ''
return 0
