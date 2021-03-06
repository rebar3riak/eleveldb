%% -------------------------------------------------------------------
%%
%% Copyright (c) 2012-2017 Basho Technologies, Inc.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

%% @doc Assorted random generators for testing.
%%
%% It's not clear that this should be in a 'test' directory,
%% but it is what it is.
-module(rand_gen_1).

-export([
    almost_completely_sequential/3,
    mostly_sequential/2,
    pareto/2,
    pareto_as_bin/2,
    rand_uniform/0,
    rand_uniform/1,
    random_bin/2
]).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

%% !@#$! pareto key generators are not exported from basho_bench_keygen.erl
%%
%% Use a fixed shape for Pareto that will yield the desired 80/20
%% ratio of generated values.

-define(PARETO_SHAPE, 1.5).

%% ====================================================================
%% Public API
%% ====================================================================

%% @doc Return a generator function for random binaries.
%%
%% Creates a randomly-generated 16MB binary once, then assigns slices of
%% that binary quickly.  If you wish to avoid having easily compressible
%% data in LevelDB (or other backend) chunks, then Size should be much
%% much less than 16MB.
random_bin(_Id, Size) ->
    HunkSize = 16 * 1024 * 1024,
    BigHunk = rand_bytes(HunkSize),
    fun() ->
        Offset = rand_uniform(HunkSize - Size),
        <<_:Offset/binary, Bin:Size/binary, _/binary>> = BigHunk,
        Bin
    end.

%% @doc Return a generator for keys that look like <<"001328681207_012345">>.
%%
%% The suffix part (after the underscore) will be assigned either
%% os:timestamp/0's microseconds or an integer between 0 and MaxSuffix.
%% The integer between 0 & MaxSuffix will be chosen PercentAlmostSeq
%% percent of the time.
almost_completely_sequential(_Id, MaxSuffix, PercentAlmostSeq) ->
    SuffLimit = erlang:min((1000 * 1000), (MaxSuffix + 1)),
    fun() ->
        Rand = rand_mod(),  % inside the fun to be sure it's seeded in self()
        {A, B, C} = os:timestamp(),
        TimeT = (A * 1000000) + B,
        End = case Rand:uniform(100) of
            N when N < PercentAlmostSeq ->
                C;  % microseconds
            _ ->
                (Rand:uniform(SuffLimit) - 1)
        end,
        erlang:list_to_binary(lists:flatten(
            io_lib:format("~12.12.0w_~6.6.0w", [TimeT, End])))
    end.

%% @doc Return a generator for keys that look like <<"001328681207_012345">>.
%%
%% With probability of 1 - (MillionNotSequential/1000000), the keys
%% will be generated using os:timestamp/0, where the suffix is exactly
%% equal to the microseconds portion of os:timestamp/0's return value.
%% Such keys will be perfectly sorted for time series-style keys: each
%% key will be "greater than" any previous key.
%%
%% With probability of (MillionNotSequential/1000000), the key will
%% still have the same "integer1_integer2" form, but the first integer
%% will be up to approximately 3 million seconds earlier than the current
%% time_t wall clock time, and the second integer will be generated by
%% rand_uniform(1000*1000).
%%
%% As MillionNotSequential approaches zero, the keys generated will
%% become more and more perfectly sorted.
mostly_sequential(_Id, MillionNotSequential) ->
    fun() ->
        Rand = rand_mod(),  % inside the fun to be sure it's seeded in self()
        {A, B, _} = TS = os:timestamp(),
        {X, Y, Z} = case Rand:uniform(1000 * 1000) < MillionNotSequential of
            true ->
                { (A - (Rand:uniform(4) - 1)),
                  erlang:abs(B - (Rand:uniform(500 * 1000) - 1)),
                  (Rand:uniform(1000 * 1000) - 1) };
            _ ->
                TS
        end,
        TimeT = (X * 1000000) + Y,
        %% e.g. 001328681207_012345
        erlang:list_to_binary(lists:flatten(
            io_lib:format("~12.12.0w_~6.6.0w", [TimeT, Z])))
    end.

%% @doc Return generator of pareto-distributed integers as binaries.
%%
%% Useful for basho_bench plugins that are expecting its keys
%% be Erlang binary terms.
pareto_as_bin(_Id, MaxKey) ->
    Pareto = pareto(trunc(MaxKey * 0.2), ?PARETO_SHAPE),
    fun() ->
        erlang:list_to_binary(io_lib:format("~w", [Pareto()]))
    end.

pareto(Mean, Shape) ->
    S1 = (-1 / Shape),
    S2 = Mean * (Shape - 1),
    fun() ->
        U = 1 - rand_uniform(),
        trunc((math:pow(U, S1) - 1) * S2)
    end.

%% @doc Equivalent to rand/random uniform/0, always seeded.
rand_uniform() ->
    Mod = rand_mod(),
    Mod:uniform().

%% @doc Equivalent to rand/random uniform/1, always seeded.
rand_uniform(N) ->
    Mod = rand_mod(),
    Mod:uniform(N).

%% ====================================================================
%% Internal
%% ====================================================================

% crypto:rand_bytes/1 is deprecated, but use it if it's still around because
% we don't need the strong stuff and we'd rather not deplete the entropy pool
rand_bytes(Size) ->
    Key = {?MODULE, rand_bytes},
    Func = case erlang:get(Key) of
        undefined ->
            F = case lists:member({rand_bytes, 1}, crypto:module_info(exports)) of
                true ->
                    rand_bytes;
                _ ->
                    strong_rand_bytes
            end,
            _ = erlang:put(Key, F),
            F;
        Val ->
            Val
    end,
    crypto:Func(Size).

rand_mod() ->
    Key = {?MODULE, rand_mod},
    case erlang:get(Key) of
        undefined ->
            Mod = case otp_version() < 18 of
                true ->
                    M = random,
                    case erlang:get(random_seed) of
                        undefined ->
                            _ = M:seed(os:timestamp()),
                            M;
                        _ ->
                            M
                    end;
                _ ->
                    rand
            end,
            _ = erlang:put(Key, Mod),
            Mod;
        Val ->
            Val
    end.

otp_version() ->
    {Vsn, _} = string:to_integer(
        case erlang:system_info(otp_release) of
            [$R | Rel] ->
                Rel;
            Rel ->
                Rel
        end),
    Vsn.

%% ====================================================================
%% Tests
%% ====================================================================

-ifdef(TEST).

rand_mod_test() ->
    Expect = case code:which(rand) of
        non_existing ->
            random;
        _ ->
            rand
    end,
    ?assertEqual(Expect, rand_mod()).

rand_bin_test() ->
    Size = 9999 + rand_uniform(9999),
    Gen = random_bin(99, Size),
    lists:foldl(
        fun(_, Last) ->
            Bin = Gen(),
            ?assertEqual(Size, erlang:byte_size(Bin)),
            ?assertNotEqual(Bin, Last),
            Bin
        end, Gen(), lists:seq(1, 97)),
    ok.

seq_size_test() ->
    Fun1 = almost_completely_sequential(7, (rand_uniform(1000000) - 1), 50),
    Fun2 = mostly_sequential(11, rand_uniform(1000000)),
    ?assertEqual(19, erlang:byte_size(Fun1())),
    ?assertEqual(19, erlang:byte_size(Fun2())).

-endif. % TEST
