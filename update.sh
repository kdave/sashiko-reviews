#!/bin/sh

src="${1:-$HOME/sashiko-sync}"
here=$(pwd)
newdir="$here/new"
donedir="$here/done"

if ! [ -f "$src" ]; then
	echo "ERROR: cannot find mail sources sashiko-sync"
	exit
fi

type -p formail >& /dev/null || echo "ERROR: cannot find formail"

mkdir -p new wip 'done'

cd wip
rm -f wip.*

cat "$src" | formail -k -X From -X Subject -X Date -X Message-Id -ds sh -c 'cat > wip.$FILENO'

for mbox in wip.*; do
	mid=$(formail -c -x message-id < "$mbox" | sed -e 's/^[^<]*<//' | sed -e 's/>.*$//')
	if [ -f "$newdir/$mid" -o -f "$donedir/$Wmid" ]; then
		echo "SKIP: $mbox $mid"
		continue
	fi
	echo "NEW: $mbox $mid"
	"$here/qpdecode.py" "$mbox" "$newdir/$mid"
done

cd "$here"
grep -L '^From sashiko-bot@kernel.org' new/* | xargs rm -- -v
git add new/*
git commit -m"Update "$(date  +%Y-%m-%d)
