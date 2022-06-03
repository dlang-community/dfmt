#!/usr/bin/env bash
set -e

for braceStyle in allman otbs knr
do
	for source in *.d
	do
		test "$(basename $source '.d')" = 'test' && continue

		echo "${source}.ref" "${braceStyle}/${source}.out"
		argsFile=$(basename "${source}" .d).args
		if [ -e "${argsFile}" ]; then
			args=$(cat "${argsFile}")
		else
			args=
		fi
		../bin/dfmt --brace_style=${braceStyle} ${args} "${source}" > "${braceStyle}/${source}.out"
		diff -u "${braceStyle}/${source}.ref" "${braceStyle}/${source}.out"
	done
done

set +e

for source in expected_failures/*.d
do
	if ../bin/dfmt "${source}" > /dev/null; then
		echo "Expected failure on test ${source} but passed"
		exit 1
	fi
done

echo "This script is superseded by test.d."
