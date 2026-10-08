#!/usr/bin/env bash
# Records how Java unifica loads every synced grammar into
# test/corpus/java/grammars.json, for the Dart loader's parity test.
# Usage: tool/observe/observe.sh <unifica checkout>, built at the commit in
# test/corpus/SOURCE (mvn compile), with the ANTLR runtime in ~/.m2.
set -euo pipefail
cd "$(dirname "$0")/../.."
unifica="${1:?usage: tool/observe/observe.sh <unifica checkout>}"
antlr="$(find "$HOME/.m2/repository/org/antlr/antlr4-runtime" -name 'antlr4-runtime-4.13*.jar' ! -name '*sources*' | sort | tail -1)"
java -cp "$unifica/target/classes:$antlr" tool/observe/Observe.java test/corpus > test/corpus/java/grammars.json
echo "Wrote test/corpus/java/grammars.json"
