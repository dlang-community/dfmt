argsFile=$1.args
if [ -e ${argsFile} ]; then
	args=$(cat ${argsFile})
fi
echo "Args:" ${args}
dfmt --brace_style=allman ${args} $1.d > allman/$1.d.ref
dfmt --brace_style=otbs ${args} $1.d > otbs/$1.d.ref

echo "------------------"
echo "allman:"
echo "------------------"
cat allman/$1.d.ref
echo "------------------"
echo "otbs:"
echo "------------------"
cat otbs/$1.d.ref
