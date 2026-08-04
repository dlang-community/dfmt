#!/usr/bin/env bash

argsFile=$1.args
if [ -e ${argsFile} ]; then
	args=$(cat ${argsFile})
fi
echo "Args:" ${args}
../bin/dfmt --brace_style=allman ${args} $1.d > allman/$1.d.ref
../bin/dfmt --brace_style=otbs ${args} $1.d > otbs/$1.d.ref
../bin/dfmt --brace_style=knr ${args} $1.d > knr/$1.d.ref
../bin/dfmt --brace_style=linux ${args} $1.d > linux/$1.d.ref

echo "------------------"
echo "allman:"
echo "------------------"
cat allman/$1.d.ref
echo "------------------"
echo "otbs:"
echo "------------------"
cat otbs/$1.d.ref
echo "------------------"
echo "knr:"
echo "------------------"
cat knr/$1.d.ref
echo "------------------"
echo "linux:"
echo "------------------"
cat linux/$1.d.ref
