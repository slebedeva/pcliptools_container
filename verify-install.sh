#!/usr/bin/env bash
# Quick sanity check of the pcliptools container's toolchain.
# Run inside the container: pcliptools-verify-install
set -uo pipefail
FAIL=0

check() {
    local name="$1"; shift
    if OUT="$("$@" 2>&1)"; then
        echo "OK    $name"
    else
        echo "FAIL  $name"
        echo "$OUT" | sed 's/^/        /'
        FAIL=1
    fi
}

echo "== core tools =="
check "samtools"                samtools --version
check "bedtools"                bedtools --version
check "gawk (as awk)"            awk --version
check "awk patsplit() works"     bash -c 'echo ATCG | awk "{ n=patsplit(\$1,a,/[ATCG]/) } END{ exit (n==4)?0:1 }"'
check "R"                       R --version
check "R dplyr"                 Rscript -e 'suppressMessages(library(dplyr)); cat("dplyr", as.character(packageVersion("dplyr")), "\n")'
check "python"                  python --version
check "python numpy"            python -c "import numpy; print(numpy.__version__)"
check "python pandas"           python -c "import pandas; print(pandas.__version__)"
check "python pybedtools"       python -c "import pybedtools; print(pybedtools.__version__)"
check "python matplotlib-venn"  python -c "import matplotlib_venn"
check "bedGraphToBigWig"        bash -c '
    command -v bedGraphToBigWig >/dev/null || { echo "not on PATH"; exit 1; }
    OUT="$(bedGraphToBigWig 2>&1)"
    if echo "$OUT" | grep -qiE "cannot open shared object|error while loading|not found"; then
        echo "$OUT"; exit 1
    fi
'
check "STAR"                    STAR --version
check "cutadapt"                cutadapt --version

echo "== pcliptools scripts on PATH =="
for tool in pcliptools-align pcliptools-annotate pcliptools-cluster \
            pcliptools-compare-bed pcliptools-compute-bigwig \
            pcliptools-compute-substitution; do
    check "$tool" bash -c "command -v $tool"
done

if [ "$FAIL" -eq 0 ]; then
    echo
    echo "All checks passed."
else
    echo
    echo "One or more checks FAILED - see above." >&2
fi
exit $FAIL
