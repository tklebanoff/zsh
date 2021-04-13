## vim:ft=zsh
## git support by: Frank Terbeck <ft@bewatermyfriend.org>
## Distributed under the same BSD-ish license as zsh itself.

setopt localoptions extendedglob NO_shwordsplit
local gitdir gitbase gitbranch gitaction gitunstaged gitstaged gitsha1 gitmisc
local -i querystaged queryunstaged
local -a git_patches_applied git_patches_unapplied
local -A hook_com

(( ${+functions[VCS_INFO_git_getaction]} )) ||
VCS_INFO_git_getaction () {
    local gitdir=$1
    local tmp

    for tmp in "${gitdir}/rebase-apply" \
               "${gitdir}/rebase"       \
               "${gitdir}/../.dotest" ; do
        if [[ -d ${tmp} ]] ; then
            if   [[ -f "${tmp}/rebasing" ]] ; then
                gitaction="rebase"
            elif [[ -f "${tmp}/applying" ]] ; then
                gitaction="am"
            else
                gitaction="am/rebase"
            fi
            return 0
        fi
    done

    for tmp in "${gitdir}/rebase-merge/interactive" \
               "${gitdir}/.dotest-merge/interactive" ; do
        if [[ -f "${tmp}" ]] ; then
            gitaction="rebase-i"
            return 0
        fi
    done

    for tmp in "${gitdir}/rebase-merge" \
               "${gitdir}/.dotest-merge" ; do
        if [[ -d "${tmp}" ]] ; then
            gitaction="rebase-m"
            return 0
        fi
    done

    if [[ -f "${gitdir}/MERGE_HEAD" ]] ; then
        gitaction="merge"
        return 0
    fi

    if [[ -f "${gitdir}/BISECT_LOG" ]] ; then
        gitaction="bisect"
        return 0
    fi

    if [[ -f "${gitdir}/CHERRY_PICK_HEAD" ]] ; then
        if [[ -d "${gitdir}/sequencer" ]] ; then
            gitaction=cherry-seq
        else
            gitaction=cherry
        fi
        return 0
    fi

    if [[ -d "${gitdir}/sequencer" ]] ; then
         gitaction="cherry-or-revert"
         return 0
    fi

    return 1
}

(( ${+functions[VCS_INFO_git_getbranch]} )) ||
VCS_INFO_git_getbranch () {
    local gitdir=$1 tmp actiondir
    local gitsymref="${vcs_comm[cmd]} symbolic-ref HEAD"

    actiondir=''
    for tmp in "${gitdir}/rebase-apply" \
               "${gitdir}/rebase"       \
               "${gitdir}/../.dotest"; do
        if [[ -d ${tmp} ]]; then
            actiondir=${tmp}
            break
        fi
    done
    if [[ -n ${actiondir} ]]; then
        gitbranch="$(${(z)gitsymref} 2> /dev/null)"
        [[ -z ${gitbranch} ]] && [[ -r ${actiondir}/head-name ]] \
            && gitbranch="$(< ${actiondir}/head-name)"
        [[ -z ${gitbranch} || ${gitbranch} == 'detached HEAD' ]] && [[ -r ${actiondir}/onto ]] \
            && gitbranch="$(< ${actiondir}/onto)"

    elif [[ -f "${gitdir}/MERGE_HEAD" ]] ; then
        gitbranch="$(${(z)gitsymref} 2> /dev/null)"
        [[ -z ${gitbranch} ]] && gitbranch="$(< ${gitdir}/ORIG_HEAD)"

    elif [[ -d "${gitdir}/rebase-merge" ]] ; then
        gitbranch="$(< ${gitdir}/rebase-merge/head-name)"
        if [[ $gitbranch == 'detached HEAD' ]]; then
            # get a sha1
            gitbranch="$(< ${gitdir}/rebase-merge/orig-head)"
        fi

    elif [[ -d "${gitdir}/.dotest-merge" ]] ; then
        gitbranch="$(< ${gitdir}/.dotest-merge/head-name)"

    elif gitbranch="$(${(z)gitsymref} 2> /dev/null)" ; then
    elif gitbranch="refs/tags/$(${vcs_comm[cmd]} describe --all --exact-match HEAD 2>/dev/null)" ; then
    elif gitbranch="$(${vcs_comm[cmd]} describe --contains HEAD 2>/dev/null)" ; then
    ## Commented out because we don't know of a case in which 'describe --contains' fails and 'name-rev --tags' succeeds.
    #elif gitbranch="$(${vcs_comm[cmd]} name-rev --name-only --no-undefined --tags HEAD 2>/dev/null)" ; then
    elif gitbranch="$(${vcs_comm[cmd]} name-rev --name-only --no-undefined --always HEAD 2>/dev/null)" ; then
    fi

    if [[ -z ${gitbranch} ]]
    then
	gitbranch="${${"$(< $gitdir/HEAD)"}[1,7]}..."
    fi

    return 0
}

(( ${+functions[VCS_INFO_git_handle_patches]} )) ||
VCS_INFO_git_handle_patches () {
    local git_applied_s git_unapplied_s gitmsg
    # All callers populate $git_patches_applied and $git_patches_unapplied in
    # order, but the hook requires us to reverse $git_patches_applied.
    git_patches_applied=(${(Oa)git_patches_applied})

    VCS_INFO_set-patch-format 'git_patches_applied' 'git_applied_s' \
                              'git_patches_unapplied' 'git_unapplied_s' \
                              ":vcs_info:${vcs}:${usercontext}:${rrn}" gitmsg \
                              '' ''
    gitmisc=$REPLY
}

gitdir=${vcs_comm[gitdir]}
VCS_INFO_git_getbranch ${gitdir}
gitbase=$( ${vcs_comm[cmd]} rev-parse --show-toplevel )
rrn=${gitbase:t}
if zstyle -t ":vcs_info:${vcs}:${usercontext}:${rrn}" get-revision ; then
    gitsha1=$(${vcs_comm[cmd]} rev-parse --quiet --verify HEAD)
else
    gitsha1=''
fi
gitbranch="${gitbranch##refs/[^/]##/}"

if [[ -z ${gitdir} ]] || [[ -z ${gitbranch} ]] ; then
    return 1
fi

if zstyle -t ":vcs_info:${vcs}:${usercontext}:${rrn}" "check-for-changes" ; then
    querystaged=1
    queryunstaged=1
elif zstyle -t ":vcs_info:${vcs}:${usercontext}:${rrn}" "check-for-staged-changes" ; then
    querystaged=1
fi
if (( querystaged || queryunstaged )) && \
   [[ "$(${vcs_comm[cmd]} rev-parse --is-inside-work-tree 2> /dev/null)" == 'true' ]] ; then
    # Default: off - these are potentially expensive on big repositories
    if (( queryunstaged )) ; then
        ${vcs_comm[cmd]} diff --no-ext-diff --ignore-submodules=dirty --quiet --exit-code 2> /dev/null ||
            gitunstaged=1
    fi
    if (( querystaged )) ; then
        if ${vcs_comm[cmd]} rev-parse --quiet --verify HEAD &> /dev/null ; then
            ${vcs_comm[cmd]} diff-index --cached --quiet --ignore-submodules=dirty HEAD 2> /dev/null
            (( $? && $? != 128 )) && gitstaged=1
        else
            # empty repository (no commits yet)
            # 4b825dc642cb6eb9a060e54bf8d69288fbee4904 is the git empty tree.
            ${vcs_comm[cmd]} diff-index --cached --quiet --ignore-submodules=dirty 4b825dc642cb6eb9a060e54bf8d69288fbee4904 2>/dev/null
            (( $? && $? != 128 )) && gitstaged=1
        fi
    fi
fi

VCS_INFO_adjust
VCS_INFO_git_getaction ${gitdir}

local patchdir=${gitdir}/patches/${gitbranch}
if [[ -d $patchdir ]] && [[ -f $patchdir/applied ]] \
   && [[ -f $patchdir/unapplied ]]
then
    # stgit
    git_patches_applied=(${(f)"$(< "${patchdir}/applied")"})
    git_patches_unapplied=(${(f)"$(< "${patchdir}/unapplied")"})
    VCS_INFO_git_handle_patches
elif [[ -d "${gitdir}/rebase-merge" ]]; then
    # 'git rebase -i'
    patchdir="${gitdir}/rebase-merge"
    local p
    [[ -f "${patchdir}/done" ]] &&
    for p in ${(f)"$(< "${patchdir}/done")"}; do
        # pick/edit/fixup/squash/reword: Add "$hash $subject" to $git_patches_applied.
        # exec: Add "exec ${command}" to $git_patches_applied.
        # (anything else): As 'exec'.
        case $p in
            ((p|pick|e|edit|r|reword|f|fixup|s|squash)' '*)
                # The line is of the form "pick $hash $subject".
                # Just strip the verb and we're good to go.
                p=${p#* }
                # Special case: in an interactive rebase, if the user wrote "p $shorthash\n"
                # in the editor (without a description after the hash), then the .../done
                # file will contain "p $longhash $shorthash\n" (git 2.11.0) or "pick $longhash\n"
                # (git 2.19.0).
                if [[ $p != *\ * ]]; then
                        # The line is of the form "pick $longhash\n"
                        #
                        # Mark the log message subject as unknown.
                        # TODO: Can we performantly obtain the subject?
                        p+=" ?"
                elif (( ${#${p//[^ ]}} == 1 )) && [[ ${p%% *} == ${p#* }* ]]; then
                        # The line is of the form "p $longhash $shorthash\n"
                        #
                        # The shorthash is superfluous, so discard it, and mark
                        # the log message subject as unknown.
                        # TODO: Can we performantly obtain the subject?
                        p="${p%% *} ?"
                fi
                ;;
            (x *)
                # The line is of the form 'exec foo bar baz' where 'foo bar
                # baz' is a shell command.  There's no way to map _that_ to
                # "$hash $subject", but I hope this counts as making an effort.
                p=${p/x /exec }
                ;;
            (*)
                # Forward compatibility with not-yet-existing 'git rebase -i' verbs.
                if [[ $p != *\ * ]]; then
                    p+=" ?"
                fi
        esac
        git_patches_applied+=("$p")
    done
    if [[ -f "${patchdir}/git-rebase-todo" ]] ; then
        # TODO: Process ${patchdir}/git-rebase-todo lines like ${patchdir}/done lines are
        git_patches_unapplied=( ${${(f)${"$(<"${patchdir}/git-rebase-todo")"}}:#[#]*} )
    fi
    VCS_INFO_git_handle_patches
elif [[ -d "${gitdir}/rebase-apply" ]]; then
    # 'git rebase' without -i
    patchdir="${gitdir}/rebase-apply"
    local next="${patchdir}/next"
    if [[ -f $next ]]; then
        local cur=$(< $next)
        local p subject
        # Fake patch names for all but current patch
        for ((p = 1; p < cur; p++)); do
            printf -v "git_patches_applied[$p]"  "%04d ?" "$p"
        done
        if [[ -f "${patchdir}/msg-clean" ]]; then
            subject="${$(< "${patchdir}/msg-clean")[(f)1]}"
        elif local this_patch_file
             printf -v this_patch_file "%s/%04d" "${patchdir}" "${cur}"
             [[ -f $this_patch_file ]]
        then
            () {
              local REPLY
              VCS_INFO_patch2subject "${this_patch_file}"
              subject=$REPLY
            }
        fi
        subject=${subject:-'?'}
        if [[ -f "${patchdir}/original-commit" ]]; then
            git_patches_applied+=("$(< ${patchdir}/original-commit) $subject")
        else
            git_patches_applied+=("? $subject")
        fi
        local last="$(< "${patchdir}/last")"
        if (( cur+1 <= last )); then
          git_patches_unapplied=( {$((cur+1))..$last} )
        fi
    fi

    VCS_INFO_git_handle_patches
elif [[ -f "${gitdir}/MERGE_HEAD" ]]; then
    # This is 'git merge --no-commit'
    local -a heads=( ${(@f)"$(<"${gitdir}/MERGE_HEAD")"} )
    local subject;
    # TODO: maybe read up to the first blank line
    IFS='' read -r subject < "${gitdir}/MERGE_MSG"
    # $subject is the subject line of the would-be commit
    # Maybe we can get the subject lines of MERGE_HEAD's commits cheaply?

    local p
    for p in $heads[@]; do
      git_patches_applied+=("$p $subject")
    done
    unset p

    # Not touching git_patches_unapplied

    VCS_INFO_git_handle_patches
elif [[ -f "${gitdir}/CHERRY_PICK_HEAD" ]]; then
    # 'git cherry-pick' without -n, that conflicted.  (With -n, git doesn't
    # record the CHERRY_PICK_HEAD information anywhere, as of git 2.6.2.)
    #
    # ### 'git cherry-pick foo bar baz' only records the "remaining" part of
    # ### the queue in the .git dir: if 'bar' has a conflict, the .git dir 
    # ### has a record of 'baz' being queued, but no record of 'foo' having been
    # ### part of the queue as well.  Therefore, the %n/%c applied/unapplied
    # ### expandos will be memoryless: the "applied" counter will always
    # ### be "1".  The %u/%c tuple will assume the values [(1,2), (1,1), (1,0)],
    # ### whereas the correct sequence would be [(1,2), (2,1), (3,0)].
    local subject
    # TODO: maybe read up to the first blank line
    IFS='' read -r subject < "${gitdir}/MERGE_MSG"
    git_patches_applied=( "$(<${gitdir}/CHERRY_PICK_HEAD) ${subject}" )
    if [[ -f "${gitdir}/sequencer/todo" ]]; then
        # Get the next patches, and remove the one that's in CHERRY_PICK_HEAD.
        git_patches_unapplied=( ${${(M)${(f)"$(<"${gitdir}/sequencer/todo")"}:#pick *}#pick } )
        git_patches_unapplied[1]=()
    else
        git_patches_unapplied=()
    fi
    VCS_INFO_git_handle_patches
else
    gitmisc=''
fi

backend_misc[patches]="${gitmisc}"
VCS_INFO_formats "${gitaction}" "${gitbranch}" "${gitbase}" "${gitstaged}" "${gitunstaged}" "${gitsha1}" "${gitmisc}"
return 0
