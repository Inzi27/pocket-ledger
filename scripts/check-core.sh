#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/core-check .build/ModuleCache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
swiftc -swift-version 5 -parse-as-library -emit-module -emit-library -module-name BudgetCore \
    Sources/BudgetCore/*.swift -module-cache-path .build/ModuleCache \
    -emit-module-path .build/core-check/BudgetCore.swiftmodule -o .build/core-check/libBudgetCore.dylib
swiftc -swift-version 5 -parse-as-library scripts/CoreChecks.swift -I .build/core-check \
    -L .build/core-check -lBudgetCore -module-cache-path .build/ModuleCache \
    -Xlinker -rpath -Xlinker "$PWD/.build/core-check" -o .build/core-check/CoreChecks
.build/core-check/CoreChecks
