%%--------------------------------------------------------------------
%% Copyright (c) 2017-2021 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-module(emqx_relup).

%% NOTE: DO NOT remove this `-include`.
%% We use this to force this module to be upgraded every release.
-include("emqx_release.hrl").

-export([ post_release_upgrade/2
        , post_release_downgrade/2
        ]).

-define(INFO(FORMAT), io:format("[emqx_relup] " ++ FORMAT ++ "~n")).
-define(INFO(FORMAT, ARGS), io:format("[emqx_relup] " ++ FORMAT ++ "~n", ARGS)).

%% What to do after upgraded from an old release vsn.
post_release_upgrade(FromRelVsn, _) ->
    {_, CurrRelVsn} = ?EMQX_RELEASE,
    ?INFO("emqx has been upgraded from ~s to ~s!", [FromRelVsn, CurrRelVsn]),
    reload_components().

%% What to do after downgraded to an old release vsn.
post_release_downgrade(ToRelVsn, _) ->
    {_, CurrRelVsn} = ?EMQX_RELEASE,
    ?INFO("emqx has been downgraded from ~s to ~s!", [CurrRelVsn, ToRelVsn]),
    reload_components().

-ifdef(EMQX_ENTERPRISE).
reload_components() ->
    ?INFO("reloading resource providers ..."),
    emqx_rule_engine:load_providers(),
    ?INFO("reloading module providers ..."),
    emqx_modules:load_providers(),
    ?INFO("loading plugins ..."),
    _ = load_plugins(),
    %% upgrade from e4.3.0~4.3.4 to >=4.3.5 requires persistent default modules after upgrade.
    %% because the emqx_modules' env is lost when pre_upgrade.
    %% must after emqx_modules plugin load(for loading emqx_modules' env)
    case erlang:function_exported(emqx_modules, persistent_default_modules, 0) of
        true ->
            ?INFO("persistent default modules ..."),
            emqx_modules:persistent_default_modules();
        false -> ok
    end,
    ok.

-else.
reload_components() ->
    ?INFO("reloading resource providers ..."),
    emqx_rule_engine:load_providers(),
    ?INFO("loading plugins ..."),
    _ = load_plugins(),
    ok.

-endif.

load_plugins() ->
    case erlang:function_exported(emqx_plugins, force_load, 0) of
        true -> emqx_plugins:force_load();
        false -> emqx_plugins:load()
    end.
