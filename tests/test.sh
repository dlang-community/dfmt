#!/usr/bin/env bash
set -e

for source in *.d
do
	echo "${source}.ref" "${source}.out"
	../bin/dfmt "${source}" >"${source}.out"
	diff -u "${source}.ref" "${source}.out"
done
