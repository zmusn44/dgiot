%%--------------------------------------------------------------------
%% Copyright (c) 2020-2021 DGIOT Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(dgiot_tdengine_field).
-author("jonliu").
-include("dgiot_tdengine.hrl").
-include_lib("dgiot/include/logger.hrl").

-export([add_field/4, get_field/1, check_fields/2, check_fields/3, get_time/2, check_value/3]).

add_field(#{<<"type">> := <<"enum">>}, Database, TableName, LowerIdentifier) ->
    <<"ALTER TABLE ", Database/binary, TableName/binary, " ADD COLUMN ", LowerIdentifier/binary, " INT;">>;
add_field(#{<<"type">> := <<"file">>} = Spec, Database, TableName, LowerIdentifier) ->
    Size = integer_to_binary(min(maps:get(<<"size">>, Spec, 50), 200)),
    <<"ALTER TABLE ", Database/binary, TableName/binary, " ADD COLUMN ", LowerIdentifier/binary, " NCHAR(", Size/binary, ");">>;
add_field(#{<<"type">> := <<"text">>} = Spec, Database, TableName, LowerIdentifier) ->
    Size = integer_to_binary(min(maps:get(<<"size">>, Spec, 50), 200)),
    <<"ALTER TABLE ", Database/binary, TableName/binary, " ADD COLUMN ", LowerIdentifier/binary, " NCHAR(", Size/binary, ");">>;
add_field(#{<<"type">> := <<"url">>} = Spec, Database, TableName, LowerIdentifier) ->
    Size = integer_to_binary(min(maps:get(<<"size">>, Spec, 50), 200)),
    <<"ALTER TABLE ", Database/binary, TableName/binary, " ADD COLUMN ", LowerIdentifier/binary, " NCHAR((", Size/binary, ");">>;
add_field(#{<<"type">> := <<"geopoint">>} = Spec, Database, TableName, LowerIdentifier) ->
    Size = integer_to_binary(min(maps:get(<<"size">>, Spec, 50), 200)),
    <<"ALTER TABLE ", Database/binary, TableName/binary, " ADD COLUMN ", LowerIdentifier/binary, " NCHAR(", Size/binary, ");">>;
add_field(#{<<"type">> := <<"image">>}, Database, TableName, LowerIdentifier) ->
    <<"ALTER TABLE ", Database/binary, TableName/binary, " ADD COLUMN ", LowerIdentifier/binary, " BIGINT;">>;
add_field(#{<<"type">> := <<"date">>}, Database, TableName, LowerIdentifier) ->
    <<"ALTER TABLE ", Database/binary, TableName/binary, " ADD COLUMN ", LowerIdentifier/binary, " TIMESTAMP;">>;
add_field(#{<<"type">> := <<"long">>}, Database, TableName, LowerIdentifier) ->
    <<"ALTER TABLE ", Database/binary, TableName/binary, " ADD COLUMN ", LowerIdentifier/binary, " BIGINT;">>;
add_field(#{<<"type">> := Type}, Database, TableName, LowerIdentifier) ->
    <<"ALTER TABLE ", Database/binary, TableName/binary, " ADD COLUMN ", LowerIdentifier/binary, " ", Type/binary, ";">>.

%%  https://www.taosdata.com/cn/documentation/taos-sql#data-type
%%  #	??????       	Bytes    ??????
%%  1	TIMESTAMP   8        ???????????????????????????????????????????????????????????????????????? 1970-01-01 00:00:00.000 (UTC/GMT) ????????????????????????????????????????????? 2.0.18.0 ?????????????????????????????????????????????????????????
%%  2	INT       	4        ??????????????? [-2^31+1, 2^31-1], -2^31 ?????? NULL
%%  3	BIGINT      8        ?????????????????? [-2^63+1, 2^63-1], -2^63 ?????? NULL
%%  4	FLOAT       4        ???????????????????????? 6-7????????? [-3.4E38, 3.4E38]
%%  5	DOUBLE      8        ????????????????????????????????? 15-16????????? [-1.7E308, 1.7E308]
%%  6	BINARY      ?????????    ???????????????????????????????????????????????? ASCII ???????????????????????????????????????????????? nchar?????????????????????????????? 16374 ???????????????????????????????????? 16K ?????????????????????????????????????????????binary ??????????????????????????????????????????????????????????????????????????????????????????????????? binary(20) ?????????????????? 20 ???????????????????????????????????????????????? 1 byte ???????????????????????????????????? 20 bytes ????????????????????????????????????????????? 20 ??????????????????????????????????????????????????????????????????????????????????????????????????????????????? \??????
%%  7	SMALLINT    2        ???????????? ?????? [-32767, 32767], -32768 ?????? NULL
%%  8	TINYINT     1        ???????????????????????? [-127, 127], -128 ?????? NULL
%%  9	BOOL       	1        ????????????{true, false}
%%  10	NCHAR       ?????????    ???????????????????????????????????????????????????????????????????????? nchar ???????????? 4 bytes ??????????????????????????????????????????????????????????????????????????????????????????????????? \??????nchar ????????????????????????????????????????????? nchar(10) ?????????????????????????????????????????? 10 ??? nchar ???????????????????????? 40 bytes ???????????????????????????????????????????????????????????????????????????
get_field(#{<<"isstorage">> := false}) ->
    pass;
get_field(#{<<"isstorage">> := true} = Property) ->
    get_field_(Property);
get_field(#{<<"isshow">> := true} = Property) ->
    get_field_(Property);
get_field(_) ->
    pass.
get_field_(#{<<"identifier">> := Field, <<"dataType">> := #{<<"type">> := <<"int">>}}) ->
    {Field, #{<<"type">> => <<"INT">>}};
get_field_(#{<<"identifier">> := Field, <<"dataType">> := #{<<"type">> := <<"image">>}}) ->
    {Field, #{<<"type">> => <<"BIGINT">>}};
get_field_(#{<<"identifier">> := Field, <<"dataType">> := #{<<"type">> := <<"long">>}}) ->
    {Field, #{<<"type">> => <<"BIGINT">>}};
get_field_(#{<<"identifier">> := Field, <<"dataType">> := #{<<"type">> := <<"float">>}}) ->
    {Field, #{<<"type">> => <<"FLOAT">>}};
get_field_(#{<<"identifier">> := Field, <<"dataType">> := #{<<"type">> := <<"date">>}}) ->
    {Field, #{<<"type">> => <<"TIMESTAMP">>}};
get_field_(#{<<"identifier">> := Field, <<"dataType">> := #{<<"type">> := <<"bool">>}}) ->
    {Field, #{<<"type">> => <<"BOOL">>}};
get_field_(#{<<"identifier">> := Field, <<"dataType">> := #{<<"type">> := <<"double">>}}) ->
    {Field, #{<<"type">> => <<"DOUBLE">>}};
get_field_(#{<<"identifier">> := Field, <<"dataType">> := #{<<"type">> := <<"string">>} = Spec}) ->
    Size = integer_to_binary(min(maps:get(<<"size">>, Spec, 10), 200)),
    {Field, #{<<"type">> => <<"NCHAR(", Size/binary, ")">>}};
get_field_(#{<<"identifier">> := Field, <<"dataType">> := #{<<"type">> := <<"text">>} = Spec}) ->
    Size = integer_to_binary(min(maps:get(<<"size">>, Spec, 50), 200)),
    {Field, #{<<"type">> => <<"NCHAR(", Size/binary, ")">>}};
get_field_(#{<<"identifier">> := Field, <<"dataType">> := #{<<"type">> := <<"geopoint">>} = Spec}) ->
    Size = integer_to_binary(min(maps:get(<<"size">>, Spec, 50), 200)),
    {Field, #{<<"type">> => <<"NCHAR(", Size/binary, ")">>}};
get_field_(#{<<"identifier">> := Field, <<"dataType">> := #{<<"type">> := <<"enum">>, <<"specs">> := _Specs}}) ->
%%    Size = integer_to_binary(maps:size(Specs)),
    {Field, #{<<"type">> => <<"INT">>}};
get_field_(#{<<"identifier">> := Field, <<"dataType">> := #{<<"type">> := <<"struct">>, <<"specs">> := SubFields}}) ->
    [get_field(SubField#{<<"identifier">> => ?Struct(Field, Field1)}) || #{<<"identifier">> := Field1} = SubField <- SubFields].


check_value(Value, ProductId, Field) ->
    case dgiot_product:get_product_identifier(ProductId, Field) of
        not_find ->
            Value;
        #{<<"dataType">> := #{<<"type">> := Type} = DataType} ->
            Specs = maps:get(<<"specs">>, DataType, #{}),
            Type1 = list_to_binary(string:to_upper(binary_to_list(Type))),
            NewValue = get_type_value(Type1, Value, Specs),
            case check_validate(NewValue, Specs) of
                true ->
                    NewValue;
                false ->
                    BinNewValue = dgiot_utils:to_binary(NewValue),
                    throw({error, <<Field/binary, "=", BinNewValue/binary, " is not validate">>})
            end
    end.

check_fields(Data, #{<<"properties">> := Props}) ->
    check_fields(Data, Props);
check_fields(Data, Props) -> check_fields(Data, Props, #{}).
check_fields(Data, Props, Acc) when Data == []; Props == [] -> Acc;
check_fields(Data, [#{<<"identifier">> := Field, <<"dataType">> := #{<<"type">> := Type} = DataType} = Prop | Other], Acc) ->
    LowerField = list_to_binary(string:to_lower(binary_to_list(Field))),
    case check_field(Data, Prop) of
        undefined ->
            check_fields(Data, Other, Acc);
        Value ->
            case list_to_binary(string:to_upper(binary_to_list(Type))) of
                <<"STRUCT">> ->
                    #{<<"specs">> := SubFields} = DataType,
                    Acc2 = lists:foldl(
                        fun(#{<<"identifier">> := Field1} = SubField, Acc1) ->
                            case check_field(Value, SubField) of
                                undefined ->
                                    Acc1;
                                Value1 ->
                                    LowerField1 = list_to_binary(string:to_lower(binary_to_list(Field1))),
                                    Acc1#{?Struct(LowerField, LowerField1) => Value1}
                            end
                        end, Acc, SubFields),
                    check_fields(Data, Other, Acc2);
                _ ->
                    check_fields(Data, Other, Acc#{LowerField => Value})
            end
    end.

check_field(Data, #{<<"identifier">> := Field, <<"dataType">> := #{<<"type">> := Type} = DataType}) ->
    Specs = maps:get(<<"specs">>, DataType, #{}),
    case maps:get(Field, Data, undefined) of
        undefined ->
            undefined;
        Value ->
            Type1 = list_to_binary(string:to_upper(binary_to_list(Type))),
            NewValue = get_type_value(Type1, Value, Specs),
            case check_validate(NewValue, Specs) of
                true ->
                    NewValue;
                false ->
                    throw({error, <<Field/binary, " is not validate">>})
            end
    end;

check_field(_, _) ->
    undefined.

check_validate(null, _) ->
    true;
check_validate(Value, #{<<"max">> := Max, <<"min">> := Min}) when is_integer(Max), is_integer(Min) ->
    Value =< Max andalso Value >= Min;
check_validate(Value, #{<<"max">> := Max}) when is_integer(Max) ->
    Value =< Max;
check_validate(Value, #{<<"min">> := Min}) when is_integer(Min) ->
    Value >= Min;
check_validate(_, _) ->
    true.

get_time(V, Interval) ->
    NewV =
        case binary:split(V, <<$T>>, [global, trim]) of
            [_, _] ->
                V;
            _ ->
                case binary:split(V, <<$.>>, [global, trim]) of
                    [NewV1, _] ->
                        NewV1;
                    _ ->
                        V
                end
        end,
    Size = erlang:size(Interval) - 1,
    <<_:Size/binary, Type/binary>> = Interval,
    case Type of
        <<"a">> ->
            NewV;
        <<"s">> ->
            dgiot_datetime:format(dgiot_datetime:to_localtime(NewV), <<"DD HH:NN:SS">>);
        <<"m">> ->
            dgiot_datetime:format(dgiot_datetime:to_localtime(NewV), <<"MM-DD HH:NN">>);
        <<"h">> ->
            dgiot_datetime:format(dgiot_datetime:to_localtime(NewV), <<"MM-DD HH">>);
        <<"d">> ->
            dgiot_datetime:format(dgiot_datetime:to_localtime(NewV), <<"YY-MM-DD">>);
        <<"y">> ->
            dgiot_datetime:format(dgiot_datetime:to_localtime(NewV), <<"YY">>);
        <<"H">> ->
            dgiot_datetime:format(dgiot_datetime:to_localtime(NewV), <<"HH">>);
        <<"D">> ->
            dgiot_datetime:format(dgiot_datetime:to_localtime(NewV), <<"DD">>);
        <<"M">> ->
            dgiot_datetime:format(dgiot_datetime:to_localtime(NewV), <<"MM">>);
        _ ->
            dgiot_datetime:format(dgiot_datetime:to_localtime(NewV), <<"YY-MM-DD HH:NN:SS">>)
    end.


get_type_value(_, null, _) ->
    null;
get_type_value(Type, Value, _Specs) when Type == <<"INT">>; Type == <<"DATE">>; Type == <<"SHORT">>; Type == <<"LONG">>; Type == <<"ENUM">>, is_list(Value) ->
   round(dgiot_utils:to_int(Value));
get_type_value(Type, Value, _Specs) when Type == <<"INT">>; Type == <<"DATE">>, is_float(Value) ->
   round(Value);
get_type_value(Type, Value, _Specs) when Type == <<"INT">>; Type == <<"DATE">> ->
    Value;
get_type_value(Type, Value, Specs) when Type == <<"FLOAT">>; Type == <<"DOUBLE">> ->
    Precision = maps:get(<<"precision">>, Specs, 3),
    case size(dgiot_utils:to_binary(Value)) of
        0 ->
            0;
        _ ->
            dgiot_utils:to_float(Value, Precision)
    end;
get_type_value(<<"BOOL">>, Value, _Specs) ->
    Value;
get_type_value(<<"TEXT">>, Value, _Specs) ->
    {unicode:characters_to_binary(unicode:characters_to_list((dgiot_utils:to_binary(Value)))), text};
get_type_value(<<"GEOPOINT">>, Value, _Specs) ->
    {unicode:characters_to_binary(unicode:characters_to_list((Value))), text};
get_type_value(<<"STRUCT">>, Value, _Specs) ->
    Value;
get_type_value(<<"IMAGE">>, Value, _Specs) ->
    round(dgiot_utils:to_int(Value));
get_type_value(_, Value, _Specs) ->
    Value.
