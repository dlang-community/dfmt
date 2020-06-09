#!/bin/bash

set -e

if [[ $BUILD == dub ]]; then
    rdmd ./d-test-utils/test_with_package.d $LIBDPARSE_VERSION libdparse -- dub build --build=release
elif [[ $DC == ldc2 ]]; then
    git submodule update --init --recursive
    make ldc -j2
else
    git submodule update --init --recursive
    make debug -j2
fi

cd tests && ./test.sh
