#!/usr/bin/env bash
set -e

for braceStyle in allman otbs
do
	for source in *.d
	do
		echo "${source}.ref" "${braceStyle}/${source}.out"
		argsFile=$(basename ${source} .d).args
		if [ -e ${argsFile} ]; then
			args=$(cat ${argsFile})
		else
			args=
		fi
		../bin/dfmt-test --brace_style=${braceStyle} ${args} "${source}" > "${braceStyle}/${source}.out"
		diff -u "${braceStyle}/${source}.ref" "${braceStyle}/${source}.out"
	done
done
