# get a random line from a file
integer z="$(wc -l <$1)"
sed -n $[RANDOM%z+1]p $1
