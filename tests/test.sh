#!/usr/bin/env bash
set -e

# main test suite
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
		../bin/dfmt --brace_style=${braceStyle} ${args} "${source}" > "${braceStyle}/${source}.out"
		diff -u "${braceStyle}/${source}.ref" "${braceStyle}/${source}.out"
	done
done

# individual tests
cd individual
for source in *.d
do
	echo "testing indiviual ${source}"
	test_name="${source}_test"
	$DC ${source} -of${test_name}
	if [ -f ${test_name} ]; then
		./${test_name}
		rm -f "${test_name}"
		echo "tested indiviual ${source}"
	fi
done
