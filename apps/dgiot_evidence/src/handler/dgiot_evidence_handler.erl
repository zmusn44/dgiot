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

-module(dgiot_evidence_handler).
-author("johnliu").
-behavior(dgiot_rest).
-dgiot_rest(all).
-include_lib("dgiot/include/logger.hrl").

%% API
-export([swagger_system/0]).
-export([handle/4]).

%% API描述
%% 支持二种方式导入
%% 示例:
%% 1. Metadata为map表示的JSON,
%%    dgiot_http_server:bind(<<"/system">>, ?MODULE, [], Metadata)
%% 2. 从模块的priv/swagger/下导入
%%    dgiot_http_server:bind(<<"/swagger_system.json">>, ?MODULE, [], priv)
swagger_system() ->
    [
        dgiot_http_server:bind(<<"/swagger_evidence.json">>, ?MODULE, [], priv)
    ].

%%%===================================================================
%%% 请求处理
%%%  如果登录, Context 内有 <<"user">>, version
%%%===================================================================

-spec handle(OperationID :: atom(), Args :: map(), Context :: map(), Req :: dgiot_req:req()) ->
    {Status :: dgiot_req:http_status(), Body :: map()} |
    {Status :: dgiot_req:http_status(), Headers :: map(), Body :: map()} |
    {Status :: dgiot_req:http_status(), Headers :: map(), Body :: map(), Req :: dgiot_req:req()}.

handle(OperationID, Args, Context, Req) ->
    Headers = #{},
    case catch do_request(OperationID, Args, Context, Req) of
        {ErrType, Reason} when ErrType == 'EXIT'; ErrType == error ->
            Err = case is_binary(Reason) of
                      true -> Reason;
                      false -> dgiot_utils:format("~p", [Reason])
                  end,
            {500, Headers, #{<<"error">> => Err}};
        ok ->
            {200, Headers, #{}, Req};
        {ok, Res} ->
            {200, Headers, Res, Req};
        {Status, Res} ->
            {Status, Headers, Res, Req};
        {Status, NewHeaders, Res} ->
            {Status, maps:merge(Headers, NewHeaders), Res, Req};
        {Status, NewHeaders, Res, NewReq} ->
            {Status, maps:merge(Headers, NewHeaders), Res, NewReq}
    end.


%%%===================================================================
%%% 内部函数 Version:API版本
%%%===================================================================
do_request(post_evidence, Args, #{<<"sessionToken">> := SessionToken} = _Context, Req) ->
    ?LOG(info, "Args ~p ", [Args]),
    case dgiot_evidence:post(Args#{<<"sessionToken">> => SessionToken}) of
        {ok, Result} ->
            {200, Result};
        {error, Reason} ->
            {error, Reason}
    end;

do_request(put_evidence, #{<<"status">> := Status} = Args, #{<<"sessionToken">> := SessionToken} = _Context, Req) ->
    ?LOG(info, "Status ~p ", [Status]),
    Host = dgiot_req:host(Req),
    dgiot_evidence:put(Args#{<<"ip">> => Host}, SessionToken);


do_request(get_evidence, #{<<"reportId">> := _ReportId} = Args, #{<<"sessionToken">> := SessionToken} = _Context, _Req) ->
    case dgiot_evidence:get(Args, SessionToken) of
        {ok, Result} ->
            {200, Result};
        {error, Reason} ->
            {error, Reason}
    end;

do_request(get_cert, _Args, _Context, _Req) ->
    case dgiot_evidence:readCert() of
        {ok, Result} ->
            {200, Result};
        {error, Reason} ->
            {error, Reason}
    end;

%% evidence 概要: 查询边缘网关及其子设备 描述:查询边缘网关及其子设备
%% OperationId:get_bed
%% 请求:POST /iotapi/bed
do_request(get_bed, #{<<"id">> := Id} = _Args, #{<<"sessionToken">> := SessionToken} = _Context, _Req) ->
    get_bed(Id, SessionToken);

%% evidence 概要: 取证前处理 描述:取证前处理
%% OperationId:post_bed
%% 请求:POST /iotapi/bed
do_request(post_bed, #{<<"datatype">> := <<"liveMonitor">>} = Body, #{<<"sessionToken">> := SessionToken} = _Context, _Req) ->
    ?LOG(info, "Body ~p", [Body]),
    case dgiot_auth:get_session(SessionToken) of
        #{<<"roles">> := Roles} ->
            [#{<<"alias">> := _AppId, <<"name">> := _AppName} | _] = maps:values(Roles);
        _ -> pass
    end,
    {200, #{<<"result">> => #{<<"status">> => 0}}};

do_request(post_bed, _Body, #{<<"sessionToken">> := SessionToken} = _Context, _Req) ->
    case dgiot_auth:get_session(SessionToken) of
        #{<<"roles">> := Roles} ->
            [#{<<"alias">> := _AppId, <<"name">> := _AppName} | _] = maps:values(Roles);
        _ -> pass
    end,
    {200, #{<<"result">> => #{<<"status">> => 0}}};

%% DB 概要: 导入试卷报告
%% OperationId:testpaper
%% 请求:POST /iotapi/testpaper
do_request(post_testpaper, #{<<"productid">> := Productid, <<"file">> := FileInfo},
    #{<<"sessionToken">> := _SessionToken} = _Context, _Req) ->
    {ok, get_paper(Productid, FileInfo)};

%% evidence 概要: 增加取证报告模版 描述:新增取证报告模版
%% OperationId:post_reporttemp
%% 请求:put /iotapi/reporttemp
do_request(put_reporttemp, #{<<"nodeType">> := _NodeType, <<"devType">> := _DevType} = Body,
    #{<<"sessionToken">> := SessionToken} = _Context, _Req) ->
    ?LOG(info, "Body ~p ", [Body]),
    R = dgiot_product:create_product(Body, SessionToken),
    ?LOG(info, "R ~p ", [R]),
    R;

%% DB 概要: 导入质检报告模版 描述:word/pdf质检报告
%% OperationId:reporttemp
%% 请求:POST /iotapi/reporttemp
do_request(post_reporttemp, #{<<"name">> := Name, <<"devType">> := DevType, <<"config">> := Config, <<"file">> := FileInfo},
    #{<<"sessionToken">> := SessionToken} = _Context, #{headers := #{<<"origin">> := Uri}} = _Req) ->
    Neconfig = jsx:decode(Config, [{labels, binary}, return_maps]),
    DataResult =
        case maps:get(<<"contentType">>, FileInfo, <<"unknow">>) of
            ContentType when
                ContentType =:= <<"application/msword">> orelse
                    ContentType =:= <<"application/vnd.openxmlformats-officedocument.wordprocessingml.document">> orelse
                    ContentType =:= <<"application/pdf">> ->
                FullPath = maps:get(<<"fullpath">>, FileInfo),
%%                Uri = "http://" ++ dgiot_utils:to_list(dgiot_req:host(Req)) ++ ":" ++ dgiot_utils:to_list(dgiot_req:port(Req)),
                {ok, #{<<"result">> => do_report(Neconfig, DevType, Name, SessionToken, FullPath, dgiot_utils:to_list(Uri))}};
            ContentType ->
                {error, <<"contentType error, contentType:", ContentType/binary>>}
        end,
    case DataResult of
        {ok, Data} ->
            {ok, Data};
        Error -> Error
    end;

%% evidence 概要: 增加取证报告 描述:新增取证报告
%% OperationId:get_report
%% 请求:GET /iotapi/report
do_request(get_report, #{<<"id">> := Id} = Body, #{<<"sessionToken">> := SessionToken} = _Context, _Req) ->
    ?LOG(info, "Body ~p ", [Body]),
    get_report(Id, SessionToken);

%% evidence 概要: 增加取证报告 描述:新增取证报告
%% OperationId:post_report
%% 请求:POST /iotapi/report
do_request(post_report, #{<<"name">> := _Name, <<"product">> := _ProductId,
    <<"basedata">> := _Basedata} = Body, #{<<"sessionToken">> := SessionToken} = _Context, _Req) ->
%%    ?LOG(info, "Body ~p ", [Body]),
    post_report(Body, SessionToken);


%% evidence 概要: 修改取证报告 描述:修改取证报告
%% OperationId:put_report
%% 请求:PUT /iotapi/report
do_request(put_report, #{<<"path">> := Path} = _Body, #{<<"sessionToken">> := SessionToken} = _Context, _Req) ->
    put_report(Path, SessionToken);

%% Evidence 概要: 删除取证报告 描述:删除取证报告
%% OperationId:DELETE_REPORT_REPORTID
%% 请求:GET /iotapi/report
do_request(delete_report_reportid, #{<<"reportId">> := ReportId} = _Args,
    #{<<"sessionToken">> := SessionToken} = _Context, _Req) ->
    delete_report(ReportId, SessionToken);


%% evidence 概要: 查询采样点 描述:查询采样点
%% OperationId:get_point
%% 请求:GET /iotapi/point
do_request(get_point, _Args, #{<<"sessionToken">> := SessionToken} = _Context, _Req) ->
    {200, #{<<"result">> => get_point(_Args, SessionToken)}};

%% evidence 概要: 标识采样点 描述:标识采样点
%% OperationId:post_point
%% 请求:POST /iotapi/point
do_request(post_point, Body, #{<<"sessionToken">> := SessionToken} = _Context, _Req) ->
    post_point(Body, SessionToken),
    {200, #{<<"result">> => ok}};

do_request(get_capture, Args, _Context, _Req) ->
    dgiot_evidence:get_capture(Args);

%% evidence 概要: 配置管理API 描述:配置管理API
%% OperationId:post_reload
%% 请求:GET /iotapi/reload
do_request(post_file_reload, #{<<"action">> := Action} = Body, _Context, _Req) ->
    dgiot_evidence:file_reload(Action, Body);

%% evidence 概要: 文件统计信息 描述:文件统计信息
%% OperationId:get_list_dir
%% 请求:GET /iotapi/list_dir
do_request(get_file_stat, _Body, _Context, _Req) ->
    dgiot_evidence:file_stat();

%% evidence 概要: 获取文件列表 描述:获取文件列表
%% OperationId:get_list_dir
%% 请求:GET /iotapi/list_dir
do_request(get_list_dir, #{<<"path">> := Path} = _Body, _Context, _Req) ->
    dgiot_evidence:list_dir(Path);

%% evidence 概要: 获取文件信息 描述:获取文件信息
%% OperationId:get_file_info
%% 请求:GET /iotapi/file_info
do_request(get_file_info, #{<<"path">> := Path} = _Body, _Context, _Req) ->
    dgiot_evidence:file_info(Path);

%% evidence 概要: 删除文件 描述:删除文件
%% OperationId:delete_file
%% 请求:GET /iotapi/delete_file
do_request(delete_file_info, #{<<"path">> := Path} = _Body, #{<<"sessionToken">> := SessionToken} = _Context, _Req) ->
    dgiot_evidence:delete_file(Path, SessionToken);

%%  服务器不支持的API接口
do_request(_OperationId, _Args, _Context, _Req) ->
    {error, <<"Not Allowed.">>}.

do_report(Config, DevType, Name, SessionToken, FullPath, Uri) ->
    case dgiot_httpc:fileUpload(Uri ++ "/WordController/fileUpload", dgiot_utils:to_list(FullPath)) of
        {ok, #{<<"content">> := Content, <<"success">> := true}} ->
            Url = cow_uri:urlencode(base64:encode(Content)),
            WordPreview = Uri ++ "/onlinePreview?url=" ++ dgiot_utils:to_list(Url) ++ "&officePreviewType=image",
            List = dgiot_html:find(WordPreview, {<<"img">>, {<<"class">>, <<"my-photo">>}}, <<"data-src">>),
            WordUrl = Uri ++ "/wordServer/" ++ dgiot_utils:to_list(filename:basename(FullPath)),
            CategoryId = maps:get(<<"category">>, Config, <<"d6ad425529">>),
            Producttempid = maps:get(<<"producttemplet">>, Config, <<"">>),
            ProductParentId =
                case dgiot_product:create_product(#{
                    <<"name">> => Name,
                    <<"devType">> => DevType,
                    <<"desc">> => <<"0">>,
                    <<"nodeType">> => 1,
                    <<"channel">> => #{<<"type">> => 1, <<"tdchannel">> => <<"24b9b4bc50">>, <<"taskchannel">> => <<"0edaeb918e">>, <<"otherchannel">> => [<<"11ed8ad9f2">>]},
                    <<"netType">> => <<"Evidence">>,
                    <<"category">> => #{<<"objectId">> => CategoryId, <<"__type">> => <<"Pointer">>, <<"className">> => <<"Category">>},
                    <<"producttemplet">> => #{<<"objectId">> => Producttempid, <<"__type">> => <<"Pointer">>, <<"className">> => <<"ProductTemplet">>},
                    <<"config">> => Config,
                    <<"thing">> => #{},
                    <<"productSecret">> => license_loader:random(),
                    <<"dynamicReg">> => true}, SessionToken) of
                    {_, #{<<"objectId">> := ProductId}} ->
                        ProductId;
                    _ ->
                        dgiot_parse:get_productid(CategoryId, DevType, Name)
                end,
            lists:foldl(fun(ImageUrl, Acc) ->
%%                <<"https://192.168.0.183:5094/wordServer/20211112142832/1.jpg">>
                NewImageUrl = dgiot_utils:get_url_path(ImageUrl),
                case binary:split(filename:basename(ImageUrl), <<$.>>, [global, trim]) of
                    [Index, _] ->
                        Acc ++ [dgiot_evidence:create_report(ProductParentId, Config, Index, NewImageUrl, WordUrl, SessionToken)]
                end
                        end, [], List);
        _Oth ->
            io:format("_Oth ~p~n", [_Oth]),
            []
    end.

get_paper(_ProductId, FileInfo) ->
    Path = maps:get(<<"fullpath">>, FileInfo),
    Fun = fun(Row) ->
        Map = jiffy:encode(#{<<"1">> => dgiot_utils:to_binary(Row)}),
        [V | _] = maps:values(jsx:decode(Map, [{labels, binary}, return_maps])),
        V
          end,
    List = dgiot_utils:read(Path, Fun, []),
%%    Title = lists:nth(1, List),
%    DeviceId = dgiot_parse:get_deviceid(ProductId, dgiot_utils:to_md5(Title)),
    Single = dgiot_utils:split_list(<<"一、单选题"/utf8>>, <<"二、多选题"/utf8>>, false, List, []),
    Multiple = dgiot_utils:split_list(<<"二、多选题"/utf8>>, <<"三、判断题"/utf8>>, false, List, []),
    Judge = dgiot_utils:split_list(<<"三、判断题"/utf8>>, <<"四、案例题"/utf8>>, false, List, []),
    Cases = dgiot_utils:split_list(<<"四、案例题"/utf8>>, <<"四、案例题222"/utf8>>, false, List, []),
    Cases1 = get_case(Cases, {<<"">>, []}, []),
    {Single_question, _} = get_simple(Single, {[], #{}}),
    {Multiple_question, _} = get_simple(Multiple, {[], #{}}),
    {Judge_question, _} = get_simple(Judge, {[], #{}}),
    Paper = Single_question ++ Multiple_question ++ Judge_question ++ Cases1,
%    create_device(DeviceId, ProductId, Title, Paper),
    #{
        <<"paper">> => Paper
    }.

get_simple([], {Acc, Map}) ->
    {Acc, Map};
get_simple([Row | List], {Acc, Map}) ->
    case Row of
        <<"A."/utf8, _Result/binary>> ->
            get_simple(List, {Acc, Map#{<<"A"/utf8>> => Row}});
        <<"B."/utf8, _Result/binary>> ->
            get_simple(List, {Acc, Map#{<<"B"/utf8>> => Row}});
        <<"C."/utf8, _Result/binary>> ->
            get_simple(List, {Acc, Map#{<<"C"/utf8>> => Row}});
        <<"D."/utf8, _Result/binary>> ->
            get_simple(List, {Acc, Map#{<<"D"/utf8>> => Row}});
        <<"E."/utf8, _Result/binary>> ->
            get_simple(List, {Acc, Map#{<<"E"/utf8>> => Row}});
        <<"F."/utf8, _Result/binary>> ->
            get_simple(List, {Acc, Map#{<<"F"/utf8>> => Row}});
        <<"答案："/utf8, Result/binary>> ->
            R1 = re:replace(Result, <<"\n">>, <<>>, [{return, binary}]),
            R = re:replace(R1, <<" ">>, <<>>, [{return, binary}]),
            get_simple(List, {Acc ++ [Map#{<<"Answer"/utf8>> => R}], #{}});
        <<"答案:"/utf8, Result/binary>> ->
            R1 = re:replace(Result, <<"\n">>, <<>>, [{return, binary}]),
            R = re:replace(R1, <<" ">>, <<>>, [{return, binary}]),
            get_simple(List, {Acc ++ [Map#{<<"Answer"/utf8>> => R}], #{}});
        <<"\n"/utf8, _/binary>> ->
            get_simple(List, {Acc, Map});
        R when size(R) > 6 ->
            get_simple(List, {Acc, Map#{<<"Question"/utf8>> => Row, <<"type">> => get_type(R)}});
        _ ->
            get_simple(List, {Acc, Map})
    end.

get_type(Question) ->
%%    io:format("~ts", [unicode:characters_to_list(Question)]),
    case re:run(Question, <<"判断"/utf8>>, [{capture, none}]) of
        match ->
            <<"判断题"/utf8>>;
        _ ->
            case re:run(Question, <<"多选"/utf8>>, [{capture, none}]) of
                match ->
                    <<"多选题"/utf8>>;
                _ ->
                    <<"单选题"/utf8>>
            end
    end.

get_case([], {Title, Acc}, Result) ->
    {Single_question, _} = get_simple(Acc, {[], #{}}),
    Result ++ [#{<<"type">> => <<"材料题"/utf8>>, <<"Question"/utf8>> => Title, <<"questions"/utf8>> => Single_question}];
get_case([Row | List], {Title, Acc}, Result) ->
    case re:run(Row, <<"背景材料"/utf8>>, [{capture, none}]) of
        match ->
            case Title of
                <<"">> ->
                    get_case(List, {Row, Acc}, Result);
                _ ->
                    {Single_question, _} = get_simple(Acc, {[], #{}}),
                    get_case(List, {Row, []}, Result ++ [#{<<"type">> => <<"材料题"/utf8>>, <<"Question"/utf8>> => Title, <<"questions"/utf8>> => Single_question}])
            end;
        _ ->
            get_case(List, {Title, Acc ++ [Row]}, Result)
    end.

%%create_device(DeviceId, ProductId, Devaddr, Paper) ->
%%    case dgiot_parse:get_object(<<"Product">>, ProductId) of
%%        {ok, #{<<"ACL">> := Acl, <<"devType">> := DevType}} ->
%%            case dgiot_parse:get_object(<<"Device">>, DeviceId) of
%%                {ok, #{<<"devaddr">> := _GWAddr}} ->
%%                    dgiot_parse:update_object(<<"Device">>, DeviceId, #{<<"basedata">> => #{<<"paper">> => Paper}, <<"status">> => <<"ONLINE">>});
%%                _ ->
%%                    dgiot_device:create_device(#{
%%                        <<"devaddr">> => dgiot_utils:to_md5(Devaddr),
%%                        <<"name">> => Devaddr,
%%                        <<"isEnable">> => true,
%%                        <<"product">> => ProductId,
%%                        <<"ACL">> => Acl,
%%                        <<"status">> => <<"ONLINE">>,
%%                        <<"location">> => #{<<"__type">> => <<"GeoPoint">>, <<"longitude">> => 120.161324, <<"latitude">> => 30.262441},
%%                        <<"brand">> => DevType,
%%                        <<"devModel">> => DevType,
%%                        <<"basedata">> =>  #{<<"paper">> => Paper}
%%                    })
%%            end;
%%        Error2 ->
%%            ?LOG(info, "Error2 ~p ", [Error2]),
%%            pass
%%    end.

post_point(#{
    <<"reportid">> := ReportId,
    <<"index">> := Index,
    <<"begin">> := Begin,
    <<"end">> := End
}, SessionToken) ->
    Query = #{<<"keys">> => [<<"count(*)">>, <<"original">>, <<"timestamp">>],
        <<"where">> => #{<<"$and">> => [#{
            <<"reportId">> => ReportId,
            <<"original.index">> => #{<<"$regex">> => Index}}]
        }
    },
    ?LOG(info, "Query ~p", [Query]),
    case dgiot_parse:query_object(<<"Evidence">>, Query,
        [{"X-Parse-Session-Token", SessionToken}], [{from, rest}]) of
        {ok, #{<<"count">> := Count, <<"results">> := Result}} when Count > 0 ->
            lists:map(fun(#{<<"objectId">> := ObjectId, <<"original">> := Original}) ->
                dgiot_parse:update_object(<<"Evidence">>, ObjectId,
                    #{<<"original">> => maps:without([<<"index">>], Original)},
                    [{"X-Parse-Session-Token", SessionToken}], [{from, rest}])
                      end, Result);
        _R ->
            pass
    end,
    Query1 = #{<<"keys">> => [<<"count(*)">>, <<"original">>, <<"timestamp">>],
        <<"where">> => #{<<"$and">> => [#{
            <<"reportId">> => ReportId,
            <<"timestamp">> => #{<<"$gte">> => Begin, <<"$lte">> => End}}]
        }
    },
    case dgiot_parse:query_object(<<"Evidence">>, Query1,
        [{"X-Parse-Session-Token", SessionToken}], [{from, rest}]) of
        {ok, #{<<"count">> := Count1, <<"results">> := Result1}} when Count1 > 0 ->
            ?LOG(info, "Result1 ~p", [Result1]),
            lists:map(fun(#{<<"objectId">> := ObjectId, <<"original">> := Original}) ->
                dgiot_parse:update_object(<<"Evidence">>, ObjectId,
                    #{<<"original">> => Original#{<<"index">> => Index}},
                    [{"X-Parse-Session-Token", SessionToken}], [{from, rest}])
                      end, Result1);
        _R2 ->
            #{}
    end.

get_point(#{
    <<"reportid">> := ReportId,
    <<"index">> := 0,
    <<"begin">> := Begin,
    <<"end">> := End
}, SessionToken) ->
    Query = #{<<"keys">> => [<<"count(*)">>, <<"original">>, <<"timestamp">>],
        <<"where">> => #{<<"$and">> => [#{
            <<"original.datatype">> => #{<<"$regex">> => <<"performanceCurve">>},
            <<"reportId">> => ReportId,
            <<"timestamp">> => #{<<"$gte">> => Begin, <<"$lte">> => End}}]
        }
    },
    case dgiot_parse:query_object(<<"Evidence">>, Query,
        [{"X-Parse-Session-Token", SessionToken}], [{from, rest}]) of
        {ok, #{<<"count">> := Count, <<"results">> := Result}} when Count > 0 ->
            lists:foldl(fun(X, Acc) ->
                case X of
                    #{<<"original">> := #{<<"data">> := Data}, <<"timestamp">> := Time} ->
                        case maps:find(0, Acc) of
                            {ok, OldData} ->
                                #{<<"startAt">> := StartAt, <<"endAt">> := EndAt} = OldData,
                                NewData = lists:foldl(fun(Key, Acc1) ->
                                    case Key of
                                        <<"startAt">> -> Acc1;
                                        <<"endAt">> -> Acc1;
                                        _ ->
                                            Value = (maps:get(Key, Data, 0) + maps:get(Key, OldData, 0)) / 2,
                                            Acc1#{Key => Value}
                                    end
                                                      end, OldData, maps:keys(Data)),
                                Acc#{0 => NewData#{
                                    <<"startAt">> => min(StartAt, Time),
                                    <<"endAt">> => max(EndAt, Time)}
                                };
                            _ ->
                                NewData = Data#{<<"startAt">> => Time, <<"endAt">> => Time},
                                Acc#{0 => NewData}
                        end;
                    _ -> Acc
                end
                        end, #{}, Result);
        _R2 ->
            #{}
    end;

get_point(#{
    <<"reportid">> := ReportId,
    <<"index">> := 65535
}, SessionToken) ->
    Query = #{<<"keys">> => [<<"count(*)">>, <<"original">>, <<"timestamp">>],
        <<"where">> => #{<<"$and">> => [#{
            <<"original.datatype">> => #{<<"$regex">> => <<"performanceCurve">>},
            <<"reportId">> => ReportId,
            <<"original.index">> => #{<<"$regex">> => <<".+">>}}]
        }
    },
    ?LOG(info, "Query ~p", [Query]),
    case dgiot_parse:query_object(<<"Evidence">>, Query,
        [{"X-Parse-Session-Token", SessionToken}], [{from, rest}]) of
        {ok, #{<<"count">> := Count, <<"results">> := Result}} when Count > 0 ->
            get_point_average(Result);
        _R2 ->
            #{}
    end;

get_point(#{
    <<"reportid">> := ReportId,
    <<"index">> := Index
}, SessionToken) ->
    Query = #{<<"keys">> => [<<"count(*)">>, <<"original">>, <<"timestamp">>],
        <<"where">> => #{<<"$and">> => [#{
            <<"datatype">> => <<"performanceCurve">>,
            <<"reportId">> => ReportId,
            <<"original.index">> => Index}]
        }
    },
    ?LOG(info, "Query ~p", [Query]),
    case dgiot_parse:query_object(<<"Evidence">>, Query,
        [{"X-Parse-Session-Token", SessionToken}], [{from, rest}]) of
        {ok, #{<<"count">> := Count, <<"results">> := Result}} when Count > 0 ->
            get_point_average(Result);
        _R2 ->
            #{}
    end.

get_point_average(Result) ->
    lists:foldl(fun(X, Acc) ->
        case X of
            #{<<"original">> := #{<<"index">> := Index, <<"data">> := Data}, <<"timestamp">> := Time} ->
                case maps:find(Index, Acc) of
                    {ok, OldData} ->
                        #{<<"startAt">> := StartAt, <<"endAt">> := EndAt} = OldData,
                        NewData = lists:foldl(fun(Key, Acc1) ->
                            case Key of
                                <<"startAt">> -> Acc1;
                                <<"endAt">> -> Acc1;
                                _ ->
                                    Value = (maps:get(Key, Data, 0) + maps:get(Key, OldData, 0)) / 2,
                                    Acc1#{Key => Value}
                            end
                                              end, OldData, maps:keys(Data)),
                        Acc#{Index => NewData#{
                            <<"startAt">> => min(StartAt, Time),
                            <<"endAt">> => max(EndAt, Time)}
                        };
                    _ ->
                        NewData = Data#{<<"startAt">> => Time, <<"endAt">> => Time},
                        Acc#{Index => NewData}
                end;
            _ -> Acc
        end
                end, #{}, Result).

get_bed(Id, SessionToken) ->
    case dgiot_parse:get_object(<<"Device">>, Id,
        [{"X-Parse-Session-Token", SessionToken}], [{from, rest}]) of
        {ok, #{<<"parentId">> := #{<<"objectId">> := ParnetId}}} ->
            case dgiot_parse:get_object(<<"Device">>, ParnetId,
                [{"X-Parse-Session-Token", SessionToken}], [{from, rest}]) of
                {ok, #{<<"basedata">> := #{<<"bedaddr">> := DtuAddr}}} ->
                    Query = #{<<"keys">> => [<<"name">>, <<"objectId">>],
                        <<"where">> => #{<<"route.", DtuAddr/binary>> => #{<<"$regex">> => <<".+">>}},
                        <<"order">> => <<"devaddr">>, <<"limit">> => 256,
                        <<"include">> => <<"product">>},
                    ?LOG(info, "Query ~p ", [Query]),
                    dgiot_parse:query_object(<<"Device">>, Query, [{"X-Parse-Session-Token", SessionToken}], [{from, rest}]);
                R1 ->
                    R1
            end;
        R2 ->
            R2
    end.


delete_report(ReportId, SessionToken) ->
    case dgiot_parse:query_object(<<"Device">>, #{<<"where">> => #{<<"parentId">> => ReportId}},
        [{"X-Parse-Session-Token", SessionToken}], [{from, rest}]) of
        {ok, #{<<"results">> := Devices}} when length(Devices) > 0 ->
            lists:map(fun(#{<<"objectId">> := ObjectId}) ->
                dgiot_parse:del_object(<<"Device">>, ObjectId,
                    [{"X-Parse-Session-Token", SessionToken}], [{from, rest}])
                      end, Devices),
            dgiot_parse:del_object(<<"Device">>, ReportId,
                [{"X-Parse-Session-Token", SessionToken}], [{from, rest}]);
        _ ->
            dgiot_parse:del_object(<<"Device">>, ReportId,
                [{"X-Parse-Session-Token", SessionToken}], [{from, rest}])
    end.


put_report(Path, SessionToken) ->
    [_, _, FileApp, FileName] = re:split(Path, <<"/">>),
    case dgiot_parse:query_object(<<"_Role">>, #{<<"where">> => #{<<"name">> => FileApp},
        <<"limit">> => 1}, [{"X-Parse-Session-Token", SessionToken}], [{from, rest}]) of
        {ok, #{<<"results">> := [#{<<"name">> := AppName, <<"config">> := Config} | _]}} ->
            Dir = maps:get(<<"home">>, Config),
            case filelib:is_dir(Dir) of
                true ->
                    Root = dgiot_evidence:get_filehome(unicode:characters_to_list(Dir)),
                    case AppName of
                        FileApp ->
                            NewPath = unicode:characters_to_list(FileApp) ++ "/" ++ unicode:characters_to_list(FileName),
                            file:delete(Root ++ "/Product.json"),
                            file:delete(Root ++ "/Device.json"),
                            file:delete(Root ++ "/Evidence.json"),
                            case dgiot_utils:post_file(Root, NewPath) of
                                {ok, _} ->
                                    {_, R1} = dgiot_evidence:post_data(<<"Product">>, Root ++ "/Product.json"),
                                    {_, R2} = dgiot_evidence:post_data(<<"Device">>, Root ++ "/Device.json"),
                                    {_, R3} = dgiot_evidence:post_data(<<"Evidence">>, Root ++ "/Evidence.json"),
                                    {ok, #{
                                        <<"Product">> => #{<<"result">> => R1},
                                        <<"Device">> => #{<<"result">> => R2},
                                        <<"Evidence">> => #{<<"result">> => R3},
                                        <<"root">> => unicode:characters_to_binary(Root ++ "/" ++ NewPath),
                                        <<"file">> => unicode:characters_to_binary(Root ++ "/" ++ NewPath),
                                        <<"url">> => unicode:characters_to_binary(NewPath)
                                    }};
                                Error -> Error
                            end;
                        false -> {error, #{
                            <<"dir">> => unicode:characters_to_binary(unicode:characters_to_list(Dir)),
                            <<"appname">> => unicode:characters_to_binary(unicode:characters_to_list(AppName)),
                            <<"filename">> => unicode:characters_to_binary(unicode:characters_to_list(FileApp))
                        }
                        }
                    end;
                _ ->
                    {error, #{
                        <<"dir">> => unicode:characters_to_binary(unicode:characters_to_list(Dir)),
                        <<"appname">> => unicode:characters_to_binary(unicode:characters_to_list(AppName)),
                        <<"filename">> => unicode:characters_to_binary(unicode:characters_to_list(FileApp))
                    }}
            end;
        _ -> {error, <<"not find">>}
    end.


get_report(Id, SessionToken) ->
    ?LOG(info, "Id ~p SessionToken ~p", [Id, SessionToken]),
    case dgiot_parse:query_object(<<"Device">>, #{
        <<"where">> => #{<<"$or">> => [#{<<"objectId">> => Id}, #{<<"parentId">> => Id}]}}) of
        {ok, #{<<"results">> := Devices}} ->
            {DAcc0, PAcc0, FAcc4} =
                lists:foldl(fun(Device, {DAcc, PAcc, FAcc}) ->
                    #{<<"objectId">> := ProductId} = maps:get(<<"product">>, Device),
                    {ok, Product} = dgiot_parse:get_object(<<"Product">>, ProductId),
                    FAcc1 =
                        case maps:get(<<"icon">>, Product, <<"">>) of
                            <<"">> -> FAcc;
                            Ico -> FAcc ++ [Ico]
                        end,
                    FAcc2 =
                        case maps:get(<<"config">>, Product, <<"">>) of
                            <<"">> -> FAcc1;
                            #{<<"layer">> := Layer} ->
                                case maps:get(<<"backgroundImage">>, Layer, <<"">>) of
                                    <<"">> -> FAcc1;
                                    ProductImage -> FAcc1 ++ [ProductImage]
                                end;
                            _ -> FAcc1
                        end,
                    FAcc3 =
                        case maps:get(<<"basedata">>, Device, <<"">>) of
                            <<"">> -> FAcc2;
                            #{<<"layer">> := Layer1} ->
                                case maps:get(<<"backgroundImage">>, Layer1, <<"">>) of
                                    <<"">> -> FAcc2;
                                    DeviceImage -> FAcc2 ++ [DeviceImage]
                                end;
                            _ -> FAcc1
                        end,
                    {DAcc ++ [maps:without([<<"createdAt">>, <<"updatedAt">>], Device)],
                            PAcc ++ [maps:without([<<"createdAt">>, <<"updatedAt">>], Product)], FAcc3}
                            end, {[], [], []}, Devices),
            case dgiot_parse:query_object(<<"Evidence">>, #{
                <<"where">> => #{<<"reportId">> => Id}}) of
                {ok, #{<<"results">> := Evidences}} ->
                    {EAcc0, FAcc0} =
                        lists:foldl(fun(Evidence, {EAcc, FAcc5}) ->
                            FAcc6 =
                                case maps:get(<<"original">>, Evidence, <<"">>) of
                                    <<"">> -> FAcc5;
                                    #{<<"data">> := Data, <<"datatype">> := DataType}
                                        when <<"liveMonitor">> =/= DataType ->
                                        case maps:get(<<"src">>, Data, <<"">>) of
                                            <<"">> -> FAcc5;
                                            Src -> FAcc5 ++ [Src]
                                        end
                                end,
                            {EAcc ++ [maps:without([<<"createdAt">>, <<"updatedAt">>], Evidence)], FAcc6}
                                    end, {[], FAcc4}, Evidences),
                    dgiot_evidence:get_report_package(Id, DAcc0, PAcc0, EAcc0, FAcc0, SessionToken);
                Error1 -> Error1
            end;
        Error -> Error
    end.

post_report(#{<<"name">> := Name, <<"product">> := ProductId, <<"basedata">> := Basedata}, SessionToken) ->
    case dgiot_parse:get_object(<<"Product">>, ProductId, [{"X-Parse-Session-Token", SessionToken}], [{from, rest}]) of
        {ok, #{<<"ACL">> := Acl, <<"objectId">> := ProductId}} ->
            case dgiot_parse:query_object(<<"Device">>, #{<<"where">> => #{<<"name">> => Name, <<"product">> => ProductId}},
                [{"X-Parse-Session-Token", SessionToken}], [{from, rest}]) of
                {ok, #{<<"results">> := Results}} when length(Results) == 0 ->
                    <<DtuAddr:12/binary, _/binary>> = license_loader:random(),
                    {ok, #{<<"objectId">> := DeviceId}} =
                        dgiot_device:create_device(#{
                            <<"devaddr">> => DtuAddr,
                            <<"name">> => Name,
                            <<"ip">> => <<"">>,
                            <<"product">> => ProductId,
                            <<"ACL">> => Acl,
                            <<"status">> => <<"ONLINE">>,
                            <<"brand">> => <<"数蛙桌面采集网关"/utf8>>,
                            <<"devModel">> => <<"SW_WIN_CAPTURE">>,
                            <<"basedata">> => Basedata
                        }),
                    case dgiot_parse:query_object(<<"View">>, #{<<"where">> => #{<<"key">> => ProductId, <<"class">> => <<"Product">>}}, [{"X-Parse-Session-Token", SessionToken}], [{from, rest}]) of
                        {ok, #{<<"results">> := Views}} ->
                            ViewRequests =
                                lists:foldl(fun(View, Acc) ->
                                    NewDict = maps:without([<<"createdAt">>, <<"objectId">>, <<"updatedAt">>], View),
                                    Acc ++ [#{
                                        <<"method">> => <<"POST">>,
                                        <<"path">> => <<"/classes/View">>,
                                        <<"body">> => NewDict#{
                                            <<"key">> => DeviceId,
                                            <<"class">> => <<"Device">>}
                                    }]
                                            end, [], Views),
                            dgiot_parse:batch(ViewRequests),
                            {ok, #{<<"result">> => <<"success">>}};
                        _R1 ->
                            ?LOG(info, "R1 ~p", [_R1]),
                            {error, <<"report exist">>}
                    end;
                _R2 ->
                    ?LOG(info, "R2 ~p", [_R2]),
                    {error, <<"report exist">>}
            end;
        _R3 ->
            ?LOG(info, "R3 ~p", [_R3]),
            {error, <<"report exist">>}
    end.


