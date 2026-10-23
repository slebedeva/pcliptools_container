# pcliptools container

Packages [paulahsan/pcliptools](https://github.com/paulahsan/pcliptools) (CC0-1.0), a
PAR-CLIP peak caller and analysis pipeline, plus STAR and cutadapt so `pcliptools-align`
works too.

Author: Claude

## Build

```bash
docker build -t pcliptools .
```

The build runs a self-test (`pcliptools-verify-install`) as its last step and will
**fail loudly** if any tool didn't come together correctly, rather than shipping a
silently broken image.

## Use

```bash
docker run --rm -it -v "$PWD":/data pcliptools bash
# inside the container:
pcliptools-cluster -b aligned.bam -n sample1 -g genes.gtf -f genome.fa
pcliptools-verify-install   # re-run the sanity checks any time
```

## What's inside and why

| Tool | Source | Notes |
|---|---|---|
| `pcliptools-*` scripts | git, pinned commit | see `PCLIPTOOLS_COMMIT` build arg |
| samtools, bedtools | apt (Ubuntu 24.04) | 1.19.2 / 2.31.1 |
| R + dplyr | apt | 4.3.3 / 1.1.4 (dplyr version matches the repo's tested version exactly) |
| python3 + numpy/pandas/pybedtools/matplotlib/matplotlib-venn | apt | avoids pip, see caveat below |
| gawk | apt, set as system `awk` | **required**, not cosmetic - see below |
| STAR | apt (`rna-star` 2.7.11b) | matches one of the two versions in the repo's README |
| cutadapt | apt (4.4) | close to the tested 4.5/4.9 |
| bedGraphToBigWig | fetched fresh from UCSC at build time | replaces the repo's vendored copy, see below |

### Why gawk, specifically

`pcliptools-functions` and `pcliptools-compute-substitution` use gawk-only
extensions: `patsplit()` and the 3-argument form of `match()`. Ubuntu's default
`awk` is mawk, which doesn't support either. This was confirmed directly (mawk
either errors or silently produces wrong output on these constructs). The
Dockerfile installs gawk and runs `update-alternatives --set awk /usr/bin/gawk`
so the plain `awk` calls throughout the scripts resolve correctly.

### Why bedGraphToBigWig is re-fetched instead of using the repo's copy

The binary vendored in `pcliptools/bin/` is dynamically linked against
`libpng12.so.0`, a library Ubuntu/Debian dropped from their repositories in
2016. No current base image can apt-install a replacement. Confirmed the
vendored copy fails with:

```
error while loading shared libraries: libpng12.so.0: cannot open shared object file
```

Instead, the Dockerfile fetches UCSC's actively-rebuilt binary from
`https://hgdownload.gi.ucsc.edu/admin/exe/linux.x86_64/bedGraphToBigWig` at
build time and verifies (`ldd` + an execution check) that it resolves cleanly
against the libpng16 already on the image. If it doesn't, the build fails at
that step with a clear message instead of shipping a broken tool.

**Reproducibility trade-off:** that URL always serves UCSC's current rebuild,
not a pinned version, so the exact bytes can change between builds (its
directory listing showed the file was last rebuilt in June 2026 at the time
this was written). For a fully pinned build, swap in one of UCSC's dated
snapshot directories instead, e.g.
`https://hgdownload.gi.ucsc.edu/admin/exe/linux.x86_64.vNNN/bedGraphToBigWig`.

### Why STAR/cutadapt are apt packages, not source builds

`rna-star` on Ubuntu 24.04 is exactly v2.7.11b - one of the two versions the
pcliptools README lists as tested - and ships as a CPU-dispatch wrapper
(`/usr/bin/STAR` picks the best of avx2/avx/sse variants at runtime, falling
back to plain), which is more portable across hardware than a single
from-source build pinned to one machine's CPU flags would be. cutadapt (4.4)
is close to the tested 4.5/4.9 and uses only long-stable flags
(`-a`, `-g`, `--minimum-length`, `-u`, `-j`).

### Why apt for the Python stack instead of pip

Ubuntu 24.04 packages every Python dependency `pcliptools-compare-bed` needs
(numpy, pandas, pybedtools, matplotlib, matplotlib-venn) at versions that are
mutually compatible because Ubuntu built them together. Mixing in a pip
install of any of these (e.g. a newer numpy) risks shadowing the apt versions
via `/usr/local/lib/python3.*/dist-packages` taking import precedence over
`/usr/lib/python3/dist-packages`, which breaks ABI-sensitive compiled
extensions like `numexpr`/`bottleneck` that pandas optionally loads. This was
observed directly while testing in an environment that had an unrelated pip
numpy installed alongside the apt one; a clean `ubuntu:24.04` image with only
the apt packages in this Dockerfile does not hit this, and the Dockerfile
never calls `pip install` for anything pcliptools needs.

### Minor version gaps left as-is

samtools (1.19.2 vs README's "1.20+") and R (4.3.3 vs "4.4.1") are one minor
version behind what the README says was tested. Every samtools/R feature the
scripts actually use (the `mpileup`/`view` flags, `dplyr::rowwise/mutate`,
`poisson.test`, `p.adjust`) has been stable across these versions for years,
and the R pipeline was tested end-to-end against synthetic data with these
exact apt versions. Bumping either would mean building from source instead of
apt; happy to do that if you'd rather pin exactly.

## Updating pcliptools

```bash
git ls-remote https://github.com/paulahsan/pcliptools.git HEAD
docker build --build-arg PCLIPTOOLS_COMMIT=<new-sha> -t pcliptools .
```
