# syntax=docker/dockerfile:1
#
# Downstream (post-alignment) toolchain for pcliptools
# https://github.com/paulahsan/pcliptools  (CC0-1.0)
#
# Includes STAR + cutadapt (so pcliptools-align works too) alongside all of
# the peak-calling / annotation / QC / plotting tools. See README.md for the
# reasoning behind each non-obvious choice below.

FROM ubuntu:24.04

LABEL org.opencontainers.image.title="pcliptools" \
      org.opencontainers.image.description="paulahsan/pcliptools PAR-CLIP toolchain: alignment (STAR/cutadapt), peak calling, annotation, T>C substitution QC, bigwig export, bed comparison" \
      org.opencontainers.image.source="https://github.com/paulahsan/pcliptools" \
      org.opencontainers.image.licenses="CC0-1.0"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    MPLBACKEND=Agg

# ---------------------------------------------------------------------------
# System packages
#
# --no-install-recommends matters: r-cran-dplyr's Recommends: chain pulls in
# an unrelated set of geospatial R packages (sf, gstat, spdep, terra...) if
# left on defaults - verified this pulls 15+ extra packages with plain
# `apt-get install r-cran-dplyr`.
#
# gawk is required, not a style choice: pcliptools-functions and
# pcliptools-compute-substitution use gawk-only extensions (patsplit(), the
# 3-argument form of match()). Ubuntu's default `awk` is mawk, which doesn't
# support either - confirmed this breaks silently rather than erroring
# clearly. update-alternatives repoints the plain `awk` the scripts call at
# gawk.
#
# rna-star (2.7.11b) and cutadapt (4.4) are apt packages, not source builds:
# 2.7.11b is one of the two STAR versions the pcliptools README says it was
# tested against, and Ubuntu's rna-star package ships a CPU-dispatch wrapper
# (avx2/avx/sse variants + fallback) that's more portable across hardware
# than a single from-source build would be.
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        gawk \
        samtools \
        bedtools \
        r-base-core \
        r-cran-dplyr \
        python3 \
        python-is-python3 \
        python3-numpy \
        python3-pandas \
        python3-matplotlib \
        python3-matplotlib-venn \
        python3-pybedtools \
        rna-star \
        cutadapt \
        libssl3t64 \
        libuuid1 \
        zlib1g \
        libpng16-16t64 \
        libmariadb3 \
    && update-alternatives --set awk /usr/bin/gawk \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# pcliptools itself, pinned to a specific commit for reproducibility.
# Bump PCLIPTOOLS_COMMIT (--build-arg PCLIPTOOLS_COMMIT=<sha>) to update.
# ---------------------------------------------------------------------------
ARG PCLIPTOOLS_COMMIT=c0dd53ab38be35f15d4c43f369cfceedcde32fc8
RUN git clone https://github.com/paulahsan/pcliptools.git /opt/pcliptools \
    && cd /opt/pcliptools \
    && git checkout ${PCLIPTOOLS_COMMIT} \
    && chmod +x bin/*

# ---------------------------------------------------------------------------
# bedGraphToBigWig
#
# pcliptools vendors a prebuilt copy of this Kent-utils binary in bin/, but
# that copy is dynamically linked against libpng12, which Ubuntu/Debian
# dropped from their repositories in 2016 - no current base image can
# apt-install it. Confirmed the vendored copy fails with:
#   "error while loading shared libraries: libpng12.so.0: cannot open
#    shared object file: No such file or directory"
#
# Fix: replace it with UCSC's actively-rebuilt "current" binary, then verify
# in place that it resolves cleanly against the libpng16 already on this
# image. The build fails loudly here if it doesn't, rather than shipping a
# broken binary silently.
#
# Reproducibility note: this URL always serves UCSC's latest rebuild, not a
# pinned version - the exact binary may change between builds. For a fully
# pinned build, point at one of UCSC's dated snapshot directories instead,
# e.g. https://hgdownload.gi.ucsc.edu/admin/exe/linux.x86_64.vNNN/
# ---------------------------------------------------------------------------
RUN cd /opt/pcliptools/bin \
    && rm -f bedGraphToBigWig \
    && curl -fsSL -o bedGraphToBigWig \
        https://hgdownload.gi.ucsc.edu/admin/exe/linux.x86_64/bedGraphToBigWig \
    && chmod +x bedGraphToBigWig \
    && echo "== ldd check ==" && ldd bedGraphToBigWig \
    && if ldd bedGraphToBigWig | grep -q "not found"; then \
           echo "FATAL: bedGraphToBigWig has unresolved shared libraries (see above)." >&2; \
           exit 1; \
       fi \
    && echo "== execution check ==" \
    && OUT="$(./bedGraphToBigWig 2>&1)"; echo "$OUT"; \
       if echo "$OUT" | grep -qiE "cannot open shared object|error while loading"; then \
           echo "FATAL: bedGraphToBigWig still fails to run (see above)." >&2; \
           exit 1; \
       fi

ENV PATH="/opt/pcliptools/bin:${PATH}"

# ---------------------------------------------------------------------------
# Build-time self-test. Fails the build (rather than shipping silently
# broken tools) if anything above didn't come together correctly. Re-runnable
# any time inside a running container as `pcliptools-verify-install`.
# ---------------------------------------------------------------------------
COPY verify-install.sh /usr/local/bin/pcliptools-verify-install
RUN chmod +x /usr/local/bin/pcliptools-verify-install \
    && pcliptools-verify-install

WORKDIR /data

CMD ["/bin/bash"]
