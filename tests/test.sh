#!/usr/bin/env bash
set -e

for source in *.d
do
	../bin/dfmt "${source}" >"${source}.out"
	diff -u "${source}.ref" "${source}.out"
done
