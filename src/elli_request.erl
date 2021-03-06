-module(elli_request).
-include("../include/elli.hrl").

-export([send_chunk/2
         , async_send_chunk/2
         , chunk_ref/1
         , path/1
         , raw_path/1
         , query_str/1
         , get_header/2
         , get_arg/2
         , get_arg/3
         , get_args/1
         , body_qs/1
         , headers/1
         , peer/1
         , method/1
         , body/1
         , get_header/3
         , to_proplist/1
        ]).

%%
%% Helpers for working with a #req{}
%%


%% @doc: Returns path split into binary parts.
path(#req{path = Path})          -> Path.
raw_path(#req{raw_path = Path})  -> Path.
headers(#req{headers = Headers}) -> Headers.
method(#req{method = Method})    -> Method.
body(#req{body = Body})          -> Body.

peer(#req{socket = Socket} = Req) ->
    case get_header(<<"X-Forwarded-For">>, Req, undefined) of
        undefined ->
            case inet:peername(Socket) of
                {ok, {Address, _}} ->
                    list_to_binary(inet_parse:ntoa(Address));
                {error, _} ->
                    undefined
            end;
        Ip ->
            Ip
    end.


get_header(Key, #req{headers = Headers}) ->
    proplists:get_value(Key, Headers).

get_header(Key, #req{headers = Headers}, Default) ->
    proplists:get_value(Key, Headers, Default).

get_arg(Key, #req{} = Req) ->
    get_arg(Key, Req, undefined).

get_arg(Key, #req{args = Args}, Default) ->
    proplists:get_value(Key, Args, Default).

%% @doc Parses application/x-www-form-urlencoded body into a proplist
body_qs(#req{body = Body}) ->
    elli_http:split_args(Body).


-spec get_args(#req{}) -> QueryArgs :: proplists:proplist().
%% @doc Returns a proplist of keys and values of the original query
%%      string.  Both keys and values in the returned proplists will
%%      be binaries or the atom `true' in case no value was supplied
%%      for the query key.
get_args(#req{args = Args}) -> Args.

-spec query_str(#req{}) -> QueryStr :: binary().
%% @doc Calculates the query string associated with the given Request
%% as a binary.
query_str(#req{raw_path = Path}) ->
    case binary:split(Path, [<<"?">>]) of
        [_, Qs] -> Qs;
        [_]     -> <<>>
    end.


%% @doc: Serializes the request record to a proplist. Useful for
%% logging
to_proplist(#req{} = Req) ->
    lists:zip(record_info(fields, req), tl(tuple_to_list(Req))).



%% @doc: Returns a reference that can be used to send chunks to the
%% client. If the protocol does not support it, returns {error,
%% not_supported}.
chunk_ref(#req{version = {1, 1}} = Req) ->
    Req#req.pid;
chunk_ref(#req{}) ->
    {error, not_supported}.

%% @doc: Sends a chunk asynchronously
async_send_chunk(Ref, Data) ->
    Ref ! {chunk, Data}.

%% @doc: Sends a chunk synchronously, if the refrenced process is dead
%% returns early with {error, closed} instead of timing out.
send_chunk(Ref, Data) ->
    case is_ref_alive(Ref) of
        false -> {error, closed};
        true  -> send_chunk(Ref, Data, 5000)
    end.

send_chunk(Ref, Data, Timeout) ->
    Ref ! {chunk, Data, self()},
    receive
        {Ref, ok} ->
            ok;
        {Ref, {error, Reason}} ->
            {error, Reason}
    after Timeout ->
            {error, timeout}
    end.

is_ref_alive(Ref) ->
    case node(Ref) =:= node(self()) of
        true -> is_process_alive(Ref);
        false -> rpc:call(node(Ref), erlang, is_process_alive, [Ref])
    end.
