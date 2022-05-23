#!/usr/bin/env bash

argsFile=$1.args
if [ -e ${argsFile} ]; then
	args=$(cat ${argsFile})
fi
echo "Args:" ${args}
../bin/dfmt --brace_style=allman ${args} $1.d > allman/$1.d.ref
../bin/dfmt --brace_style=otbs ${args} $1.d > otbs/$1.d.ref

echo "------------------"
echo "allman:"
echo "------------------"
cat allman/$1.d.ref
echo "------------------"
echo "otbs:"
echo "------------------"
cat otbs/$1.d.ref
