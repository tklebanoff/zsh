if (( ! $# )); then
  p4 help commands
else
  p4 help $1
fi | ${=PAGER:-less}
