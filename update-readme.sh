#!/bin/bash

here=$(pwd)

{
	cat README.md.in

	for patch in new/*; do
		subj=$(formail -c -x subject < "$patch")
		subj=${subj/ Re: /}
		subj=${subj//_/\\_}
		subj=${subj//>/\\>}
		url=$(grep '^Sashiko AI review.*http' < "$patch")
		url=https${url#*https}
		echo "* [$subj]($patch) [(*web*)]($url)"
	done

} > README.md
