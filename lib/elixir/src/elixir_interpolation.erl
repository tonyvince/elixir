% Handle string and string-like interpolations.
-module(elixir_interpolation).
-export([extract/5, unescape_chars/1, unescape_chars/2,
unescape_tokens/1, unescape_tokens/2, unescape_map/1]).
-include("elixir.hrl").

%% Extract string interpolations

extract(Line, Raw, Interpol, String, Last) ->
  %% Ignore whatever is in the scope and enable terminator checking.
  Scope = Raw#elixir_tokenizer{terminators=[], check_terminators=true},
  extract(Line, Scope, Interpol, String, [], [], [], Last).

%% Terminators

extract(Line, _Scope, _Interpol, [], Buffer, [], Output, []) ->
  finish_extraction(Line, Buffer, Output, []);

extract(Line, _Scope, _Interpol, [], _Buffer, [], _Output, Last) ->
  { error, { string, Line, io_lib:format("missing terminator: ~ts", [[Last]]), [] } };

extract(Line, _Scope, _Interpol, [Last|Remaining], Buffer, [], Output, Last) ->
  finish_extraction(Line, Buffer, Output, Remaining);

% extract(Line, _Scope, _Interpol, End, _Buffer, _Search, _Output, Last) when End == [Last]; End == [] ->
%   { error, { string, Line, io_lib:format("missing terminator: ~ts", [[Last]]), [] } };

%% Going through the string

extract(Line, Scope, Interpol, [$\n|Rest], Buffer, Search, Output, Last) ->
  extract(Line+1, Scope, Interpol, Rest, [$\n|Buffer], Search, Output, Last);

extract(Line, Scope, Interpol, [$\\, $#, ${|Rest], Buffer, [], Output, Last) ->
  extract(Line, Scope, Interpol, Rest, [${,$#|Buffer], [], Output, Last);

extract(Line, Scope, Interpol, [$\\,Char|Rest], Buffer, [], Output, Last) ->
  extract(Line, Scope, Interpol, Rest, [Char,$\\|Buffer], [], Output, Last);

extract(Line, Scope, true, [$#, ${|Rest], Buffer, [], Output, Last) ->
  Output1 = build_string(Line, Buffer, Output),

  case elixir_tokenizer:tokenize(Rest, Line, Scope) of
    { error, { EndLine, _, "}" }, [$}|NewRest], Tokens } ->
      Output2 = build_interpol(Line, Tokens, Output1),
      extract(EndLine, Scope, true, NewRest, [], [], Output2, Last);
    { error, Reason, _, _ } ->
      { error, Reason };
    { ok, _EndLine, _ } ->
      { error, { string, Line, "missing interpolation terminator: }", [] } }
  end;

%% Catch all clause

extract(Line, Scope, Interpol, [Char|Rest], Buffer, Search, Output, Last) ->
  extract(Line, Scope, Interpol, Rest, [Char|Buffer], Search, Output, Last).

%% Unescape a series of tokens as returned by extract.

unescape_tokens(Tokens) ->
  unescape_tokens(Tokens, fun unescape_map/1).

unescape_tokens(Tokens, Map) ->
  [unescape_token(Token, Map) || Token <- Tokens].

unescape_token(Token, Map) when is_binary(Token) -> unescape_chars(Token, Map);
unescape_token(Other, _Map) -> Other.

% Unescape chars. For instance, "\" "n" (two chars) needs to be converted to "\n" (one char).

unescape_chars(String) ->
  unescape_chars(String, fun unescape_map/1).

unescape_chars(String, Map) ->
  Octals = Map($0) /= false,
  Hex    = Map($x) /= false,
  unescape_chars(String, Map, Octals, Hex, <<>>).

unescape_chars(<<$\\,A,B,C,Rest/binary>>, Map, true, Hex, Acc) when ?is_octal(A), A =< $3, ?is_octal(B), ?is_octal(C) ->
  append_escaped(Rest, Map, [A,B,C], true, Hex, Acc, 8);

unescape_chars(<<$\\,A,B,Rest/binary>>, Map, true, Hex, Acc) when ?is_octal(A), ?is_octal(B) ->
  append_escaped(Rest, Map, [A,B], true, Hex, Acc, 8);

unescape_chars(<<$\\,A,Rest/binary>>, Map, true, Hex, Acc) when ?is_octal(A) ->
  append_escaped(Rest, Map, [A], true, Hex, Acc, 8);

unescape_chars(<<$\\,P,A,B,Rest/binary>>, Map, Octal, true, Acc) when (P == $x orelse P == $X), ?is_hex(A), ?is_hex(B) ->
  append_escaped(Rest, Map, [A,B], Octal, true, Acc, 16);

unescape_chars(<<$\\,P,A,Rest/binary>>, Map, Octal, true, Acc) when (P == $x orelse P == $X), ?is_hex(A) ->
  append_escaped(Rest, Map, [A], Octal, true, Acc, 16);

unescape_chars(<<$\\,P,${,A,$},Rest/binary>>, Map, Octal, true, Acc) when (P == $x orelse P == $X), ?is_hex(A) ->
  append_escaped(Rest, Map, [A], Octal, true, Acc, 16);

unescape_chars(<<$\\,P,${,A,B,$},Rest/binary>>, Map, Octal, true, Acc) when (P == $x orelse P == $X), ?is_hex(A), ?is_hex(B) ->
  append_escaped(Rest, Map, [A,B], Octal, true, Acc, 16);

unescape_chars(<<$\\,P,${,A,B,C,$},Rest/binary>>, Map, Octal, true, Acc) when (P == $x orelse P == $X), ?is_hex(A), ?is_hex(B), ?is_hex(C) ->
  append_escaped(Rest, Map, [A,B,C], Octal, true, Acc, 16);

unescape_chars(<<$\\,P,${,A,B,C,D,$},Rest/binary>>, Map, Octal, true, Acc) when (P == $x orelse P == $X), ?is_hex(A), ?is_hex(B), ?is_hex(C), ?is_hex(D) ->
  append_escaped(Rest, Map, [A,B,C,D], Octal, true, Acc, 16);

unescape_chars(<<$\\,P,${,A,B,C,D,E,$},Rest/binary>>, Map, Octal, true, Acc) when (P == $x orelse P == $X), ?is_hex(A), ?is_hex(B), ?is_hex(C), ?is_hex(D), ?is_hex(E) ->
    append_escaped(Rest, Map, [A,B,C,D,E], Octal, true, Acc, 16);

unescape_chars(<<$\\,P,${,A,B,C,D,E,F,$},Rest/binary>>, Map, Octal, true, Acc) when (P == $x orelse P == $X), ?is_hex(A), ?is_hex(B), ?is_hex(C), ?is_hex(D), ?is_hex(E), ?is_hex(F) ->
  append_escaped(Rest, Map, [A,B,C,D,E,F], Octal, true, Acc, 16);

unescape_chars(<<$\\,Escaped,Rest/binary>>, Map, Octals, Hex, Acc) ->
  case Map(Escaped) of
    false -> unescape_chars(Rest, Map, Octals, Hex, <<Acc/binary, $\\, Escaped>>);
    Other -> unescape_chars(Rest, Map, Octals, Hex, <<Acc/binary, Other>>)
  end;

unescape_chars(<<Char, Rest/binary>>, Map, Octals, Hex, Acc) ->
  unescape_chars(Rest, Map, Octals, Hex, <<Acc/binary, Char>>);

unescape_chars(<<>>, _Map, _Octals, _Hex, Acc) -> Acc.

append_escaped(Rest, Map, List, Octal, Hex, Acc, Base) ->
  Codepoint = list_to_integer(List, Base),
  unescape_chars(Rest, Map, Octal, Hex, <<Acc/binary, Codepoint/utf8>>).

% Unescape Helpers

unescape_map($a) -> 7;
unescape_map($b) -> $\b;
unescape_map($d) -> $\d;
unescape_map($e) -> $\e;
unescape_map($f) -> $\f;
unescape_map($n) -> $\n;
unescape_map($r) -> $\r;
unescape_map($s) -> $\s;
unescape_map($t) -> $\t;
unescape_map($v) -> $\v;
unescape_map(E)  -> E.

% Extract Helpers

finish_extraction(Line, Buffer, Output, Remaining) ->
  case build_string(Line, Buffer, Output) of
    []    -> Final = [<<>>];
    Final -> []
  end,
  { Line, lists:reverse(Final), Remaining }.

build_string(_Line, [], Output) -> Output;
build_string(_Line, Buffer, Output) ->
  [elixir_utils:characters_to_binary(lists:reverse(Buffer))|Output].

build_interpol(Line, Buffer, Output) ->
  [wrap_interpol(Line, forms(lists:reverse(Buffer), Line))| Output].

wrap_interpol(Line, Form) ->
  Meta = [{line,Line}],
  { '::', Meta, [{ { '.', Meta, ['Elixir.Kernel', to_string] }, Meta, [Form]}, { binary, Meta, nil }]}.

forms(Tokens, StartLine) ->
  try elixir_parser:parse(Tokens) of
    { ok, [] } -> nil;
    { ok, [Forms] } when not is_list(Forms) -> Forms;
    { ok, Forms } -> { '__block__', [{line,StartLine}], Forms };
    { error, { Line, _, [Error, Token] } } -> throw({ interpolation_error, { Line, Error, Token } })
  catch
    { error, { Line, _, [Error, Token] } } -> throw({ interpolation_error, { Line, Error, Token } })
  end.
