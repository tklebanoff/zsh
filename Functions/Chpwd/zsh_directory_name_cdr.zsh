if [[ $1 = n ]]; then
  if [[ $2 = <-> ]]; then
    # Recent directory
    autoload -Uz cdr
    cdr -r
    if [[ -n ${reply[$2]} ]]; then
      typeset -ga reply=(${reply[$2]})
      return 0
    else
      typeset -ga reply=()
      return 1
    fi
  fi
elif [[ $1 = c ]]; then
  if [[ $PREFIX = <-> || -z $PREFIX ]]; then
    typeset -a keys values
    values=(${${(f)"$(cdr -l)"}/ ##/:})
    keys=(${values%%:*})
    _describe -t dir-index 'recent directory index' \
      values -V unsorted -S']'
    return
  fi
fi
return 1
