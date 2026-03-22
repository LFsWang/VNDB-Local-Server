# Local VNDB Server

- [ ] web - :x: not working
- [v] api - work with vndbid (search by title no work)

check the [SETUP.md](SETUP.en.md) / [中文版本](SETUP.md) to build the docker container

## VNDB Readme

### 1. Introduction

This page lists and documents any provided database dumps. These dumps are complimentary to the real-time API, and the usage terms that apply to the API apply here as well.

### 2. Tags

- File: vndb-tags-latest.json.gz (more files).

- Updated: Every day around 8:00 UTC.

- License: Open Database License + Database Contents License, see our Data License for more information.

This dump includes information about all (approved) VN tags in the JSON format. The top-level type is an array of tags, and each tag is represented as an object with the following members:

| Member      | Type              | null? | Description                                                                                                                         |
| ----------- | ----------------- | ----- | ----------------------------------------------------------------------------------------------------------------------------------- |
| id          | integer           | no    | Tag ID                                                                                                                              |
| name        | string            | no    | Tag name                                                                                                                            |
| description | string            | no    | Can include formatting codes as described in d9#3.                                                                                  |
| meta        | bool              | no    | Whether this is a meta tag or not. This field only exists for backwards compatibility and is currently the inverse of "searchable". |
| searchable  | bool              | no    | Whether it's possible to filter VNs by this tag.                                                                                    |
| applicable  | bool              | no    | Whether this tag can be applied to VN entries.                                                                                      |
| vns         | integer           | no    | Number of tagged VNs (including child tags)                                                                                         |
| cat         | string            | no    | Tag category/classification: "cont" for content, "ero" for sexual stuff, and "tech" for technical details.                          |
| aliases     | array of strings  | no    | (Possibly empty) list of alternative names.                                                                                         |
| parents     | array of integers | no    | List of parent tags (empty for root tags). The first element in this array points to the primary parent tag.                        |

Tag names and their aliases are globally unique and self-describing. See the tag creation guidelines for more information.

### 3. Traits

- File: vndb-traits-latest.json.gz (more files).

- ~~Updated: Every day around 8:00 UTC.~~

- License: Open Database License + Database Contents License, see our Data License for more information.

This dump includes information about all (approved) character traits in the JSON format. The top-level type is an array of traits, and each trait is represented as an object with the following members:

| Member      | Type              | null? | Description                                                                                                                           |
| ----------- | ----------------- | ----- | ------------------------------------------------------------------------------------------------------------------------------------- |
| id          | integer           | no    | Trait ID                                                                                                                              |
| name        | string            | no    | Trait name                                                                                                                            |
| description | string            | no    | Can include formatting codes as described in d9#3.                                                                                    |
| meta        | bool              | no    | Whether this is a meta trait or not. This field only exists for backwards compatibility and is currently the inverse of "searchable". |
| searchable  | bool              | no    | Whether it's possible to filter characters by this trait.                                                                             |
| applicable  | bool              | no    | Whether this trait can be applied to character entries.                                                                               |
| sexual      | bool              | no    | Whether this trait indicates sexual content.                                                                                          |
| chars       | integer           | no    | Number of characters on which this trait and any child traits is used.                                                                |
| aliases     | array of strings  | no    | (Possibly empty) list of alternative names.                                                                                           |
| parents     | array of integers | no    | List of parent traits (empty for root traits). The first element in this array points to the primary parent trait.                    |

Unlike with tags, trait names and aliases are neither globally unique nor self-describing. If you wish to display a trait (name) to the user, you should do so in combination with its associated root trait. For example, i112 is often displayed as "Eyes > Green", to differentiate it with i50, which is "Hair > Green". The root trait can be found by following the primary parents until you've ended up on the trait with an empty parents array.

### 4. Votes

File: vndb-votes-latest.gz (more files).

Updated: Every day around 8:00 UTC.

License: Open Database License, see our Data License for more information.

This dump contains the VN votes of all users who did not mark their vote list as private. Votes from known duplicate accounts or from users who voted on unreleased VNs are also not included.

Each line in the file represents a single vote. Each line contains the VN id, user ID, vote, and date that the vote was cast, separated by a space. Votes are as listed on the site, multiplied by 10 (i.e. in the range of 10 - 100).

### 5. Near-complete database

File: vndb-db-latest.tar.zst (more files).

Updated: Every day around 8:00 UTC.

License: See our Data License or the included README.txt for license information.

This dump contains almost everything in VNDB, except for the following:

- Anything discussion board related.
- Change histories of database entries.
- Database entries that have been deleted.
- Lists from users who have made that private.
- Any other user info that is not strictly necessary for cross-referencing with other DB entries.
- Tables & columns that are derived from included data (i.e. caches).
- This database dump is NOT considered a stable API. The schema and the semantics of the different tables and fields is expected to change over time.

### 6. Images

- Command: rsync -rtpv --del rsync://dl.vndb.org/vndb-img/ vndb-img/

- Updated: Every day around 8:00 UTC.

- License: Open Database License for the collection, use of individual images is considered "fair use". See our Data License for more information.

This rsync server includes all images referenced from the database dumps. Images are divided among the following directories:

Name Approx. size Approx. num files Description
ch 3.5 GiB 140k Character images
cv 9 GiB 80k Visual Novel / release covers and package artwork
cv.t 1.5 GiB 35k Thumbnails for 'cv', only for images where the original is larger than 256x400
sf 30 GiB 170k Full-size screenshots
sf.t 1.5 GiB ^ Screenshot thumbnails

All directories include NSFW images, sometimes with very explicit content. The appropriate metadata can be found in the 'images' table in the near-complete database dump.

The bandwidth and number of concurrent connections are strictly limited in order to preserve server resources, so please have patience when downloading a full copy. Prefer incremental updates over redownloading a full copy, but don't scan for updates more than once a day - the published files aren't updated more often than that anyway.
