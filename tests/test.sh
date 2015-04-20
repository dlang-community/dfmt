#!/usr/bin/env bash
set -e

for braceStyle in allman otbs
do
	for source in *.d
	do
		echo "${source}.ref" "${braceStyle}/${source}.out"
		../bin/dfmt --brace_style=${braceStyle} "${source}" > "${braceStyle}/${source}.out"
		diff -u "${braceStyle}/${source}.ref" "${braceStyle}/${source}.out"
	done
done
