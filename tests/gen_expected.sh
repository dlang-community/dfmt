dfmt --braces=allman $1.d > allman/$1.d.ref
dfmt --braces=otbs $1.d > otbs/$1.d.ref

echo "------------------"
echo "allman:"
echo "------------------"
cat allman/$1.d.ref
echo "------------------"
echo "otbs:"
echo "------------------"
cat otbs/$1.d.ref
