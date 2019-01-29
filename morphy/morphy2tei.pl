:- module(morphy2tei, []).
:- use_module(library(sgml)).
:- use_module(library(pwp)).
:- use_module(library(pure_input)).

:- multifile loader:mime_type_loader/4.
:- multifile mime:mime_extension/2.

:- multifile attribute_mapping/3.

mime:mime_extension(yaml, application/'x-yaml').
mime:mime_extension(yml, application/'x-yaml').

attribute_mapping(analysis, lemma, lemma).
attribute_mapping(fragment, label, label).
attribute_mapping(word, label, label).
attribute_mapping(word, fparent, parent).
attribute_mapping(part, parent, parent).
attribute_mapping(Kind, '*', conjecture) :- form_kind(Kind).

yaml(Pos, AL, [H|T]) --> entry(Pos, AL, H, AL1), !, { Pos1 is Pos + 1 }, yaml(Pos1, AL1, T).
yaml(_, AL, []) --> [], { maplist(finalize_attach, AL) }.

entry(Pos, AL, Kind:Pos = [value = Val | Attrs1], AL1) --> `-`, header(Kind),
    { memberchk(Kind, [fragment, word, part, punc, page, line, year]) },
    line_atom(Val),
    attributes(Kind, Attrs), { do_attach(Pos, Attrs, AL), make_attach_list(Attrs, AL, Attrs1, AL1) }, !, skip_lines.
entry(_, _, _, _) --> [_], syntax_error('cannot parse').    

do_attach(Pos, Attrs, AL) :- memberchk(parent = P, Attrs), !, memberchk(P = Att, AL),
    attach_to_list(Pos, Att).
do_attach(_, _, _).

make_attach_list(Attrs, AL, [attach = Att | Attrs], [Label = Att | AL]) :- memberchk(label = Label, Attrs), !.
make_attach_list(Attrs, AL, Attrs, AL).

attach_to_list(Pos, Att) :- var(Att), !, Att = [Pos | _].
attach_to_list(Pos, [_ | T]) :- attach_to_list(Pos, T).

finalize_attach(Att) :- var(Att), !, Att = [].
finalize_attach([_ | T]) :- !, finalize_attach(T).
finalize_attach(_ = L) :- finalize_attach(L).

skip_lines --> `\n`, !, skip_lines.
skip_lines --> `\r\n`, !, skip_lines.
skip_lines --> [].

attributes(Kind, [Key = Value|T]) --> attribute(Kind, Key, Value), !, attributes(Kind, T).
attributes(_, []) --> [].

attribute(Kind, analysis, Ana) --> { form_kind(Kind) },
    ` -`, header(ana), !, line(_), analysis_attributes(Ana).
attribute(Kind, dubious, form) --> { form_kind(Kind) }, ` ?!: !\n`, !.
attribute(_, error, Map) --> ` !: `, !, line_atom(X), { attribute_mapping(keyword, X, Map) }.
attribute(_, dubious, Map) --> ` ?: `, !, line_atom(X), { attribute_mapping(keyword, X, Map) }.
attribute(Kind, dubious, form) --> ` ?!: `, line(`!`), { form_kind(Kind) }, !.
attribute(Kind, Map, MapValue) --> ` `, header(Tag), { attribute_mapping(Kind, Tag, Map) }, line_atom(Value),
    { attribute_mapping(Map, Value, MapValue) -> true; MapValue = Value }.

analysis_attributes([Name = Value|T]) --> ` `, analysis_attribute(Name, Value), !, analysis_attributes(T).
analysis_attributes([]) --> [].

analysis_attribute(error, Map) --> attribute(_, error, Map), !.
analysis_attribute(dubious, Map) --> attribute(_, dubious, Map), !.
analysis_attribute(grdic, Values) --> ` `, header(grdic), !, tokens(Toks), { maplist(attribute_mapping(grdic), Toks, Values) }.
analysis_attribute(gramm, Values) --> ` `, header(gramm), !, tokens(Toks), { maplist(attribute_mapping(gramm), Toks, Values) }.
analysis_attribute(Map, MapValue) --> ` `, header(Tag), { attribute_mapping(analysis, Tag, Map) }, line_atom(Value),
    { attribute_mapping(Map, Value, MapValue) -> true; MapValue = Value }.

form_kind(Kind) :- memberchk(Kind, [fragment, word, part]).
    
line_atom(X) --> line(L), { atom_codes(X, L) }.

line([]) --> [0'\n], !.
line([]) --> `\r\n`, !.
line([H|T]) --> [H], !, line(T).

tokens([H|T]) --> token(H), !, nexttokens(T).
tokens([]) --> [0'\n].
tokens([]) --> `\r\n`.

nexttokens([H|T]) --> `, `, token(H), !, nexttokens(T).
nexttokens([]) --> [0'\n].
nexttokens([]) --> `\r\n`.

token(X) --> token0(L), { atom_codes(X, L) }.
token0([H|T]) --> [H], { H \== 0',, H \== 0'\n, H \== 0'\r }, !, token0(T).
token0([]) --> [].

header(Kind) --> kind0(L), `: `, { atom_codes(Kind, L) }.

kind0([H|T]) --> [H], { H \== 0': }, !, kind0(T).
kind0([]) --> [].

parse_yaml(Source, Entries) :- phrase_from_file(yaml(1, [], Entries), Source).

group_entries([word:Pos = Attrs|T], [word:Pos = [parts = Parts | Attrs0] | T1]) :- 
    selectchk(attach = L, Attrs, Attrs0), !,
    max_list(L, MaxPos),
    collect_parts(MaxPos, T, Parts, T1).
group_entries([H|T], [H|T1]) :- group_entries(T, T1).
group_entries([], []).

collect_parts(MaxPos, [Kind:Pos = Attrs | T], [Kind:Pos = Attrs | Parts], T1) :-
    Pos =< MaxPos, !,
    collect_parts(MaxPos, T, Parts, T1).
collect_parts(_, T, [], T1) :- group_entries(T, T1).

loader:mime_type_loader(application/'x-yaml', Source, Parameters, xml(Content)) :-
    load_structure(template('tei.pwp'), PWP, [dialect(xmlns)]),
    parse_yaml(Source, Entries),
    group_entries(Entries, Segments),
    pwp_xml(PWP, Content, ['PARAMETERS' = Parameters, 'SEGMENTS' = Segments]).



    