# Erlang bindings to the LevelDB datastore 

This project is forked from [Basho eleveldb](https://github.com/basho/eleveldb) and modified for use within R3R.

## Status

| `master` | `develop` |
|----------|-----------|
|[![Build Status](https://travis-ci.org/rebar3riak/eleveldb.svg?branch=master)](https://travis-ci.org/rebar3riak/eleveldb)|[![Build Status](https://travis-ci.org/rebar3riak/eleveldb.svg?branch=develop)](https://travis-ci.org/rebar3riak/eleveldb)|

## Upstream README

***This is ancient and needs to be reviewed!***

This repository follows the Basho standard for branch management 
as of November 28, 2013.  The standard is found here:

https://github.com/basho/riak/wiki/Basho-repository-management

In summary, the "develop" branch contains the most recently reviewed
engineering work.  The "master" branch contains the most recently
released work, i.e. distributed as part of a Riak release.

## Iterating Records

### High-level Iterator Interface

The interface that most clients of eleveldb should use when iterating over a set of records stored in leveldb is `fold`, since this fits nicely with the Erlang way of doing things.

For those who need more control over the process of iterating over records, you can use direct iterator actions. Use them with great care.

### Direct Iterator Actions

#### seek/next/prev

- **seek:** Move iterator to a new position.

- **next:** Move forward one position and return the value; do nothing else.

- **prev:** Move backward one position and return the value; do nothing else.

#### prefetc/prefetch_stop

- **prefetch:** Perform a `next` action and then start a parallel call for the subsequent `next` while Erlang processes the current `next`. The subsequent `prefetch` may return immediately with the value already retrieved.

- **prefetch_stop:** Stop a sequence of `prefetch` calls. If there is a parallel `prefetch` pending, cancel it, since we are about to move the pointer.

#### Warning

Either use `prefetch`/`prefetch_stop` or `next`/`prev`.  Do not intermix `prefetch` and `next`/`prev`.  You must `prefetch_stop` after one or more `prefetch` operations before using any of the other operations (`seek`, `next`, `prev`).

