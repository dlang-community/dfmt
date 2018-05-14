# Contributors Guide


### dfmt follows the neptune versioning scheme 

The following is taken verbatim from
https://github.com/sociomantic-tsunami/neptune/blob/master/doc/library-contributor.rst


## Submitting Pull Requests

When making a PR to a Neptune-versioned library, the choice of which branch to
submit a PR against is important. A branch should be chosen as follows:

* If your change is a bug fix, the PR should be submitted against the oldest
  supported minor branch.
* If your change is a new feature, refactoring, or deprecation, the PR should be
  submitted against the oldest supported major branch.
* If your change is a breaking change to the API, the PR should be submitted
  against the next unreleased major branch. 
  (In case the v1.0.0 has not been reached this is void)


## Major and Minor Releases

When making a commit to a Neptune-versioned library, API-affecting changes
should be noted in a file in the ``relnotes`` folder, as follows. When the
corresponding branch is released, the files in that folder will be collated to
form the notes for the release.

The following procedure should be followed:

1. Look at each commit you're making and note whether it contains any of the
   following:

   * Breaking changes to user-available features (i.e. to the library's API).
   * New user-available features.
   * Deprecations of user-available features.

2. For each change noted in step 1, write a description of the change. The
   descriptions should be written so as to be understandable to users of the
   library and should explain the impact of the change, as well as any helpful
   procedures to adapt existing code (as necessary).

   The descriptions of changes should be written in the following form:

     ### Catchy, max 80 characters description of the change

     `name.of.affected.module` [, `name.of.another.affected.module`]

     One or more lines describing the changes made. Each of these description
     lines should be at most 80 characters long.

3. Insert your descriptions into files in the library's ``relnotes`` folder,
   named as follows: ``<name>.<change-type>.md``:

   * ``<name>`` can be whatever you want, but should indicate the change made.
   * ``<change-type>`` should be one of: ``migration``, ``feature``,
     ``deprecation``.
   * e.g. ``add-suspendable-throttler.feature.md``,
     ``change-epoll-selector.migration.md``.

   Normally, you'll create a new file with the selected name, but it's also ok
   to add further notes to an existing file, if the new changes fall under the
   same area. It is also sometimes possible that a change will require the
   release notes for a previous change to be modified.

4. Add your release notes in the same commit where the corresponding changes
   occur.
