---
title: Cite this software
description: How to cite __REPO_NAME__ in a paper, and how the maintainer gets a DOI for each release.
type: how-to
audience: [user, admin]
---

# Cite this software

## Cite a release

On the repository's GitHub page, select **Cite this repository** in the
sidebar. GitHub builds an APA or BibTeX citation from `CITATION.cff` in the
root of the repository. Name the release you used, for example `v1.2.0`, so
that others can reproduce your results.

When the repository has a DOI (see the next section), cite the DOI of the
release you used. The concept DOI always points to the newest release.

## Get a DOI for each release (maintainer)

[Zenodo](https://zenodo.org/) archives each GitHub release and gives it a
DOI. This is a one-time setup by the maintainer, and it works only for
public repositories.

1. Sign in to Zenodo with GitHub, open **GitHub** in your account settings,
   and turn the switch on for this repository.
2. Publish the next release as usual by merging the release pull request.
   Zenodo archives it within a few minutes and reads `CITATION.cff` for the
   title and authors.
3. Copy the concept DOI (the one for all versions) from the Zenodo record.
   Add it to `CITATION.cff` as `doi: 10.5281/zenodo.NNNNNNN`, and add the
   DOI badge Zenodo offers under the README title.

## Keep the authors current

`CITATION.cff` lists people, not accounts. Add each author with
`given-names`, `family-names` and, when they have one, `orcid`. Check the
file with:

```bash
uvx cffconvert --validate
```
